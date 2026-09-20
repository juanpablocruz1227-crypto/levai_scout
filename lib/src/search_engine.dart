/// Cliente de busca para uma instância local do SearXNG.
///
/// Este arquivo define o modelo de dados [SearchResult] e o cliente
/// [SearxngClient], responsável por consultar o endpoint JSON do
/// SearXNG e retornar resultados fortemente tipados para o restante
/// do pipeline do Levai Scout.
library levai_scout.search_engine;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';

/// Representa um único resultado de busca retornado pelo SearXNG.
@immutable
class SearchResult {
  /// Título da página, conforme indexado pelo motor de busca.
  final String title;

  /// URL absoluta da página encontrada.
  final String url;

  /// Trecho (snippet) de conteúdo retornado pelo motor de busca.
  final String snippet;

  const SearchResult({
    required this.title,
    required this.url,
    required this.snippet,
  });

  /// Constrói um [SearchResult] a partir do JSON bruto retornado pelo
  /// SearXNG em `/search?format=json`. Campos ausentes são tratados
  /// com segurança, retornando strings vazias em vez de lançar erro.
  factory SearchResult.fromJson(Map<String, dynamic> json) {
    return SearchResult(
      title: (json['title'] as String?)?.trim() ?? '(sem título)',
      url: (json['url'] as String?)?.trim() ?? '',
      snippet: (json['content'] as String?)?.trim() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'title': title,
        'url': url,
        'snippet': snippet,
      };

  @override
  String toString() => 'SearchResult(title: $title, url: $url)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SearchResult &&
          runtimeType == other.runtimeType &&
          title == other.title &&
          url == other.url &&
          snippet == other.snippet;

  @override
  int get hashCode => Object.hash(title, url, snippet);
}

/// Exceção lançada quando a consulta ao SearXNG falha (rede, status
/// HTTP inesperado ou corpo de resposta inválido).
class SearxngException implements Exception {
  final String message;
  final int? statusCode;

  SearxngException(this.message, {this.statusCode});

  @override
  String toString() => statusCode != null
      ? 'SearxngException [$statusCode]: $message'
      : 'SearxngException: $message';
}

/// Cliente HTTP para uma instância local do SearXNG.
///
/// Por padrão assume que o SearXNG está rodando em
/// `http://localhost:8080`, configuração comum de instalações via
/// Docker Compose. Utilize o parâmetro [baseUrl] para apontar para
/// outra porta/host caso necessário.
class SearxngClient {
  /// URL base da instância do SearXNG (sem barra final).
  final String baseUrl;

  /// Categorias padrão utilizadas na busca (ex: 'general', 'it').
  final List<String> categories;

  final http.Client _httpClient;

  SearxngClient({
    this.baseUrl = 'http://localhost:8080',
    this.categories = const ['general'],
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  /// Executa uma busca no SearXNG e retorna até [maxResults]
  /// resultados estruturados.
  ///
  /// Lança [SearxngException] em caso de falha de rede, status HTTP
  /// diferente de 200, ou corpo de resposta em formato inesperado.
  Future<List<SearchResult>> search(
    String query, {
    int maxResults = 5,
    String language = 'pt-BR',
  }) async {
    if (query.trim().isEmpty) {
      throw SearxngException('A consulta de busca não pode ser vazia.');
    }

    final uri = Uri.parse('$baseUrl/search').replace(queryParameters: {
      'q': query,
      'format': 'json',
      'language': language,
      'categories': categories.join(','),
    });

    http.Response response;
    try {
      response = await _httpClient.get(
        uri,
        headers: const {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 15));
    } catch (e) {
      throw SearxngException(
        'Falha ao conectar ao SearXNG em $baseUrl. '
        'Verifique se o serviço está em execução. Detalhe: $e',
      );
    }

    if (response.statusCode != 200) {
      throw SearxngException(
        'O SearXNG retornou um status inesperado.',
        statusCode: response.statusCode,
      );
    }

    late final Map<String, dynamic> decoded;
    try {
      decoded = jsonDecode(response.body) as Map<String, dynamic>;
    } on FormatException catch (e) {
      throw SearxngException(
        'Resposta do SearXNG não é um JSON válido. '
        'Certifique-se de que o formato "json" está habilitado no '
        'settings.yml da instância. Detalhe: $e',
      );
    }

    final rawResults = decoded['results'];
    if (rawResults is! List) {
      return const <SearchResult>[];
    }

    return rawResults
        .whereType<Map<String, dynamic>>()
        .map(SearchResult.fromJson)
        .where((result) => result.url.isNotEmpty)
        .take(maxResults)
        .toList(growable: false);
  }

  /// Libera os recursos do cliente HTTP subjacente.
  void close() => _httpClient.close();
}
