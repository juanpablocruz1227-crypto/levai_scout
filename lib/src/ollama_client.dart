import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:levai_scout/src/search_engine.dart';

class OllamaException implements Exception {
  final String message;

  OllamaException(this.message);

  @override
  String toString() => 'OllamaException: $message';
}

class ChatMessage {
  final String role;
  final String content;

  const ChatMessage({
    required this.role,
    required this.content,
  });

  Map<String, dynamic> toJson() {
    return {
      'role': role,
      'content': content,
    };
  }
}

class OllamaClient {
  final String baseUrl;
  final String model;
  final int contextWindow;
  final double temperature;

  final HttpClient _httpClient = HttpClient();

  OllamaClient({
    this.baseUrl = 'http://localhost:11434',
    this.model = 'qwen-fast',
    this.contextWindow = 4096,
    this.temperature = 0.2,
  });

  Future<bool> healthCheck() async {
    try {
      final request = await _httpClient
          .getUrl(Uri.parse('$baseUrl/api/tags'))
          .timeout(const Duration(seconds: 5));

      final response = await request.close();

      if (response.statusCode != 200) {
        return false;
      }

      final body = await utf8.decoder.bind(response).join();

      final data = jsonDecode(body);

      if (data is! Map<String, dynamic>) {
        return false;
      }

      final models = data['models'];

      if (models is! List) {
        return false;
      }

      for (final item in models) {
        if (item is! Map) {
          continue;
        }

        final name = item['name'];

        if (name is! String) {
          continue;
        }

        if (name == model ||
            name.startsWith('$model:') ||
            model.startsWith('$name:')) {
          return true;
        }
      }

      return false;
    } catch (_) {
      return false;
    }
  }

  Future<List<String>> generateRelatedQueries(String query) async {
    final prompt = '''
Gere até 3 sub-buscas para pesquisar melhor a pergunta abaixo.

Pergunta:
$query

REGRAS:
- Responda somente com as sub-buscas.
- Uma sub-busca por linha.
- Não use números.
- Não explique nada.
- Não repita exatamente a pergunta original.
- Use palavras-chave úteis para pesquisa.
''';

    try {
      final response = await _generateOnce(
        prompt: prompt,
        systemPrompt: '''
Você é um mecanismo de expansão de consultas do Levai Scout.
Sua função é transformar uma pergunta em poucas pesquisas complementares.
Seja extremamente conciso.
''',
        numPredict: 120,
      );

      final lines = response
          .split(RegExp(r'[\r\n]+'))
          .map((line) {
            return line
                .replaceFirst(RegExp(r'^\s*[-*•]\s*'), '')
                .replaceFirst(RegExp(r'^\s*\d+[.)]\s*'), '')
                .trim();
          })
          .where((line) => line.isNotEmpty)
          .toList();

      final unique = <String>[];

      for (final line in lines) {
        if (line.toLowerCase() == query.trim().toLowerCase()) {
          continue;
        }

        if (!unique.contains(line)) {
          unique.add(line);
        }
      }

      return unique.take(3).toList();
    } catch (_) {
      // Se a expansão falhar, a pesquisa original continua funcionando.
      return const [];
    }
  }

  Stream<String> generateStream({
    required String userQuery,
    required String context,
    required List<SearchResult> sources,
  }) async* {
    final sourceText = sources.asMap().entries.map((entry) {
      final index = entry.key + 1;
      final source = entry.value;

      return '''
[FONTE $index]
Título: ${source.title}
URL: ${source.url}
Resumo: ${source.snippet}
''';
    }).join('\n');

    final prompt = '''
Você é o Levai Scout, um agente local de pesquisa.

RESPONDA EM PORTUGUÊS DO BRASIL.

PERGUNTA DO USUÁRIO:
$userQuery

CONTEXTO EXTRAÍDO DAS PÁGINAS:
$context

FONTES:
$sourceText

REGRAS:
1. Use o contexto pesquisado como fonte principal.
2. Não invente fatos que não estejam nas informações disponíveis.
3. Se houver informações conflitantes, deixe isso claro.
4. Responda diretamente à pergunta.
5. Seja técnico quando a pergunta for técnica.
6. Para programação, inclua código quando necessário.
7. Cite as fontes usando [Fonte 1], [Fonte 2], etc.
8. Não repita a pergunta.
9. Não faça uma introdução desnecessária.
10. Priorize precisão e clareza.
''';

    yield* _streamGenerate(
      prompt: prompt,
      systemPrompt: '''
Você é o Levai Scout, um agente local de pesquisa e programação.

Sua função é analisar informações fornecidas por ferramentas
de pesquisa e produzir respostas precisas.

Nunca invente informações.
Quando houver contexto de pesquisa, baseie a resposta nele.
Responda em português do Brasil.
Seja direto.
''',
    );
  }

