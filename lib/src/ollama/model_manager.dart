import 'dart:convert';

import 'package:http/http.dart' as http;

class OllamaModelManager {
  final String baseUrl;

  OllamaModelManager({
    this.baseUrl = 'http://localhost:11434',
  });

  Future<List<String>> listModels() async {
    final response = await http
        .get(Uri.parse('$baseUrl/api/tags'))
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw Exception('Ollama respondeu com HTTP ${response.statusCode}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final models = data['models'];

    if (models is! List) {
      return [];
    }

    return models
        .whereType<Map>()
        .map((model) => model['name']?.toString())
        .whereType<String>()
        .toList();
  }

  Future<bool> isAvailable() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/tags'))
          .timeout(const Duration(seconds: 5));

      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
