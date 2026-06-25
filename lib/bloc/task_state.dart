import 'package:equatable/equatable.dart';
import '../config/app_config.dart';
import '../data/models/task_model.dart';

abstract class TaskState extends Equatable {
  const TaskState();

  @override
  List<Object?> get props => [];
}

class TaskInitial extends TaskState {}

class TaskLoading extends TaskState {}

class TasksLoaded extends TaskState {
  final List<Task> tasks;
  final InputMode inputMode;

  const TasksLoaded(this.tasks, this.inputMode);

  @override
  List<Object?> get props => [tasks, inputMode];
}

class RecordingInProgress extends TaskState {}

class ProcessingSpeech extends TaskState {}

class TaskSuccess extends TaskState {
  final String message;

  const TaskSuccess(this.message);

  @override
  List<Object?> get props => [message];
}

class TaskFailure extends TaskState {
  final String error;

  const TaskFailure(this.error);

  @override
  List<Object?> get props => [error];
}
