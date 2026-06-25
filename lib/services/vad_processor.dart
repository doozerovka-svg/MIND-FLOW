import 'dart:async';
import 'dart:ffi';
import 'dart:math';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'webrtc_vad_bindings.dart';

class VadProcessor {
  final Function() onSilenceDetected;
  final int silenceThresholdMs;
  final int sampleRate;
  
  // VAD mode/aggressiveness (0 = normal, 3 = very aggressive)
  final int aggressiveness;
  
  // Pure Dart Fallback parameters
  final double rmsThreshold; 

  WebRtcVadBindings? _bindings;
  Pointer<Void>? _vadHandle;
  bool _isNativeLoaded = false;
  
  final List<int> _buffer = [];
  int _consecutiveSilenceMs = 0;
  StreamSubscription<List<int>>? _streamSubscription;

  // Frame size for WebRTC VAD is 10, 20 or 30ms. We use 30ms.
  // 16000 Hz * 30ms = 480 samples. 480 samples * 2 bytes/sample = 960 bytes.
  static const int frameMs = 30;
  late final int _frameByteLength;
  late final int _frameSamplesCount;

  VadProcessor({
    required this.onSilenceDetected,
    this.silenceThresholdMs = 1500,
    this.sampleRate = 16000,
    this.aggressiveness = 3,
    this.rmsThreshold = 350.0, // Default threshold for energy VAD
  }) {
    _frameSamplesCount = (sampleRate * frameMs) ~/ 1000;
    _frameByteLength = _frameSamplesCount * 2;
    _initNativeVad();
  }

  /// Initialize native WebRTC VAD if library exists. Otherwise fall back to Dart RMS VAD.
  void _initNativeVad() {
    try {
      DynamicLibrary dylib;
      // Load platform-specific dynamic library
      // On Android: libwebrtc_vad.so, On iOS: framework/App, etc.
      // We will attempt to load a library named 'webrtc_vad'.
      // If it throws, we catch it and use pure-Dart fallback.
      dylib = DynamicLibrary.open('webrtc_vad');
      _bindings = WebRtcVadBindings(dylib);
      
      _vadHandle = _bindings!.create();
      final initResult = _bindings!.init(_vadHandle!);
      if (initResult == 0) {
        _bindings!.setMode(_vadHandle!, aggressiveness);
        _isNativeLoaded = true;
        print('WebRTC VAD: Native library loaded successfully.');
      } else {
        print('WebRTC VAD: Failed to initialize native VAD. Using Dart RMS fallback.');
        _bindings!.free(_vadHandle!);
        _vadHandle = null;
      }
    } catch (e) {
      print('WebRTC VAD: Native library not found/loaded ($e). Using Dart RMS fallback.');
      _isNativeLoaded = false;
      _bindings = null;
      _vadHandle = null;
    }
  }

  /// Start processing PCM audio bytes stream.
  void startProcessing(Stream<List<int>> pcmStream) {
    stopProcessing();
    _buffer.clear();
    _consecutiveSilenceMs = 0;

    _streamSubscription = pcmStream.listen((chunk) {
      _buffer.addAll(chunk);
      _processBuffer();
    });
  }

  /// Stop processing and cancel subscriptions.
  void stopProcessing() {
    _streamSubscription?.cancel();
    _streamSubscription = null;
  }

  /// Process the accumulated buffer into 30ms frames.
  void _processBuffer() {
    while (_buffer.length >= _frameByteLength) {
      // Extract 30ms frame bytes
      final frameBytes = _buffer.sublist(0, _frameByteLength);
      // Remove processed bytes from buffer
      _buffer.removeRange(0, _frameByteLength);

      bool isSpeech = false;

      if (_isNativeLoaded && _vadHandle != null && _bindings != null) {
        isSpeech = _runNativeVad(frameBytes);
      } else {
        isSpeech = _runEnergyVad(frameBytes);
      }

      if (isSpeech) {
        _consecutiveSilenceMs = 0;
      } else {
        _consecutiveSilenceMs += frameMs;
        if (_consecutiveSilenceMs >= silenceThresholdMs) {
          stopProcessing();
          onSilenceDetected();
          break;
        }
      }
    }
  }

  /// Run native WebRTC VAD on the 30ms frame.
  bool _runNativeVad(List<int> frameBytes) {
    final Pointer<Int16> pcmFrame = malloc<Int16>(_frameSamplesCount);
    
    // Copy bytes to native memory
    final byteData = ByteData.sublistView(Uint8List.fromList(frameBytes));
    for (int i = 0; i < _frameSamplesCount; i++) {
      pcmFrame[i] = byteData.getInt16(i * 2, Endian.little);
    }

    try {
      final int result = _bindings!.process(
        _vadHandle!,
        sampleRate,
        pcmFrame,
        _frameSamplesCount,
      );
      return result == 1; // 1 = Speech, 0 = Silence, -1 = Error
    } catch (e) {
      // If native process fails, fallback to energy VAD
      return _runEnergyVad(frameBytes);
    } finally {
      malloc.free(pcmFrame);
    }
  }

  /// Fallback pure Dart VAD using Root-Mean-Square (RMS) amplitude energy detection.
  bool _runEnergyVad(List<int> frameBytes) {
    double sumOfSquares = 0.0;
    final int samplesCount = frameBytes.length ~/ 2;
    
    final byteData = ByteData.sublistView(Uint8List.fromList(frameBytes));
    
    for (int i = 0; i < samplesCount; i++) {
      final double sample = byteData.getInt16(i * 2, Endian.little).toDouble();
      sumOfSquares += sample * sample;
    }
    
    final double rms = sqrt(sumOfSquares / samplesCount);
    
    // If RMS energy is above threshold, we consider it speech
    return rms > rmsThreshold;
  }

  /// Release native resources.
  void dispose() {
    stopProcessing();
    if (_isNativeLoaded && _vadHandle != null && _bindings != null) {
      _bindings!.free(_vadHandle!);
      _vadHandle = null;
      _isNativeLoaded = false;
    }
  }
}
