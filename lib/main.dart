import 'dart:ui';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import 'bloc/task_bloc.dart';
import 'bloc/task_event.dart';
import 'bloc/task_state.dart';
import 'config/app_config.dart';
import 'data/models/task_model.dart';
import 'data/repositories/task_repository.dart';
import 'services/audio_recorder_service.dart';
import 'services/llm_service.dart';
import 'services/stt_service.dart';
import 'package:workmanager/workmanager.dart';
import 'services/notification_service.dart';
import 'services/sync_worker.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set system navigation overlay colors
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFF09090B),
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  // Initialize Isar DB
  final dir = await getApplicationDocumentsDirectory();
  final isar = await Isar.open(
    [TaskSchema],
    directory: dir.path,
  );

  // Initialize Notifications
  await NotificationService.init();

  // Initialize Workmanager
  await Workmanager().initialize(
    callbackDispatcher,
    isInDebugMode: false,
  );
  
  // Register recurring background sync task
  await Workmanager().registerPeriodicTask(
    "1",
    syncTaskName,
    inputData: {'directory': dir.path},
    frequency: const Duration(minutes: 15),
  );

  // Initialize Services & Repositories
  final repository = TaskRepository(isar);
  final recorderService = AudioRecorderService();
  final sttService = OpenAiWhisperService();
  final llmService = LlmService();

  runApp(MyApp(
    repository: repository,
    recorderService: recorderService,
    sttService: sttService,
    llmService: llmService,
  ));
}

class MyApp extends StatelessWidget {
  final TaskRepository repository;
  final AudioRecorderService recorderService;
  final SttService sttService;
  final LlmService llmService;

