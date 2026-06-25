import 'dart:convert';
import 'package:isar/isar.dart';
import '../models/task_model.dart';

class TaskRepository {
  final Isar isar;

  TaskRepository(this.isar);

  /// Watch all tasks reactively, sorted by reminder timestamp (tasks without reminders at the end).
  Stream<List<Task>> watchTasks() {
    return isar.tasks.where().sortByReminderTimestamp().watch(fireImmediately: true);
  }

  /// Get all tasks.
  Future<List<Task>> getAllTasks() async {
    return await isar.tasks.where().findAll();
  }

  /// Process incoming raw transcript and AI response JSON, mapping to Isar.
  Future<void> processIncomingTranscript(String transcript, String rawJsonFromAi) async {
    Task task;
    try {
      if (rawJsonFromAi.trim().isEmpty) {
        throw const FormatException('Empty AI response');
      }
      
      final Map<String, dynamic> parsedJson = jsonDecode(rawJsonFromAi);
      task = Task.fromJson(parsedJson);
    } catch (e) {
      // Фолбэк-стратегия при критической ошибке ИИ-парсинга
      task = Task()
        ..title = transcript.isNotEmpty ? transcript : 'Голосовая задача'
        ..hasReminder = false
        ..isComplex = false
        ..steps = [];
    }

    // Запись в БД через безопасную последовательную транзакцию
    await isar.writeTxn(() async {
      await isar.tasks.put(task);
    });
  }

  /// Add or update a task directly.
  Future<void> saveTask(Task task) async {
    await isar.writeTxn(() async {
      await isar.tasks.put(task);
    });
  }

  /// Find the most relevant task matching the query text for intent: UPDATE.
  Future<Task?> findRelevantTask(String queryText) async {
    final tasks = await isar.tasks.where().findAll();
    if (tasks.isEmpty) return null;

    final cleanQuery = queryText.toLowerCase();
    
    // Simple text matching heuristic: count matching words of length > 3
    final queryWords = cleanQuery
        .split(RegExp(r'[\s,.\-!?]+'))
        .where((w) => w.length > 3)
        .toList();

    if (queryWords.isEmpty) {
      return tasks.last; // Fallback to the most recent task
    }

    Task? bestMatch;
    int maxMatches = 0;

    for (var task in tasks) {
      int matches = 0;
      final titleLower = task.title.toLowerCase();
      
      for (var word in queryWords) {
        if (titleLower.contains(word)) {
          matches++;
        }
      }
      
      if (matches > maxMatches) {
        maxMatches = matches;
        bestMatch = task;
      }
    }

    // If no word matches, return the last active task.
    return bestMatch ?? tasks.last;
  }

  /// Calculate a unique notification ID to prevent reminder collisions.
  /// If another task has a reminder timestamp within 1 minute, the ID is adjusted.
  Future<int> calculateNotificationId(Task task) async {
    if (!task.hasReminder || task.reminderTimestamp == null) {
      return 0;
    }

    final targetTime = task.reminderTimestamp!;
    final oneMinuteAgo = targetTime.subtract(const Duration(seconds: 30));
    final oneMinuteLater = targetTime.add(const Duration(seconds: 30));

    // Find other tasks with reminder timestamp within 1 minute
    final collidingTasks = await isar.tasks
        .filter()
        .reminderTimestampBetween(oneMinuteAgo, oneMinuteLater)
        .and()
        .not()
        .idEqualTo(task.id)
        .findAll();

    if (collidingTasks.isEmpty) {
      return task.id;
    }

    // Increment notification ID relative to primary key task.id, off-setting to avoid overlap
    return task.id + (collidingTasks.length * 100000);
  }
}
