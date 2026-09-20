import 'dart:io';

import 'package:path/path.dart' as p;

class LevaiSettings {
  final String model;
  final String ollamaUrl;
  final String searxngUrl;
  final String mode;
  final String language;
  final int maxResults;

  const LevaiSettings({
    this.model = 'qwen2.5-coder:3b',
    this.ollamaUrl = 'http://localhost:11434',
    this.searxngUrl = 'http://localhost:8080',
    this.mode = 'advanced',
    this.language = 'pt-BR',
    this.maxResults = 8,
  });

  LevaiSettings copyWith({
    String? model,
    String? ollamaUrl,
    String? searxngUrl,
    String? mode,
    String? language,
    int? maxResults,
  }) {
    return LevaiSettings(
      model: model ?? this.model,
      ollamaUrl: ollamaUrl ?? this.ollamaUrl,
      searxngUrl: searxngUrl ?? this.searxngUrl,
      mode: mode ?? this.mode,
      language: language ?? this.language,
      maxResults: maxResults ?? this.maxResults,
    );
  }
}

class SettingsStore {
  final String filePath;

  SettingsStore({String? filePath})
      : filePath = filePath ??
            p.join(
              Platform.environment['USERPROFILE'] ?? '.',
              '.levai_scout',
              'settings.json',
            );

  Future<void> save(LevaiSettings settings) async {
    final file = File(filePath);
    await file.parent.create(recursive: true);

    final content = '''
{
  "model": "${settings.model}",
  "ollamaUrl": "${settings.ollamaUrl}",
  "searxngUrl": "${settings.searxngUrl}",
  "mode": "${settings.mode}",
  "language": "${settings.language}",
  "maxResults": ${settings.maxResults}
}
''';

    await file.writeAsString(content);
  }

  Future<LevaiSettings> load() async {
    final file = File(filePath);

    if (!await file.exists()) {
      return const LevaiSettings();
    }

    final text = await file.readAsString();

    String value(String key, String fallback) {
      final match = RegExp(
        '"$key"\\s*:\\s*"([^"]*)"',
      ).firstMatch(text);

      return match?.group(1) ?? fallback;
    }

    int integer(String key, int fallback) {
      final match = RegExp(
        '"$key"\\s*:\\s*(\\d+)',
      ).firstMatch(text);

      return int.tryParse(match?.group(1) ?? '') ?? fallback;
    }

    return LevaiSettings(
      model: value('model', 'qwen2.5-coder:3b'),
      ollamaUrl: value(
        'ollamaUrl',
        'http://localhost:11434',
      ),
      searxngUrl: value(
        'searxngUrl',
        'http://localhost:8080',
      ),
      mode: value('mode', 'advanced'),
      language: value('language', 'pt-BR'),
      maxResults: integer('maxResults', 8),
    );
  }
}
