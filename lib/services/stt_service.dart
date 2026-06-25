import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';

class OfflineException implements Exception {
  final String message;
  OfflineException([this.message = 'No internet connection. Audio saved locally.']);

  @override
  String toString() => 'OfflineException: $message';
}

abstract class SttService {
  /// Transcribes the audio file at the given [filePath] into plain text.
  /// Throws [OfflineException] if there is a network outage.
  Future<String> transcribe(String filePath);
}

class OpenAiWhisperService implements SttService {
  final http.Client _client;

  OpenAiWhisperService({http.Client? client}) : _client = client ?? http.Client();

  @override
  Future<String> transcribe(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw ArgumentError('Audio file does not exist at path: $filePath');
    }

    final String apiKey = AppConfig.openAiApiKey;
    if (apiKey.isEmpty) {
      throw StateError('OpenAI API Key is empty. Please set it in AppConfig.');
    }

    final uri = Uri.parse(AppConfig.whisperUrl);
    final request = http.MultipartRequest('POST', uri)
      ..headers['Authorization'] = 'Bearer $apiKey'
      ..fields['model'] = 'whisper-1'
      ..files.add(await http.MultipartFile.fromPath('file', filePath));

    try {
      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 30),
      );
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final Map<String, dynamic> jsonResponse = jsonDecode(response.body);
        final String text = jsonResponse['text'] as String? ?? '';
        return text.trim();
      } else {
        throw HttpException(
          'Whisper API returned error status: ${response.statusCode}. Body: ${response.body}',
        );
      }
    } on SocketException catch (_) {
      throw OfflineException();
    } on http.ClientException catch (_) {
      throw OfflineException();
    } catch (e) {
      // Re-throw if it's already an OfflineException or HttpException, otherwise wrap
      if (e is OfflineException || e is HttpException) {
        rethrow;
      }
      throw Exception('Failed to transcribe audio: $e');
    }
  }
}
