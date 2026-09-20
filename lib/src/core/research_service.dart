import 'dart:async';
import 'dart:io';

import 'package:levai_scout/src/core/config.dart';
import 'package:levai_scout/src/ollama_client.dart';
import 'package:levai_scout/src/pop/pop_engine.dart';
import 'package:levai_scout/src/scraper.dart';
import 'package:levai_scout/src/search_engine.dart';

enum ResearchDepth {
  quick,
  standard,
  deep,
}

class ResearchService {
  final LevaiConfig config;
  final SearxngClient search;
  final OllamaClient ollama;
  final WebScraper scraper;

  ResearchService({
    this.config = const LevaiConfig(),
  })  : search = SearxngClient(baseUrl: config.searxngUrl),
        ollama = OllamaClient(
          baseUrl: config.ollamaUrl,
          model: config.model,
          contextWindow: config.contextWindow,
          temperature: config.temperature,
        ),
        scraper = WebScraper(maxConcurrency: 3);

  Future<void> init() => scraper.init();

  Future<List<SearchResult>> popSearch(
    String input, {
    int maxQueries = 3,
  }) async {
    final pop = PopEngine.generateSearchQueries(
      input,
      maxQueries: maxQueries,
    );

    if (pop.isEmpty) {
      return const [];
    }

    final results = <SearchResult>[];
    final seen = <String>{};

    for (final query in pop) {
      final found = await search.search(
        query,
        maxResults: config.maxResults,
      );

      for (final result in found) {
        if (seen.add(result.url)) {
          results.add(result);
        }
      }
    }

    return results;
  }

  Future<List<SearchResult>> deepSearch(
    String input, {
    ResearchDepth depth = ResearchDepth.standard,
  }) async {
    final queries = <String>[input];

    if (depth != ResearchDepth.quick) {
      queries.addAll(
        PopEngine.generateSearchQueries(
          input,
          maxQueries: depth == ResearchDepth.deep ? 5 : 3,
        ).skip(1),
      );
    }

    final results = <SearchResult>[];
    final seen = <String>{};

    for (final query in queries) {
      final found = await search.search(
        query,
        maxResults: config.maxResults,
      );

      for (final result in found) {
        if (seen.add(result.url)) {
          results.add(result);
        }
      }
    }

    return results;
  }

  Future<String?> synthesize(
    String question,
    List<SearchResult> results,
  ) async {
    if (results.isEmpty) {
      return null;
    }

    final selected = results.take(8).toList();

    stdout.writeln(
      'Lendo ${selected.length} fonte(s) com Chromium...',
    );

    final pages = await scraper.scrapeAll(
      selected.map((result) => result.url).toList(),
    );

    final successful = pages.where((page) => page.success).toList();

    if (successful.isEmpty) {
      return null;
    }

    final context = successful
        .map((page) => page.content)
        .whereType<String>()
        .join('\n\n--- FONTE ---\n\n');

    if (context.trim().isEmpty) {
      return null;
    }

    final buffer = StringBuffer();

    await for (final token in ollama.generateStream(
      userQuery: question,
      context: context,
      sources: selected,
    )) {
      buffer.write(token);
      stdout.write(token);
    }

    stdout.writeln();

    return buffer.toString();
  }

  void close() {
    search.close();
    ollama.close();
  }

  Future<void> dispose() async {
    await scraper.dispose();
    close();
  }
}
