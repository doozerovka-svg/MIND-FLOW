import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

class AudioRecorderService {
  final AudioRecorder _recorder = AudioRecorder();
  StreamController<List<int>>? _pcmStreamController;
  final List<int> _accumulatedBytes = [];
  bool _isRecording = false;

  bool get isRecording => _isRecording;

  /// Stream of raw PCM bytes emitted in real-time during recording.
  Stream<List<int>> get pcmStream {
    if (_pcmStreamController == null) {
      throw StateError('Recording has not started yet.');
    }
    return _pcmStreamController!.stream;
  }

  /// Check and request microphone permissions.
  Future<bool> hasPermission() async {
    return await _recorder.hasPermission();
  }

  /// Start recording mono PCM 16-bit, 16kHz audio as a stream.
  Future<void> startRecording() async {
    if (_isRecording) return;

    if (!await hasPermission()) {
      throw Exception('Microphone permission denied.');
    }

    _accumulatedBytes.clear();
    _isRecording = true;
    _pcmStreamController = StreamController<List<int>>.broadcast();

    const recordConfig = RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: 16000,
      numChannels: 1,
    );

    try {
      final stream = await _recorder.startStream(recordConfig);
      
      stream.listen(
        (data) {
          if (!_isRecording) return;
          _accumulatedBytes.addAll(data);
          _pcmStreamController?.add(data);
        },
        onError: (error) {
          _pcmStreamController?.addError(error);
        },
        onDone: () {
          _pcmStreamController?.close();
        },
        cancelOnError: true,
      );
    } catch (e) {
      _isRecording = false;
      _pcmStreamController?.close();
      rethrow;
    }
  }

  /// Stop recording, process the accumulated PCM bytes, prepend the WAV header,
  /// save the WAV file to temporary directory, and return its file path.
  Future<String?> stopRecording() async {
    if (!_isRecording) return null;

    _isRecording = false;
    await _recorder.stop();

    _pcmStreamController?.close();
    _pcmStreamController = null;

    if (_accumulatedBytes.isEmpty) {
      return null;
    }

    // Convert accumulated raw PCM bytes to WAV format
    final wavBytes = _convertPcmToWav(_accumulatedBytes, 16000);
    
    // Save to a temporary file
    final tempDir = await getTemporaryDirectory();
    final String filePath = '${tempDir.path}/mind_flow_task_${DateTime.now().millisecondsSinceEpoch}.wav';
    final file = File(filePath);
    await file.writeAsBytes(wavBytes, flush: true);

    return filePath;
  }

  /// Helper to convert raw PCM 16-bit Mono bytes to a full WAV file bytes by prepending the 44-byte WAV header.
  List<int> _convertPcmToWav(List<int> pcmBytes, int sampleRate) {
    final int totalDataLen = pcmBytes.length;
    final int totalAudioLen = totalDataLen;
    final int totalDataLenWithHeader = totalAudioLen + 36;
    final int byteRate = sampleRate * 2; // 16-bit mono = 2 bytes/sample

    final Uint8List header = Uint8List(44);
    
    // RIFF/WAVE Header
    header[0] = 0x52; // R
    header[1] = 0x49; // I
    header[2] = 0x46; // F
    header[3] = 0x46; // F
    
    header[4] = (totalDataLenWithHeader & 0xff);
    header[5] = ((totalDataLenWithHeader >> 8) & 0xff);
    header[6] = ((totalDataLenWithHeader >> 16) & 0xff);
    header[7] = ((totalDataLenWithHeader >> 24) & 0xff);
    
    header[8] = 0x57; // W
    header[9] = 0x41; // A
    header[10] = 0x56; // V
    header[11] = 0x45; // E
    
    // fmt Chunk
    header[12] = 0x66; // f
    header[13] = 0x6d; // m
    header[14] = 0x74; // t
    header[15] = 0x20; // ' '
    
    header[16] = 16; // size of 'fmt ' chunk
    header[17] = 0;
    header[18] = 0;
    header[19] = 0;
    
    header[20] = 1; // format = 1 (PCM)
    header[21] = 0;
    
    header[22] = 1; // channel = 1 (mono)
    header[23] = 0;
    
    header[24] = (sampleRate & 0xff);
    header[25] = ((sampleRate >> 8) & 0xff);
    header[26] = ((sampleRate >> 16) & 0xff);
    header[27] = ((sampleRate >> 24) & 0xff);
    
    header[28] = (byteRate & 0xff);
    header[29] = ((byteRate >> 8) & 0xff);
    header[30] = ((byteRate >> 16) & 0xff);
    header[31] = ((byteRate >> 24) & 0xff);
    
    header[32] = 2; // block align (1 channel * 2 bytes/sample)
    header[33] = 0;
    
    header[34] = 16; // bits per sample = 16
    header[35] = 0;
    
    // data Chunk
    header[36] = 0x64; // d
    header[37] = 0x61; // a
    header[38] = 0x74; // t
    header[39] = 0x61; // a
    
    header[40] = (totalAudioLen & 0xff);
    header[41] = ((totalAudioLen >> 8) & 0xff);
    header[42] = ((totalAudioLen >> 16) & 0xff);
    header[43] = ((totalAudioLen >> 24) & 0xff);
    
    return [...header, ...pcmBytes];
  }

  /// Clean up resources.
  void dispose() {
    _recorder.dispose();
  }
}
