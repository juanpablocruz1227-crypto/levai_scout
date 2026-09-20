class StudySession {
  final String topic;
  final String material;
  final DateTime createdAt;

  StudySession({
    required this.topic,
    required this.material,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() {
    return {
      'topic': topic,
      'material': material,
      'createdAt': createdAt.toIso8601String(),
    };
  }
}
