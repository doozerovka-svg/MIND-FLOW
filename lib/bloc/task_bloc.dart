import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../config/app_config.dart';
import '../models/task_model.dart';
import '../repositories/task_repository.dart';
import '../services/audio_recorder_service.dart';
import '../services/llm_service.dart';
import '../services/stt_service.dart';
import '../services/vad_processor.dart';
import 'task_event.dart';
import 'task_state.dart';

class TaskBloc extends Bloc<TaskEvent, TaskState> {
  final TaskRepository _repository;
  final AudioRecorderService _recorderService;
  final SttService _sttService;
  final LlmService _llmService;
  
  VadProcessor? _vadProcessor;
  StreamSubscription<List<Task>>? _tasksSubscription;

  TaskBloc({
    required TaskRepository repository,
    required AudioRecorderService recorderService,
    required SttService sttService,
    required LlmService llmService,
  })  : _repository = repository,
        _recorderService = recorderService,
        _sttService = sttService,
        _llmService = llmService,
        super(TaskInitial()) {
    on<LoadTasks>(_onLoadTasks);
    on<StartRecording>(_onStartRecording);
    on<StopRecording>(_onStopRecording);
    on<ToggleConfigMode>(_onToggleConfigMode);
  }

  Future<void> _onLoadTasks(LoadTasks event, Emitter<TaskState> emit) async {
    emit(TaskLoading());
    
    // Cancel any previous active subscription
    await _tasksSubscription?.cancel();
    
    // Subscribe to reactive database updates from Isar
    _tasksSubscription = _repository.watchTasks().listen((taskList) {
      add(_UpdateTasksList(taskList));
    });
  }

  // Private event to handle updates from the Isar DB reactive stream
  Future<void> _onUpdateTasksList(_UpdateTasksList event, Emitter<TaskState> emit) async {
    emit(TasksLoaded(event.tasks, AppConfig.inputMode));
  }

  // Helper handler for updates
  void _onLoadTasksInternal() {
    on<_UpdateTasksList>((event, emit) {
      emit(TasksLoaded(event.tasks, AppConfig.inputMode));
    });
  }

  Future<void> _onStartRecording(StartRecording event, Emitter<TaskState> emit) async {
    if (_recorderService.isRecording) return;
    
    try {
      emit(RecordingInProgress());
      
      // Trigger short tactile feedback for recording start
      HapticFeedback.mediumImpact();

      await _recorderService.startRecording();
      
      // Initialize WebRTC VAD processor
      _vadProcessor = VadProcessor(
        onSilenceDetected: () {
          // Callback when silence is detected for 1.5 seconds: automatically trigger StopRecording event
          add(StopRecording());
        },
      );
      
      // Feed recording stream to VAD processor
      _vadProcessor!.startProcessing(_recorderService.pcmStream);
    } catch (e) {
      HapticFeedback.vibrate();
      emit(TaskFailure('Failed to start recording: $e'));
      _reloadTasks();
    }
  }

  Future<void> _onStopRecording(StopRecording event, Emitter<TaskState> emit) async {
    if (!_recorderService.isRecording) return;

    String? audioPath;
    try {
      emit(ProcessingSpeech());
      
      // Stop VAD and retrieve audio file path
      _vadProcessor?.stopProcessing();
      _vadProcessor?.dispose();
      _vadProcessor = null;

      audioPath = await _recorderService.stopRecording();
      
      if (audioPath == null) {
        // Empty recording or misfire
        HapticFeedback.vibrate(); // Reject with haptic response
        emit(TaskInitial());
        _reloadTasks();
        return;
      }

      // Step 1: Speech-to-Text Transcription
      final String transcript = await _sttService.transcribe(audioPath);
      
      if (transcript.isEmpty) {
        // Empty transcript rejection
        HapticFeedback.vibrate();
        emit(TaskInitial());
        _reloadTasks();
        return;
      }

      // Step 2: Intent Classification (CREATE vs UPDATE)
      final String intent = await _llmService.classifyIntent(transcript);

      if (intent == 'UPDATE') {
        // Find most relevant task in database
        final Task? contextTask = await _repository.findRelevantTask(transcript);
        
        if (contextTask != null) {
          // Call LLM with existing task context
          final String updatedJson = await _llmService.processTask(transcript, contextTask: contextTask);
          
          // Safely apply JSON updates to the DB
          await _repository.processIncomingTranscript(transcript, updatedJson);
          emit(const TaskSuccess('Задача обновлена'));
        } else {
          // No context task found, fallback to CREATE
          final String structuredJson = await _llmService.processTask(transcript);
          await _repository.processIncomingTranscript(transcript, structuredJson);
          emit(const TaskSuccess('Задача создана'));
        }
      } else {
        // CREATE intent
        final String structuredJson = await _llmService.processTask(transcript);
        await _repository.processIncomingTranscript(transcript, structuredJson);
        emit(const TaskSuccess('Задача создана'));
      }
    } on OfflineException catch (e) {
      // Offline scenario recovery: save the audio and create an offline task
      HapticFeedback.vibrate();
      
      try {
        final offlineTask = Task()
          ..title = 'Ожидает синхронизации: Голосовая запись'
          ..hasReminder = false
          ..isComplex = false
          ..steps = []
          ..needsSync = true
          ..localAudioPath = audioPath ?? '';
        
        await _repository.saveTask(offlineTask);
      } catch (_) {}
      
      emit(TaskSuccess(e.message));
    } catch (e) {
      // LLM or system parsing error fallback: save raw transcript directly
      HapticFeedback.vibrate();
      emit(TaskFailure('Ошибка: $e. Задача сохранена в исходном виде.'));
    } finally {
      _reloadTasks();
    }
  }

  Future<void> _onToggleConfigMode(ToggleConfigMode event, Emitter<TaskState> emit) async {
    AppConfig.inputMode = event.mode;
    _reloadTasks();
  }

  void _reloadTasks() {
    // Helper to trigger load tasks
    final state = this.state;
    if (state is TasksLoaded) {
      add(LoadTasks());
    } else {
      add(LoadTasks());
    }
  }

  @override
  Future<void> close() async {
    await _tasksSubscription?.cancel();
    _vadProcessor?.dispose();
    _recorderService.dispose();
    return super.close();
  }
}

// Private event class to propagate reactive Isar changes
class _UpdateTasksList extends TaskEvent {
  final List<Task> tasks;
  const _UpdateTasksList(this.tasks);

  @override
  List<Object?> get props => [tasks];
}
