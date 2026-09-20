class LevaiConfig {
  final String searxngUrl;
  final String ollamaUrl;
  final String model;
  final int contextWindow;
  final double temperature;
  final int maxResults;

  const LevaiConfig({
    this.searxngUrl = 'http://localhost:8080',
    this.ollamaUrl = 'http://localhost:11434',
    this.model = 'qwen2.5-coder:3b',
    this.contextWindow = 8192,
    this.temperature = 0.2,
    this.maxResults = 8,
  });

  LevaiConfig copyWith({
    String? searxngUrl,
    String? ollamaUrl,
    String? model,
    int? contextWindow,
    double? temperature,
    int? maxResults,
  }) {
    return LevaiConfig(
      searxngUrl: searxngUrl ?? this.searxngUrl,
      ollamaUrl: ollamaUrl ?? this.ollamaUrl,
      model: model ?? this.model,
      contextWindow: contextWindow ?? this.contextWindow,
      temperature: temperature ?? this.temperature,
      maxResults: maxResults ?? this.maxResults,
    );
  }

  @override
  String toString() {
    return '''
Levai Scout Configuration

SearXNG: $searxngUrl
Ollama:  $ollamaUrl
Modelo:  $model
Contexto: $contextWindow
Temperature: $temperature
Max results: $maxResults
''';
  }
}
