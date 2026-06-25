import 'package:isar/isar.dart';
import 'package:uuid/uuid.dart';

part 'task_model.g.dart';

@Collection()
class Task {
  Id id = Isar.autoIncrement;

  @Index(type: IndexType.value)
  late String title;

  late bool hasReminder;
  
  @Index()
  DateTime? reminderTimestamp;

  late bool isComplex;

  List<EmbeddedStep> steps = [];

  bool? needsSync;
  String? localAudioPath;

  Task();

  // Фабрика безопасного парсинга с генерацией стабильных ID на клиенте
  factory Task.fromJson(Map<String, dynamic> json) {
    final rawSteps = json['steps'] as List<dynamic>? ?? [];
    
    return Task()
      ..title = json['title'] as String? ?? 'Новая задача'
      ..hasReminder = json['has_reminder'] as bool? ?? false
      ..reminderTimestamp = json['reminder_timestamp'] != null 
          ? DateTime.parse(json['reminder_timestamp'] as String) 
          : null
      ..isComplex = json['is_complex'] as bool? ?? false
      ..steps = rawSteps.map((stepJson) => EmbeddedStep.fromJson(stepJson as Map<String, dynamic>)).toList();
  }
}

@Embedded()
class EmbeddedStep {
  // Уникальный ID шага генерируется строго на стороне клиента при десериализации
  String? id;
  String? text;

  EmbeddedStep({this.id, this.text});

  factory EmbeddedStep.fromJson(Map<String, dynamic> json) {
    return EmbeddedStep(
      id: const Uuid().v4(), // Гарантия уникальности Key в UI-коллекциях
      text: json['text'] as String? ?? '',
    );
  }
}
