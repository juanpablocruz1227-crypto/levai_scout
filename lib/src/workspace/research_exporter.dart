import 'dart:io';

import 'package:path/path.dart' as p;

class ResearchExporter {
  static Future<File> markdown({
    required String question,
    required List<String> sources,
    required String? answer,
  }) async {
    final directory = Directory(
      p.join(
        Platform.environment['USERPROFILE'] ?? '.',
        'Documents',
        'LevaiScout',
      ),
    );

    await directory.create(recursive: true);

    final safeName = question
        .replaceAll(RegExp(r'[^\w\s-]'), '')
        .replaceAll(RegExp(r'\s+'), '_')
        .toLowerCase();

    final name = safeName.isEmpty ? 'research' : safeName;

    final file = File(
      p.join(
        directory.path,
        '$name.md',
      ),
    );

    final buffer = StringBuffer();

    buffer.writeln('# Levai Scout Research');
    buffer.writeln();
    buffer.writeln('## Pergunta');
    buffer.writeln();
    buffer.writeln(question);
    buffer.writeln();

    if (answer != null && answer.trim().isNotEmpty) {
      buffer.writeln('## Resposta');
      buffer.writeln();
      buffer.writeln(answer);
      buffer.writeln();
    }

    buffer.writeln('## Fontes');
    buffer.writeln();

    for (final source in sources) {
      buffer.writeln('- $source');
    }

    await file.writeAsString(buffer.toString());

    return file;
  }
}