  const MyApp({
    super.key,
    required this.repository,
    required this.recorderService,
    required this.sttService,
    required this.llmService,
  });

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => TaskBloc(
        repository: repository,
        recorderService: recorderService,
        sttService: sttService,
        llmService: llmService,
      )..add(LoadTasks()),
      child: MaterialApp(
        title: 'MIND FLOW',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: const Color(0xFF09090B),
          fontFamily: 'Outfit',
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFF6366F1),
            secondary: Color(0xFFA5B4FC),
            surface: Color(0xFF18181B),
            background: Color(0xFF09090B),
          ),
          useMaterial3: true,
        ),
        home: const HomeScreen(),
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late AnimationController _waveController;
  final TextEditingController _openAiKeyController = TextEditingController();
  final TextEditingController _deepSeekKeyController = TextEditingController();
  bool _showSettings = false;

  @override
  void initState() {
    super.initState();
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    
    // Load existing keys from config into controllers
    _openAiKeyController.text = AppConfig.openAiApiKey;
    _deepSeekKeyController.text = AppConfig.deepSeekApiKey;
  }

  @override
  void dispose() {
    _waveController.dispose();
    _openAiKeyController.dispose();
    _deepSeekKeyController.dispose();
    super.dispose();
  }

  void _saveSettings() {
    setState(() {
      AppConfig.openAiApiKey = _openAiKeyController.text.trim();
      AppConfig.deepSeekApiKey = _deepSeekKeyController.text.trim();
      _showSettings = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Настройки сохранены'),
        backgroundColor: Color(0xFF6366F1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Background subtle glowing gradients
          Positioned(
            top: -100,
            left: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF6366F1).withOpacity(0.15),
                    blurRadius: 100,
                    spreadRadius: 50,
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: -50,
            right: -50,
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFA5B4FC).withOpacity(0.12),
                    blurRadius: 80,
                    spreadRadius: 40,
                  ),
                ],
              ),
            ),
          ),

          // Main content
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header Panel
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'MIND FLOW',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -1.0,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _getFormattedDate(),
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.white.withOpacity(0.5),
                            ),
                          ),
                        ],
                      ),
                      // Settings Button
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _showSettings = !_showSettings;
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withOpacity(0.04),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.08),
                            ),
                          ),
                          child: const Icon(
                            Icons.tune_rounded,
                            size: 20,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Task List Stream Builder
                Expanded(
                  child: BlocBuilder<TaskBloc, TaskState>(
                    builder: (context, state) {
                      if (state is TaskLoading) {
                        return const Center(
                          child: CircularProgressIndicator(color: Color(0xFF6366F1)),
                        );
                      } else if (state is TasksLoaded) {
                        final tasks = state.tasks;
                        if (tasks.isEmpty) {
                          return const Center(
                            child: Padding(
                              padding: EdgeInsets.symmetric(horizontal: 40.0),
                              child: Text(
                                'Свободный день.\nНажмите и удерживайте кнопку, чтобы записать задачу.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey,
                                  height: 1.5,
                                ),
                              ),
                            ),
                          );
                        }
                        return ListView.builder(
                          padding: const EdgeInsets.only(
                            left: 20,
                            right: 20,
                            bottom: 120, // offset for recorder button
                          ),
                          itemCount: tasks.length,
                          itemBuilder: (context, index) {
                            return TaskCard(task: tasks[index]);
                          },
                        );
                      } else if (state is TaskFailure) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24.0),
                            child: Text(
                              state.error,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.redAccent),
                            ),
                          ),
                        );
                      }
                      return const SizedBox();
                    },
                  ),
                ),
              ],
            ),
          ),

          // Waveform overlay when recording
          BlocBuilder<TaskBloc, TaskState>(
            builder: (context, state) {
              if (state is RecordingInProgress) {
                if (!_waveController.isAnimating) {
                  _waveController.repeat();
                }
                return Positioned.fill(
                  child: IgnorePointer(
                    child: Container(
                      color: Colors.black.withOpacity(0.4),
                      child: Center(
                        child: AnimatedBuilder(
                          animation: _waveController,
                          builder: (context, child) {
                            return CustomPaint(
                              painter: WaveformPainter(_waveController.value),
                              size: const Size(200, 200),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                );
              } else {
                _waveController.stop();
                return const SizedBox();
              }
            },
          ),

          // Processing Speech spinner overlay
          BlocBuilder<TaskBloc, TaskState>(
            builder: (context, state) {
              if (state is ProcessingSpeech) {
                return Positioned.fill(
                  child: Container(
                    color: Colors.black.withOpacity(0.65),
                    child: const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(color: Color(0xFF6366F1)),
                          SizedBox(height: 20),
                          Text(
                            'Обработка голоса ИИ...',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }
              return const SizedBox();
            },
          ),

          // Centered Recorder Action Button
          Positioned(
            bottom: 30,
            left: 0,
            right: 0,
            child: Center(
              child: RecorderButton(waveController: _waveController),
            ),
          ),

          // Sliding Glassmorphism Settings Panel
          if (_showSettings) _buildSettingsDrawer(),
        ],
      ),
    );
  }

  Widget _buildSettingsDrawer() {
    return Positioned.fill(
      child: Stack(
        children: [
          // Dismiss tap target
          GestureDetector(
            onTap: () => setState(() => _showSettings = false),
            child: Container(
              color: Colors.black.withOpacity(0.5),
            ),
          ),
          // Drawer UI
          Align(
            alignment: Alignment.bottomCenter,
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: const Color(0xFF18181B).withOpacity(0.85),
                    border: Border(
                      top: BorderSide(color: Colors.white.withOpacity(0.12)),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Настройки MIND FLOW',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          IconButton(
                            onPressed: () => setState(() => _showSettings = false),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                      const Divider(color: Colors.white12),
                      const SizedBox(height: 12),

                      // Input mode picker
                      const Text(
                        'Режим записи',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: ChoiceChip(
                              label: const Center(child: Text('Короткий тап')),
                              selected: AppConfig.inputMode == InputMode.tap,
                              onSelected: (val) {
                                if (val) {
                                  context.read<TaskBloc>().add(const ToggleConfigMode(InputMode.tap));
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ChoiceChip(
                              label: const Center(child: Text('Удержание')),
                              selected: AppConfig.inputMode == InputMode.hold,
                              onSelected: (val) {
                                if (val) {
                                  context.read<TaskBloc>().add(const ToggleConfigMode(InputMode.hold));
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // LLM Provider Picker
                      const Text(
                        'Провайдер ИИ модели',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: ChoiceChip(
                              label: const Center(child: Text('OpenAI (GPT-4o-mini)')),
                              selected: AppConfig.llmProvider == LlmProvider.openai,
                              onSelected: (val) {
                                if (val) {
                                  setState(() => AppConfig.llmProvider = LlmProvider.openai);
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ChoiceChip(
                              label: const Center(child: Text('DeepSeek (V3)')),
                              selected: AppConfig.llmProvider == LlmProvider.deepseek,
                              onSelected: (val) {
                                if (val) {
                                  setState(() => AppConfig.llmProvider = LlmProvider.deepseek);
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // OpenAI API Key input
                      const Text(
                        'OpenAI API Ключ',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _openAiKeyController,
                        obscureText: true,
                        decoration: InputDecoration(
                          hintText: 'sk-...',
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.04),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // DeepSeek API Key input
                      const Text(
                        'DeepSeek API Ключ',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _deepSeekKeyController,
                        obscureText: true,
                        decoration: InputDecoration(
                          hintText: 'ds-...',
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.04),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Save button
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _saveSettings,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF6366F1),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'Сохранить изменения',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getFormattedDate() {
    final now = DateTime.now();
    final months = [
      'Января', 'Февраля', 'Марта', 'Апреля', 'Мая', 'Июня',
      'Июля', 'Августа', 'Сентября', 'Октября', 'Ноября', 'Декабря'
    ];
    final weekdayNames = [
      'Понедельник', 'Вторник', 'Среда', 'Четверг', 'Пятница', 'Суббота', 'Воскресенье'
    ];
    return '${weekdayNames[now.weekday - 1]}, ${now.day} ${months[now.month - 1]}';
  }
}

class TaskCard extends StatefulWidget {
  final Task task;

  const TaskCard({super.key, required this.task});

  @override
  State<TaskCard> createState() => _TaskCardState();
}

class _TaskCardState extends State<TaskCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final hasReminder = widget.task.hasReminder && widget.task.reminderTimestamp != null;
    final isOffline = widget.task.needsSync == true;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isOffline ? Colors.amber.withOpacity(0.3) : Colors.white.withOpacity(0.06),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Column(
            children: [
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                title: Text(
                  widget.task.title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    decoration: isOffline ? TextDecoration.none : null,
                    color: isOffline ? Colors.amber : Colors.white,
                  ),
                ),
                subtitle: hasReminder
                    ? Padding(
                        padding: const EdgeInsets.only(top: 6.0),
                        child: Row(
                          children: [
                            Icon(
                              Icons.alarm_rounded,
                              size: 14,
                              color: const Color(0xFF6366F1).withOpacity(0.8),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _formatTimestamp(widget.task.reminderTimestamp!),
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.white.withOpacity(0.55),
                              ),
                            ),
                          ],
                        ),
                      )
                    : null,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isOffline)
                      const Tooltip(
                        message: 'Ожидает синхронизации с сетью',
                        child: Icon(Icons.sync_problem_rounded, color: Colors.amber, size: 20),
                      ),
                    if (widget.task.isComplex)
                      IconButton(
                        onPressed: () {
                          setState(() {
                            _expanded = !_expanded;
                          });
                        },
                        icon: Icon(
                          _expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                          color: Colors.white.withOpacity(0.6),
                        ),
                      ),
                  ],
                ),
              ),
              if (_expanded && widget.task.isComplex)
                Container(
                  padding: const EdgeInsets.only(left: 18, right: 18, bottom: 18),
                  child: Column(
                    children: widget.task.steps.map((step) => _buildStepItem(step)).toList(),
                  ),
                )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepItem(EmbeddedStep step) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 2, right: 10),
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFF6366F1),
            ),
          ),
          Expanded(
            child: Text(
              step.text ?? '',
              style: TextStyle(
                fontSize: 14,
                color: Colors.white.withOpacity(0.8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTimestamp(DateTime time) {
    final local = time.toLocal();
    final dayStr = local.day.toString().padLeft(2, '0');
    final monthStr = local.month.toString().padLeft(2, '0');
    final hourStr = local.hour.toString().padLeft(2, '0');
    final minStr = local.minute.toString().padLeft(2, '0');
    return '$dayStr.$monthStr в $hourStr:$minStr';
  }
}

class RecorderButton extends StatefulWidget {
  final AnimationController waveController;

  const RecorderButton({super.key, required this.waveController});

  @override
  State<RecorderButton> createState() => _RecorderButtonState();
}

class _RecorderButtonState extends State<RecorderButton> {
  bool _held = false;

  void _start() {
    context.read<TaskBloc>().add(StartRecording());
  }

  void _stop() {
    context.read<TaskBloc>().add(StopRecording());
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TaskBloc, TaskState>(
      builder: (context, state) {
        final isRecording = state is RecordingInProgress;

        if (AppConfig.inputMode == InputMode.hold) {
          // HOLD Recording Interface
          return GestureDetector(
            onLongPressStart: (_) {
              setState(() => _held = true);
              _start();
            },
            onLongPressEnd: (_) {
              setState(() => _held = false);
              _stop();
            },
            child: _buildButtonBody(isRecording || _held),
          );
        } else {
          // TAP Recording Interface
          return GestureDetector(
            onTap: () {
              if (isRecording) {
                _stop();
              } else {
                _start();
              }
            },
            child: _buildButtonBody(isRecording),
          );
        }
      },
    );
  }

  Widget _buildButtonBody(bool active) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: active ? 85 : 75,
      height: active ? 85 : 75,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active ? const Color(0xFF6366F1) : const Color(0xFF1E1B4B),
        border: Border.all(
          color: active ? const Color(0xFFA5B4FC) : const Color(0xFF6366F1).withOpacity(0.3),
          width: active ? 4 : 2,
        ),
        boxShadow: [
          BoxShadow(
            color: active ? const Color(0xFF6366F1).withOpacity(0.6) : const Color(0xFF6366F1).withOpacity(0.1),
            blurRadius: active ? 24 : 10,
            spreadRadius: active ? 6 : 1,
          )
        ],
      ),
      child: Center(
        child: Icon(
          active ? Icons.stop_rounded : Icons.mic_none_rounded,
          size: active ? 32 : 30,
          color: Colors.white,
        ),
      ),
    );
  }
}

class WaveformPainter extends CustomPainter {
  final double progress;

  WaveformPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF6366F1).withOpacity(0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    final double center = size.height / 2;
    final int barCount = 12;
    final double spacing = size.width / barCount;

    for (int i = 0; i < barCount; i++) {
      // Create organic pulsating wave bar heights
      final double waveFactor = math.sin(progress * math.pi * 2 + (i * 0.5));
      final double barHeight = 25 + (waveFactor.abs() * 50);
      final double x = (i * spacing) + (spacing / 2);

      canvas.drawLine(
        Offset(x, center - barHeight / 2),
        Offset(x, center + barHeight / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant WaveformPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
