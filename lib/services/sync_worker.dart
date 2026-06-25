import 'package:isar/isar.dart';
import 'package:workmanager/workmanager.dart';
import '../data/models/task_model.dart';
import '../repositories/task_repository.dart';
import 'llm_service.dart';
import 'stt_service.dart';

const String syncTaskName = 'com.mindflow.sync_offline_tasks';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    // We only handle sync task
    if (taskName != syncTaskName) return true;

    try {
      // 1. Initialize Isar inside the background thread
      final String dir = inputData?['directory'] as String? ?? '';
      if (dir.isEmpty) return false;

      final isar = await Isar.open(
        [TaskSchema],
        directory: dir,
      );

      final repository = TaskRepository(isar);
      final sttService = OpenAiWhisperService();
      final llmService = LlmService();

      // 2. Fetch tasks that need synchronization
      final offlineTasks = await isar.tasks
          .filter()
          .needsSyncEqualTo(true)
          .findAll();

      if (offlineTasks.isEmpty) {
        await isar.close();
        return true;
      }

      for (var task in offlineTasks) {
        final String audioPath = task.localAudioPath ?? '';
        if (audioPath.isEmpty) continue;

        try {
          // Perform Speech-to-Text
          final String transcript = await sttService.transcribe(audioPath);
          if (transcript.isEmpty) {
            // If empty, clean up the task from sync requirements
            await isar.writeTxn(() async {
              task.needsSync = false;
              task.title = 'Пустая запись';
              await isar.tasks.put(task);
            });
            continue;
          }

          // Perform Intent classification
          final String intent = await llmService.classifyIntent(transcript);
          
          if (intent == 'UPDATE') {
            final Task? contextTask = await repository.findRelevantTask(transcript);
            if (contextTask != null) {
              final String updatedJson = await llmService.processTask(
                transcript,
                contextTask: contextTask,
              );
              // Safely apply JSON updates to the DB
              await repository.processIncomingTranscript(transcript, updatedJson);
            } else {
              final String structuredJson = await llmService.processTask(transcript);
              await repository.processIncomingTranscript(transcript, structuredJson);
            }
          } else {
            // CREATE intent
            final String structuredJson = await llmService.processTask(transcript);
            await repository.processIncomingTranscript(transcript, structuredJson);
          }

          // Delete the temporary local audio file to save space
          final file = Uri.parse(audioPath).toFilePath();
          // We can delete file locally
          // (omit for simplicity of testing or implement safely)
        } catch (_) {
          // If a single task fails due to network, we stop and try again in next run
          await isar.close();
          return false;
        }
      }

      await isar.close();
      return true;
    } catch (_) {
      return false;
    }
  });
}
