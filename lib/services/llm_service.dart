import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import '../models/task_model.dart';
import 'stt_service.dart'; // For OfflineException

class LlmService {
  final http.Client _client;

  LlmService({http.Client? client}) : _client = client ?? http.Client();

  /// Call the active LLM provider (OpenAI or DeepSeek) to classify the user's intent.
  /// Returns "CREATE" or "UPDATE".
  Future<String> classifyIntent(String transcript) async {
    if (transcript.trim().isEmpty) return 'CREATE';

    const systemPrompt = '''
You are an intent classifier for a voice task manager. Your only job is to classify the user's input into one of two categories:
- "UPDATE": If the user clearly references modifying, adding steps to, checking off, deleting, or rescheduling an existing task. Examples: "Добавь в задачу по машине пункт купить шампунь", "Сдвинь напоминание о созвоне на 15:00", "Пометь созвон как сделанный".
- "CREATE": If the user is describing a new task to be created from scratch. Examples: "Надо помыть машину в субботу", "Купить молоко вечером".

You must respond with EXACTLY one word: either "CREATE" or "UPDATE" (no punctuation, no other words).
''';

    final String apiKey = _getApiKey();
    if (apiKey.isEmpty) {
      throw StateError('API Key for the selected LLM provider is empty.');
    }

    final url = _getUrl();
    final model = _getModel();

    final body = {
      'model': model,
      'messages': [
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': transcript}
      ],
      'temperature': 0.0,
    };

    try {
      final response = await _client.post(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final Map<String, dynamic> jsonResponse = jsonDecode(response.body);
        final String rawResponse =
            jsonResponse['choices'][0]['message']['content'] as String? ?? 'CREATE';
        final cleanResponse = rawResponse.trim().toUpperCase();
        
        if (cleanResponse.contains('UPDATE')) {
          return 'UPDATE';
        }
        return 'CREATE';
      } else {
        throw Exception('LLM Classifier API error: ${response.statusCode}');
      }
    } on http.ClientException catch (_) {
      throw OfflineException('Network error during intent classification');
    } catch (_) {
      // Return CREATE as fallback
      return 'CREATE';
    }
  }

  /// Process the transcript to structure it as a JSON task.
  /// If [contextTask] is provided, it instructs the LLM to update this task instead.
  Future<String> processTask(String transcript, {Task? contextTask}) async {
    final String currentDateTime = DateTime.now().toUtc().toIso8601String();
    final String currentDayOfWeek = _getDayOfWeekName(DateTime.now().weekday);

    final String baseSystemPrompt = '''
Роль: Ты — изолированный бэкенд-модуль ядра СУБД таск-менеджера. Твоя цель — преобразовать транскрипт аудио в строго валидный JSON-объект по заданной схеме.

Динамический контекст пользователя:
- Текущая дата и время: $currentDateTime (Формат: YYYY-MM-DDTHH:mm:ssZ)
- Текущий день недели: $currentDayOfWeek

Правила обработки полей JSON:
1. title: Краткая суть действия в инфинитиве. Без мусора, междометий и местоимений.
2. has_reminder: Изменяется на true при любом явном или неявном указании на время выполнения.
3. reminder_timestamp: Расчет времени строго от предоставленного $currentDateTime.
   - Относительное время ("через полчаса") рассчитывается математическим сложением.
   - Нечеткие таймфреймы привязываются к интервалам текущих суток пользователя: 
     "Утром" -> 09:00:00, "Обед" -> 14:00:00, "Вечером" -> 19:00:00, "Ночью" -> 23:00:00.
   - Предохранитель времени: Если рассчитанный интервал для текущих суток уже прошел (сейчас 21:00, а пользователь сказал "сделай вечером"), дата автоматически переносится на эти же интервалы СЛЕДУЮЩЕГО дня.
   - Полное отсутствие маркеров времени при has_reminder = true переносит задачу на 09:00:00 следующего дня.
4. is_complex: Логическое true, если задача требует более двух физических шагов или более 15 минут времени. В противном случае — false.
5. steps: Массив объектов [{"text": "String"}]. Если is_complex = false, массив строго пуст []. Если true, задача декомпозируется по методу Лотоса на атомарные, хронологически последовательные шаги. Запрещено добавлять в поле text префиксы ("1.", "Шаг"). Генерация ID шагов на стороне ИИ запрещена.

Выходной JSON-контракт от LLM (Схема ответа):
{
  "title": "String",
  "has_reminder": Boolean,
  "reminder_timestamp": "String" (ISO 8601 with timezone offset, e.g. "2026-06-27T10:00:00+03:00" or null),
  "is_complex": Boolean,
  "steps": [
    { "text": "String" }
  ]
}
''';

    String userPrompt = 'Транскрипт аудио пользователя: "$transcript"';

    if (contextTask != null) {
      // Format existing task details to inject into prompt for modification
      final existingTaskJson = {
        'title': contextTask.title,
        'has_reminder': contextTask.hasReminder,
        'reminder_timestamp': contextTask.reminderTimestamp?.toIso8601String(),
        'is_complex': contextTask.isComplex,
        'steps': contextTask.steps.map((s) => {'text': s.text}).toList(),
      };

      userPrompt = '''
Пользователь хочет ОБНОВИТЬ существующую задачу на основе новой инструкции.

Существующая задача:
${jsonEncode(existingTaskJson)}

Новая аудиоинструкция пользователя по обновлению:
"$transcript"

Инструкции по обновлению:
1. Измени или дополни исходную задачу в соответствии с аудиозаписью.
2. Если пользователь просит добавить шаги, добавь их в массив "steps".
3. Если пользователь просит перенести время, рассчитай новый "reminder_timestamp" относительно $currentDateTime.
4. Верни полный результирующий JSON-объект обновленной задачи по той же схеме.
''';
    }

    final String apiKey = _getApiKey();
    if (apiKey.isEmpty) {
      throw StateError('API Key for the selected LLM provider is empty.');
    }

    final url = _getUrl();
    final model = _getModel();

    final body = {
      'model': model,
      'messages': [
        {'role': 'system', 'content': baseSystemPrompt},
        {'role': 'user', 'content': userPrompt}
      ],
      'response_format': {'type': 'json_object'},
      'temperature': 0.1,
    };

    try {
      final response = await _client.post(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final Map<String, dynamic> jsonResponse = jsonDecode(response.body);
        return jsonResponse['choices'][0]['message']['content'] as String? ?? '{}';
      } else {
        throw HttpException('LLM API returned error status: ${response.statusCode}. Body: ${response.body}');
      }
    } on SocketException catch (_) {
      throw OfflineException('Network error during task structuring');
    } on http.ClientException catch (_) {
      throw OfflineException('Network error during task structuring');
    }
  }

  String _getApiKey() {
    return AppConfig.llmProvider == LlmProvider.openai
        ? AppConfig.openAiApiKey
        : AppConfig.deepSeekApiKey;
  }

  String _getUrl() {
    return AppConfig.llmProvider == LlmProvider.openai
        ? AppConfig.openAiGptUrl
        : AppConfig.deepSeekUrl;
  }

  String _getModel() {
    return AppConfig.llmProvider == LlmProvider.openai
        ? AppConfig.gptModel
        : AppConfig.deepSeekModel;
  }

  String _getDayOfWeekName(int weekday) {
    switch (weekday) {
      case 1: return 'Monday';
      case 2: return 'Tuesday';
      case 3: return 'Wednesday';
      case 4: return 'Thursday';
      case 5: return 'Friday';
      case 6: return 'Saturday';
      case 7: return 'Sunday';
      default: return 'Unknown';
    }
  }
}
