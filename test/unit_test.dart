import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_flow/data/models/task_model.dart';

void main() {
  group('Task Model & JSON Parsing Tests', () {
    test('Successful task deserialization with steps and reminder', () {
      const String rawJson = '''
      {
        "title": "Помыть машину в субботу",
        "has_reminder": true,
        "reminder_timestamp": "2026-06-27T10:00:00+03:00",
        "is_complex": true,
        "steps": [
          {"text": "Положить летний комплект шин в багажник"},
          {"text": "Доехать до ближайшего шиномонтажа"}
        ]
      }
      ''';

      final Map<String, dynamic> parsedJson = jsonDecode(rawJson);
      final Task task = Task.fromJson(parsedJson);

      expect(task.title, equals('Помыть машину в субботу'));
      expect(task.hasReminder, isTrue);
      expect(task.reminderTimestamp, isNotNull);
      expect(task.reminderTimestamp!.year, equals(2026));
      expect(task.reminderTimestamp!.month, equals(6));
      expect(task.reminderTimestamp!.day, equals(27));
      expect(task.isComplex, isTrue);
      expect(task.steps.length, equals(2));
      expect(task.steps[0].text, equals('Положить летний комплект шин в багажник'));
      expect(task.steps[0].id, isNotEmpty);
      expect(task.steps[1].text, equals('Доехать до ближайшего шиномонтажа'));
      expect(task.steps[1].id, isNotEmpty);
      expect(task.steps[0].id, isNot(equals(task.steps[1].id)));
    });

    test('Safe parsing fallback under invalid/corrupted JSON', () {
      const String transcript = 'Сырой транскрипт задачи';
      
      // Simulating fallback parsing logic usually done in repository
      Task task;
      try {
        const String corruptedJson = '{invalid json';
        final Map<String, dynamic> parsedJson = jsonDecode(corruptedJson);
        task = Task.fromJson(parsedJson);
      } catch (e) {
        task = Task()
          ..title = transcript.isNotEmpty ? transcript : 'Голосовая задача'
          ..hasReminder = false
          ..isComplex = false
          ..steps = [];
      }

      expect(task.title, equals(transcript));
      expect(task.hasReminder, isFalse);
      expect(task.isComplex, isFalse);
      expect(task.steps, isEmpty);
    });

    test('Safe parsing fallback under empty JSON/empty transcript', () {
      const String transcript = '';
      
      Task task;
      try {
        const String emptyJson = '';
        final Map<String, dynamic> parsedJson = jsonDecode(emptyJson);
        task = Task.fromJson(parsedJson);
      } catch (e) {
        task = Task()
          ..title = transcript.isNotEmpty ? transcript : 'Голосовая задача'
          ..hasReminder = false
          ..isComplex = false
          ..steps = [];
      }

      expect(task.title, equals('Голосовая задача'));
      expect(task.hasReminder, isFalse);
      expect(task.isComplex, isFalse);
      expect(task.steps, isEmpty);
    });
  });

  group('Intent & Task Repository Heuristics Tests', () {
    test('Heuristic keyword matcher for UPDATE intent context matching', () {
      // Mocking Task Database
      final tasks = [
        Task()..title = 'Поменять резину на автомобиле',
        Task()..title = 'Купить молоко и хлеб',
        Task()..title = 'Созвониться с коллегами по работе',
      ];

      String queryText = 'Добавь в задачу по машине пункт взять шампунь';
      final cleanQuery = queryText.toLowerCase();
      final queryWords = cleanQuery
          .split(RegExp(r'[\s,.\-!?]+'))
          .where((w) => w.length > 3)
          .toList();

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

      // Best match should be null since no direct keyword matches
      expect(bestMatch, isNull); // Since no direct substring match

      // Let's test with direct keyword match
      queryText = 'Добавь в резину пункт купить шампунь';
      final queryWords2 = queryText.toLowerCase().split(' ').where((w) => w.length > 3).toList();
      bestMatch = null;
      maxMatches = 0;
      for (var task in tasks) {
        int matches = 0;
        final titleLower = task.title.toLowerCase();
        for (var word in queryWords2) {
          if (titleLower.contains(word)) {
            matches++;
          }
        }
        if (matches > maxMatches) {
          maxMatches = matches;
          bestMatch = task;
        }
      }
      expect(bestMatch, equals(tasks[0])); // Matches "резину"
    });
  });
}
