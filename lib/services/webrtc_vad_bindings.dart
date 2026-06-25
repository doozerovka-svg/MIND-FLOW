import 'dart:ffi';

// C functions signatures
typedef NativeCreate = Pointer<Void> Function();
typedef DartCreate = Pointer<Void> Function();

typedef NativeInit = Int32 Function(Pointer<Void> handle);
typedef DartInit = int Function(Pointer<Void> handle);

typedef NativeSetMode = Int32 Function(Pointer<Void> handle, Int32 mode);
typedef DartSetMode = int Function(Pointer<Void> handle, int mode);

typedef NativeProcess = Int32 Function(
    Pointer<Void> handle, Int32 fs, Pointer<Int16> audioFrame, IntPtr frameLength);
typedef DartProcess = int Function(
    Pointer<Void> handle, int fs, Pointer<Int16> audioFrame, int frameLength);

typedef NativeFree = Void Function(Pointer<Void> handle);
typedef DartFree = void Function(Pointer<Void> handle);

class WebRtcVadBindings {
  final DynamicLibrary _dylib;

  late final DartCreate create;
  late final DartInit init;
  late final DartSetMode setMode;
  late final DartProcess process;
  late final DartFree free;

  WebRtcVadBindings(this._dylib) {
    create = _dylib.lookupFunction<NativeCreate, DartCreate>('WebRtcVad_Create');
    init = _dylib.lookupFunction<NativeInit, DartInit>('WebRtcVad_Init');
    setMode = _dylib.lookupFunction<NativeSetMode, DartSetMode>('WebRtcVad_set_mode');
    process = _dylib.lookupFunction<NativeProcess, DartProcess>('WebRtcVad_Process');
    free = _dylib.lookupFunction<NativeFree, DartFree>('WebRtcVad_Free');
  }
}
