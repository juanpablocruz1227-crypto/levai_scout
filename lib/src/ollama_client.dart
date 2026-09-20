/// Integração com o Ollama para inferência local usando o modelo
/// `qwen2.5-coder`.
///
/// Cobre três usos distintos:
///  - Síntese de pesquisa (Modo IA), com streaming NDJSON.
///  - Expansão de sub-buscas, usada pelo Modo IA para pesquisar o
///    tema por múltiplos ângulos (como um "Modo IA" de busca faria).
///  - Chat multi-turno (Modo Offline), via `/api/chat`, sem depender
///    de busca ou scraping.
library levai_scout.ollama_client;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'search_engine.dart';

/// Uma mensagem de uma conversa multi-turno (papel + conteúdo),
/// compatível com o endpoint `/api/chat` do Ollama.
class ChatMessage {
  final String role; // 'system' | 'user' | 'assistant'
  final String content;

  const ChatMessage({required this.role, required this.content});

  Map<String, dynamic> toJson() => {'role': role, 'content': content};
}

/// System prompt do Modo IA: pesquisa + síntese com citação de
/// fontes e perguntas relacionadas ao final, no espírito de um
/// "Modo IA" de busca, porém rodando 100% localmente.
const String kAiModeSystemPrompt = '''
Você é o Levai Scout, um assistente de pesquisa avançado que roda
100% localmente, no espírito de um "Modo IA" de busca, porém sem
depender de nenhum serviço externo.

REGRAS OBRIGATÓRIAS:
1. Baseie sua resposta ESTRITAMENTE no CONTEXTO fornecido, extraído
   ao vivo de páginas web pelo motor de scraping do Levai Scout.
   Nunca utilize conhecimento prévio para preencher lacunas que o
   contexto não cobre.
2. Se o contexto for insuficiente, incompleto ou não responder à
   pergunta do usuário, declare isso explicitamente em vez de
   inventar (alucinar) qualquer informação.
3. Sintetize os dados de múltiplas fontes de forma coesa, objetiva e
   direta, comparando pontos de vista divergentes quando existirem.
4. Utilize Markdown para estruturar a resposta: títulos com "#",
   negrito com "**texto**" e blocos de código com três crases
   quando relevante.
5. Ao final da resposta, inclua obrigatoriamente, nesta ordem:
   a) "## Fontes consultadas" — lista das URLs realmente utilizadas.
   b) "## Perguntas relacionadas" — 3 perguntas curtas que o usuário
      poderia fazer em seguida para aprofundar o tema.
6. Responda sempre em português do Brasil, de forma clara, direta e
   tecnicamente precisa.
''';

/// System prompt do Modo Offline: um assistente de propósito geral,
/// sem acesso à internet, que deve deixar claro os limites do seu
/// próprio conhecimento.
const String kOfflineChatSystemPrompt = '''
Você é o Levai Scout em Modo Offline: um assistente local, rodando
inteiramente no computador do usuário, sem qualquer acesso à
internet nesta conversa.

REGRAS:
1. Responda com base apenas no seu conhecimento interno do modelo.
2. Se a pergunta depender de informação recente ou específica que
   você não tem certeza de conhecer, avise o usuário que, nesse
   caso, o Modo IA (com busca na web) seria mais indicado.
3. Seja direto, técnico quando o assunto pedir, e sempre responda em
   português do Brasil.
4. Utilize Markdown (títulos, negrito, blocos de código) quando isso
   ajudar a organizar a resposta.
''';

/// Exceção lançada quando a comunicação com o Ollama falha.
class OllamaException implements Exception {
  final String message;
  OllamaException(this.message);

  @override
  String toString() => 'OllamaException: $message';
}

/// Cliente para o servidor local do Ollama, especializado no modelo
/// `qwen2.5-coder`, com suporte a streaming de resposta.
class OllamaClient {
  /// URL base do servidor Ollama (padrão: instalação local).
  final String baseUrl;

  /// Nome do modelo a ser utilizado nas chamadas.
  final String model;

