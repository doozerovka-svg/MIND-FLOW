import 'package:equatable/equatable.dart';
import '../config/app_config.dart';

abstract class TaskEvent extends Equatable {
  const TaskEvent();

  @override
  List<Object?> get props => [];
}

class LoadTasks extends TaskEvent {}

class StartRecording extends TaskEvent {}

class StopRecording extends TaskEvent {}

class ToggleConfigMode extends TaskEvent {
  final InputMode mode;

  const ToggleConfigMode(this.mode);

  @override
  List<Object?> get props => [mode];
}