  Stream<String> chatStream({
    required List<ChatMessage> messages,
  }) async* {
    final request = await _httpClient
        .postUrl(Uri.parse('$baseUrl/api/chat'))
        .timeout(const Duration(seconds: 10));

    request.headers.contentType = ContentType.json;

    final body = <String, dynamic>{
      'model': model,
      'messages': messages.map((message) => message.toJson()).toList(),
      'stream': true,
      'options': {
        'num_ctx': contextWindow,
        'temperature': temperature,
        'top_p': 0.9,
        'num_predict': 512,
      },
    };

    request.write(jsonEncode(body));

    final response = await request.close();

    if (response.statusCode != 200) {
      final errorBody = await utf8.decoder.bind(response).join();

      throw OllamaException(
        'Ollama retornou status ${response.statusCode}: $errorBody',
      );
    }

    final lines =
        response.transform(utf8.decoder).transform(const LineSplitter());

    await for (final line in lines) {
      if (line.trim().isEmpty) {
        continue;
      }

      try {
        final decoded = jsonDecode(line);

        if (decoded is! Map<String, dynamic>) {
          continue;
        }

        if (decoded['error'] != null) {
          throw OllamaException(
            decoded['error'].toString(),
          );
        }

        final message = decoded['message'];

        if (message is Map) {
          final content = message['content'];

          if (content is String && content.isNotEmpty) {
            yield content;
          }
        }

        if (decoded['done'] == true) {
          break;
        }
      } catch (e) {
        if (e is OllamaException) {
          rethrow;
        }

        continue;
      }
    }
  }

  Future<String> _generateOnce({
    required String prompt,
    required String systemPrompt,
    int numPredict = 256,
  }) async {
    final request = await _httpClient
        .postUrl(Uri.parse('$baseUrl/api/generate'))
        .timeout(const Duration(seconds: 10));

    request.headers.contentType = ContentType.json;

    final body = <String, dynamic>{
      'model': model,
      'prompt': prompt,
      'system': systemPrompt,
      'stream': false,
      'options': {
        'num_ctx': contextWindow,
        'temperature': temperature,
        'top_p': 0.9,
        'num_predict': numPredict,
      },
    };

    request.write(jsonEncode(body));

    final response = await request.close();

    final responseBody = await utf8.decoder.bind(response).join();

    if (response.statusCode != 200) {
      throw OllamaException(
        'Ollama retornou status ${response.statusCode}: $responseBody',
      );
    }

    final decoded = jsonDecode(responseBody);

    if (decoded is! Map<String, dynamic>) {
      throw OllamaException('Resposta inválida do Ollama.');
    }

    if (decoded['error'] != null) {
      throw OllamaException(
        decoded['error'].toString(),
      );
    }

    final result = decoded['response'];

    if (result is! String) {
      throw OllamaException(
        'Ollama não retornou texto.',
      );
    }

    return result.trim();
  }

  Stream<String> _streamGenerate({
    required String prompt,
    required String systemPrompt,
  }) async* {
    final request = await _httpClient
        .postUrl(Uri.parse('$baseUrl/api/generate'))
        .timeout(const Duration(seconds: 10));

    request.headers.contentType = ContentType.json;

    final body = <String, dynamic>{
      'model': model,
      'prompt': prompt,
      'system': systemPrompt,
      'stream': true,
      'options': {
        'num_ctx': contextWindow,
        'temperature': temperature,
        'top_p': 0.9,
        'num_predict': 768,
      },
    };

    request.write(jsonEncode(body));

    final response = await request.close();

    if (response.statusCode != 200) {
      final errorBody = await utf8.decoder.bind(response).join();

      throw OllamaException(
        'Ollama retornou status ${response.statusCode}: $errorBody',
      );
    }

    final lines =
        response.transform(utf8.decoder).transform(const LineSplitter());

    await for (final line in lines) {
      if (line.trim().isEmpty) {
        continue;
      }

      try {
        final decoded = jsonDecode(line);

        if (decoded is! Map<String, dynamic>) {
          continue;
        }

        if (decoded['error'] != null) {
          throw OllamaException(
            decoded['error'].toString(),
          );
        }

        final token = decoded['response'];

        if (token is String && token.isNotEmpty) {
          yield token;
        }

        if (decoded['done'] == true) {
          break;
        }
      } catch (e) {
        if (e is OllamaException) {
          rethrow;
        }

        continue;
      }
    }
  }

  void close() {
    _httpClient.close(force: true);
  }
}