  /// Tamanho da janela de contexto, em tokens.
  final int contextWindow;

  /// Temperatura de amostragem. Mantida baixa (0.3–0.4) para
  /// favorecer respostas factuais e determinísticas no Modo IA.
  final double temperature;

  final http.Client _httpClient;

  OllamaClient({
    this.baseUrl = 'http://localhost:11434',
    this.model = 'qwen2.5-coder',
    this.contextWindow = 8192,
    this.temperature = 0.35,
    http.Client? httpClient,
  })  : assert(temperature >= 0.0 && temperature <= 1.0),
        _httpClient = httpClient ?? http.Client();

  /// Gera uma resposta em streaming (token a token) para o Modo IA,
  /// a partir da [userQuery], do [context] extraído pelo scraper e
  /// das [sources] (URLs) que originaram esse contexto.
  Stream<String> generateStream({
    required String userQuery,
    required String context,
    List<SearchResult> sources = const [],
    String systemPrompt = kAiModeSystemPrompt,
  }) async* {
    final prompt = _buildResearchPrompt(userQuery, context, sources);

    final request = http.Request('POST', Uri.parse('$baseUrl/api/generate'));
    request.headers['Content-Type'] = 'application/json';
    request.body = jsonEncode({
      'model': model,
      'prompt': prompt,
      'system': systemPrompt,
      'stream': true,
      'options': {
        'temperature': temperature,
        'num_ctx': contextWindow,
      },
    });

    yield* _streamGenerateResponse(request);
  }

  /// Conversa multi-turno para o Modo Offline, via `/api/chat`. A
  /// lista [messages] deve conter o histórico completo (incluindo a
  /// mensagem mais recente do usuário); o Ollama não guarda estado
  /// entre chamadas.
  Stream<String> chatStream({
    required List<ChatMessage> messages,
    String systemPrompt = kOfflineChatSystemPrompt,
  }) async* {
    final fullMessages = [
      ChatMessage(role: 'system', content: systemPrompt),
      ...messages,
    ];

    final request = http.Request('POST', Uri.parse('$baseUrl/api/chat'));
    request.headers['Content-Type'] = 'application/json';
    request.body = jsonEncode({
      'model': model,
      'messages': fullMessages.map((m) => m.toJson()).toList(),
      'stream': true,
      'options': {
        'temperature': temperature,
        'num_ctx': contextWindow,
      },
    });

    http.StreamedResponse streamedResponse;
    try {
      streamedResponse = await _httpClient.send(request);
    } catch (e) {
      throw OllamaException(
        'Falha ao conectar ao Ollama em $baseUrl. Detalhe: $e',
      );
    }

    if (streamedResponse.statusCode != 200) {
      final body = await streamedResponse.stream.bytesToString();
      throw OllamaException(
        'Ollama retornou status ${streamedResponse.statusCode}: $body',
      );
    }

    final lines = streamedResponse.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    await for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      Map<String, dynamic> decoded;
      try {
        decoded = jsonDecode(trimmed) as Map<String, dynamic>;
      } on FormatException {
        continue;
      }

      if (decoded.containsKey('error')) {
        throw OllamaException(decoded['error'].toString());
      }

      final message = decoded['message'] as Map<String, dynamic>?;
      final token = message?['content'] as String?;
      if (token != null && token.isNotEmpty) {
        yield token;
      }

      if (decoded['done'] == true) break;
    }
  }

  /// Pede ao modelo, em uma chamada não-streaming, de 2 a 3
  /// sub-buscas relacionadas à [query] original — usado pelo Modo IA
  /// para pesquisar o tema por múltiplos ângulos antes de
  /// sintetizar, de forma parecida com um "Modo IA" de busca.
  ///
  /// Em caso de qualquer falha (rede, parsing), retorna uma lista
  /// vazia silenciosamente: a busca expandida é uma otimização, não
  /// um requisito para o funcionamento do Modo IA.
  Future<List<String>> generateRelatedQueries(String query) async {
    final instruction =
        'Gere de 2 a 3 consultas de busca curtas e complementares '
        '(em português) que ajudem a responder a pergunta abaixo '
        'com mais profundidade, cobrindo ângulos diferentes. '
        'Responda APENAS com um array JSON de strings, sem nenhum '
        'texto adicional, sem markdown, sem crases.\n\n'
        'Pergunta: "$query"';

    try {
      final response = await _httpClient
          .post(
            Uri.parse('$baseUrl/api/generate'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'model': model,
              'prompt': instruction,
              'stream': false,
              'options': {'temperature': 0.2, 'num_ctx': contextWindow},
            }),
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode != 200) return const <String>[];

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final rawText = (decoded['response'] as String? ?? '').trim();

      final jsonStart = rawText.indexOf('[');
      final jsonEnd = rawText.lastIndexOf(']');
      if (jsonStart == -1 || jsonEnd == -1 || jsonEnd <= jsonStart) {
        return const <String>[];
      }

      final jsonSlice = rawText.substring(jsonStart, jsonEnd + 1);
      final parsed = jsonDecode(jsonSlice);
      if (parsed is! List) return const <String>[];

      return parsed
          .whereType<String>()
          .map((q) => q.trim())
          .where((q) => q.isNotEmpty && q.toLowerCase() != query.toLowerCase())
          .take(3)
          .toList(growable: false);
    } catch (_) {
      return const <String>[];
    }
  }

  Stream<String> _streamGenerateResponse(http.Request request) async* {
    http.StreamedResponse streamedResponse;
    try {
      streamedResponse = await _httpClient.send(request);
    } catch (e) {
      throw OllamaException(
        'Falha ao conectar ao Ollama em $baseUrl. '
        'Verifique se o serviço "ollama serve" está em execução. '
        'Detalhe: $e',
      );
    }

    if (streamedResponse.statusCode != 200) {
      final body = await streamedResponse.stream.bytesToString();
      throw OllamaException(
        'Ollama retornou status ${streamedResponse.statusCode}: $body',
      );
    }

    final lines = streamedResponse.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    await for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      Map<String, dynamic> decoded;
      try {
        decoded = jsonDecode(trimmed) as Map<String, dynamic>;
      } on FormatException {
        continue;
      }

      if (decoded.containsKey('error')) {
        throw OllamaException(decoded['error'].toString());
      }

      final token = decoded['response'] as String?;
      if (token != null && token.isNotEmpty) {
        yield token;
      }

      if (decoded['done'] == true) break;
    }
  }

  String _buildResearchPrompt(
    String userQuery,
    String context,
    List<SearchResult> sources,
  ) {
    final buffer = StringBuffer();

    buffer.writeln('### PERGUNTA DO USUÁRIO');
    buffer.writeln(userQuery.trim());
    buffer.writeln();

    buffer.writeln('### CONTEXTO EXTRAÍDO DA WEB (via Chromium headless)');
    buffer.writeln(context.trim().isEmpty
        ? '(nenhum conteúdo pôde ser extraído das páginas)'
        : context.trim());
    buffer.writeln();

    if (sources.isNotEmpty) {
      buffer.writeln('### FONTES DISPONÍVEIS');
      for (final source in sources) {
        buffer.writeln('- ${source.title}: ${source.url}');
      }
      buffer.writeln();
    }

    buffer.writeln(
      'Com base estrita no contexto acima, responda à pergunta do '
      'usuário em português, seguindo todas as regras do seu system '
      'prompt, incluindo as seções finais "## Fontes consultadas" e '
      '"## Perguntas relacionadas".',
    );

    return buffer.toString();
  }

  /// Verifica rapidamente se o servidor Ollama está acessível,
  /// consultando o endpoint `/api/tags`.
  Future<bool> healthCheck() async {
    try {
      final response = await _httpClient
          .get(Uri.parse('$baseUrl/api/tags'))
          .timeout(const Duration(seconds: 3));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Libera os recursos do cliente HTTP subjacente.
  void close() => _httpClient.close();
}
