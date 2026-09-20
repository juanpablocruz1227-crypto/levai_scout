/// Levai Scout — ponto de entrada da aplicação de linha de comando.
///
/// Suporta três modos de operação (ver [AppMode]):
///   - IA Avançada: busca + sub-buscas + scraping + síntese com LLM.
///   - Busca Direta: apenas lista os resultados, sem IA.
///   - Chat Offline: conversa direta com o LLM, sem internet.
///
/// Em qualquer modo, o comando `/open` funciona como um mini
/// navegador de terminal, lendo uma página inteira (por número da
/// última busca ou por URL direta) com um paginador estilo `less`.
library levai_scout.main;

import 'dart:async';
import 'dart:io';

import 'package:levai_scout/src/app_mode.dart';
import 'package:levai_scout/src/markdown_renderer.dart';
import 'package:levai_scout/src/ollama_client.dart';
import 'package:levai_scout/src/pager.dart';
import 'package:levai_scout/src/scraper.dart';
import 'package:levai_scout/src/search_engine.dart';

const String _kAsciiArt = r'''
 _     _______     ___    ___   ____   ____ ___  _   _ _____
| |   | ____\ \   / / \  |_ _| / ___| / ___/ _ \| | | |_   _|
| |   |  _|  \ \ / / _ \  | |  \___ \| |  | | | | | | | | |
| |___| |___  \ V / ___ \ | |   ___) | |__| |_| | |_| | | |
|_____|_____|  \_/_/   \_\___| |____/ \____\___/ \___/  |_|

              Pesquisa Local, Privada e Sem Nuvem
''';

const String _kSearxngUrl = 'http://localhost:8080';
const String _kOllamaUrl = 'http://localhost:11434';
const String _kOllamaModel = 'qwen2.5-coder';
const int _kMaxSearchResults = 5;
const int _kScraperConcurrency = 3;

/// Uma entrada do histórico de sessão (pergunta + resposta/ação).
class _HistoryEntry {
  final AppMode mode;
  final String query;
  final DateTime timestamp;

  _HistoryEntry(this.mode, this.query) : timestamp = DateTime.now();
}

Future<void> main(List<String> arguments) async {
  _printAsciiArt();

  final searxngClient = SearxngClient(baseUrl: _kSearxngUrl);
  final ollamaClient = OllamaClient(
    baseUrl: _kOllamaUrl,
    model: _kOllamaModel,
    contextWindow: 8192,
    temperature: 0.35,
  );
  final scraper = WebScraper(maxConcurrency: _kScraperConcurrency);
  final renderer = MarkdownRenderer();
  final pager = TerminalPager();

  final history = <_HistoryEntry>[];
  final offlineChatHistory = <ChatMessage>[];
  List<SearchResult> lastResults = const [];

  final healthy = await _runHealthCheck(searxngClient, ollamaClient);

  await scraper.init();

  var currentMode = await _promptModeSelection(AppMode.aiMode, healthy);
  _printModeBanner(currentMode);
  _printHelp();

  bool running = true;
  while (running) {
    stdout.write(
      '${AnsiCodes.cyan}${AnsiCodes.bold}scout'
      '${AnsiCodes.reset}${AnsiCodes.gray}[${currentMode.shortTag}]'
      '${AnsiCodes.reset}${AnsiCodes.cyan}${AnsiCodes.bold}›'
      '${AnsiCodes.reset} ',
    );
    final input = stdin.readLineSync(encoding: SystemEncoding())?.trim();

    if (input == null || input.isEmpty) continue;

    if (input == '/quit' || input == '/exit') {
      running = false;
      continue;
    }
    if (input == '/clear') {
      _clearScreen();
      _printAsciiArt();
      _printModeBanner(currentMode);
      continue;
    }
    if (input == '/history') {
      _printHistory(history);
      continue;
    }
    if (input == '/help') {
      _printHelp();
      continue;
    }
    if (input == '/mode' || input == '/modes') {
      currentMode = await _promptModeSelection(currentMode, healthy);
      _printModeBanner(currentMode);
      continue;
    }
    if (input.startsWith('/open')) {
      await _handleOpenCommand(
        input: input,
        lastResults: lastResults,
        scraper: scraper,
        pager: pager,
      );
      continue;
    }

    try {
      switch (currentMode) {
        case AppMode.aiMode:
          final results = await _handleAiQuery(
            query: input,
            searxngClient: searxngClient,
            scraper: scraper,
            ollamaClient: ollamaClient,
            renderer: renderer,
          );
          if (results != null) lastResults = results;
          break;

        case AppMode.noAiMode:
          final results = await _handleSearchOnlyQuery(
            query: input,
            searxngClient: searxngClient,
          );
          lastResults = results;
          break;

        case AppMode.offlineMode:
          await _handleOfflineChat(
            query: input,
            ollamaClient: ollamaClient,
            renderer: renderer,
            history: offlineChatHistory,
          );
          break;
      }
      history.add(_HistoryEntry(currentMode, input));
    } catch (e) {
      stdout.writeln(
        '${AnsiCodes.yellow}Erro ao processar: $e${AnsiCodes.reset}\n',
      );
    }
  }

  stdout.writeln('\nEncerrando o Levai Scout...');
  searxngClient.close();
  ollamaClient.close();
  await scraper.dispose();
  exit(0);
}

// ---------------------------------------------------------------------------
// MODO IA — busca expandida + scraping + síntese
// ---------------------------------------------------------------------------

/// Executa o pipeline completo do Modo IA: gera sub-buscas
/// relacionadas, busca todas em paralelo, raspa as páginas e
/// sintetiza uma resposta única com o LLM local.
///
/// Retorna a lista de [SearchResult] usada (para permitir `/open`
/// por número depois), ou `null` se a busca não retornou nada.
Future<List<SearchResult>?> _handleAiQuery({
  required String query,
  required SearxngClient searxngClient,
  required WebScraper scraper,
  required OllamaClient ollamaClient,
  required MarkdownRenderer renderer,
}) async {
  stdout.writeln(
    '${AnsiCodes.gray}Gerando sub-buscas relacionadas...${AnsiCodes.reset}',
  );
  final relatedQueries = await ollamaClient.generateRelatedQueries(query);
  final allQueries = [query, ...relatedQueries];

  if (relatedQueries.isNotEmpty) {
    stdout.writeln(
      '${AnsiCodes.gray}Sub-buscas: '
      '${relatedQueries.join(" | ")}${AnsiCodes.reset}',
    );
  }

  stdout.writeln('${AnsiCodes.gray}Buscando no SearXNG...${AnsiCodes.reset}');

  final seenUrls = <String>{};
  final aggregatedResults = <SearchResult>[];
  for (final q in allQueries) {
    try {
      final results =
          await searxngClient.search(q, maxResults: _kMaxSearchResults);
      for (final result in results) {
        if (seenUrls.add(result.url)) {
          aggregatedResults.add(result);
        }
      }
    } catch (_) {
      // Uma sub-busca falhar não deve interromper o fluxo principal.
      continue;
    }
  }

  if (aggregatedResults.isEmpty) {
    stdout.writeln(
      '${AnsiCodes.yellow}Nenhum resultado encontrado para '
      '"$query".${AnsiCodes.reset}\n',
    );
    return null;
  }

  final topResults = aggregatedResults.take(_kMaxSearchResults * 2).toList();

  stdout.writeln(
    '${AnsiCodes.gray}${topResults.length} resultado(s) combinados. '
    'Raspando páginas (até $_kScraperConcurrency simultâneas)...'
    '${AnsiCodes.reset}',
  );

  final urls = topResults.map((r) => r.url).toList(growable: false);
  final scrapedPages = await scraper.scrapeAll(urls);
  final successfulPages = scrapedPages.where((p) => p.success).toList();

  if (successfulPages.isEmpty) {
    stdout.writeln(
      '${AnsiCodes.yellow}Não foi possível extrair conteúdo de '
      'nenhuma página encontrada.${AnsiCodes.reset}\n',
    );
    return topResults;
  }

  final combinedContext = successfulPages
      .map((p) => '### Fonte: ${p.url}\n${_truncate(p.content, 6000)}')
      .join('\n\n---\n\n');

  stdout.writeln(
    '${AnsiCodes.gray}Sintetizando resposta com $_kOllamaModel...'
    '${AnsiCodes.reset}\n',
  );

  final rawAnswerBuffer = StringBuffer();
  await for (final token in ollamaClient.generateStream(
    userQuery: query,
    context: combinedContext,
    sources: topResults,
  )) {
    rawAnswerBuffer.write(token);
  }

  stdout.writeln(renderer.render(rawAnswerBuffer.toString()));
  stdout.writeln();

  _printNumberedResultsHint(topResults);
  return topResults;
}

// ---------------------------------------------------------------------------
// MODO SEM IA — apenas busca e lista resultados
// ---------------------------------------------------------------------------

/// Busca no SearXNG e imprime apenas a lista numerada de resultados
/// (título, URL, resumo), sem chamar o LLM.
Future<List<SearchResult>> _handleSearchOnlyQuery({
  required String query,
  required SearxngClient searxngClient,
}) async {
  final results =
      await searxngClient.search(query, maxResults: _kMaxSearchResults);

  if (results.isEmpty) {
    stdout.writeln(
      '${AnsiCodes.yellow}Nenhum resultado encontrado para '
      '"$query".${AnsiCodes.reset}\n',
    );
    return const [];
  }

  stdout.writeln();
  for (var i = 0; i < results.length; i++) {
    final result = results[i];
    stdout.writeln(
      '${AnsiCodes.yellow}${AnsiCodes.bold}[${i + 1}]${AnsiCodes.reset} '
      '${AnsiCodes.white}${AnsiCodes.bold}${result.title}${AnsiCodes.reset}',
    );
    stdout.writeln('    ${AnsiCodes.blue}${result.url}${AnsiCodes.reset}');
    if (result.snippet.isNotEmpty) {
      stdout.writeln('    ${AnsiCodes.gray}${_truncate(result.snippet, 200)}'
          '${AnsiCodes.reset}');
    }
    stdout.writeln();
  }

  stdout.writeln(
    '${AnsiCodes.gray}Use /open <nº> para ler a página inteira.'
    '${AnsiCodes.reset}\n',
  );

  return results;
}

// ---------------------------------------------------------------------------
// MODO OFFLINE — chat multi-turno sem busca
// ---------------------------------------------------------------------------

/// Envia [query] ao LLM local mantendo o histórico da conversa
/// (Modo Offline), sem qualquer busca ou scraping.
Future<void> _handleOfflineChat({
  required String query,
  required OllamaClient ollamaClient,
  required MarkdownRenderer renderer,
  required List<ChatMessage> history,
}) async {
  history.add(ChatMessage(role: 'user', content: query));

  final buffer = StringBuffer();
  await for (final token in ollamaClient.chatStream(messages: history)) {
    buffer.write(token);
  }

  final answer = buffer.toString();
  history.add(ChatMessage(role: 'assistant', content: answer));

  stdout.writeln(renderer.render(answer));
  stdout.writeln();
}

// ---------------------------------------------------------------------------
// COMANDO /open — mini navegador de terminal
// ---------------------------------------------------------------------------

/// Trata o comando `/open <nº|url>`, lendo a página inteira (via
/// Chromium + limpeza de HTML) e exibindo com o [TerminalPager].
Future<void> _handleOpenCommand({
  required String input,
  required List<SearchResult> lastResults,
  required WebScraper scraper,
  required TerminalPager pager,
}) async {
  final argument = input.replaceFirst('/open', '').trim();

  if (argument.isEmpty) {
    stdout.writeln(
      '${AnsiCodes.yellow}Uso: /open <nº do resultado> ou /open <url>'
      '${AnsiCodes.reset}\n',
    );
    return;
  }

  String targetUrl;
  String? title;

  final asNumber = int.tryParse(argument);
  if (asNumber != null) {
    if (asNumber < 1 || asNumber > lastResults.length) {
      stdout.writeln(
        '${AnsiCodes.yellow}Não há resultado nº $asNumber na última '
        'busca.${AnsiCodes.reset}\n',
      );
      return;
    }
    final selected = lastResults[asNumber - 1];
    targetUrl = selected.url;
    title = selected.title;
  } else if (argument.startsWith('http://') ||
      argument.startsWith('https://')) {
    targetUrl = argument;
    title = argument;
  } else {
    stdout.writeln(
      '${AnsiCodes.yellow}Argumento inválido. Use um número da última '
      'busca ou uma URL começando com http:// ou https://'
      '${AnsiCodes.reset}\n',
    );
    return;
  }

  stdout.writeln('${AnsiCodes.gray}Abrindo $targetUrl...${AnsiCodes.reset}');
  final page = await scraper.scrapeOne(targetUrl);

  if (!page.success) {
    stdout.writeln(
      '${AnsiCodes.yellow}Não foi possível abrir a página: '
      '${page.error}${AnsiCodes.reset}\n',
    );
    return;
  }

  pager.show(page.content, title: title);
}

// ---------------------------------------------------------------------------
// UTILITÁRIOS DE INTERFACE
// ---------------------------------------------------------------------------

String _truncate(String text, int maxChars) {
  if (text.length <= maxChars) return text;
  return '${text.substring(0, maxChars)}\n[...conteúdo truncado...]';
}

Future<bool> _runHealthCheck(
  SearxngClient searxngClient,
  OllamaClient ollamaClient,
) async {
  stdout
      .writeln('${AnsiCodes.gray}Executando health check...${AnsiCodes.reset}');

  bool searxngOk;
  try {
    await searxngClient.search('ping', maxResults: 1);
    searxngOk = true;
  } catch (_) {
    searxngOk = false;
  }

  final ollamaOk = await ollamaClient.healthCheck();

  _printServiceStatus('SearXNG', _kSearxngUrl, searxngOk);
  _printServiceStatus('Ollama ($_kOllamaModel)', _kOllamaUrl, ollamaOk);
  stdout.writeln();

  if (!searxngOk) {
    stdout.writeln(
      '${AnsiCodes.yellow}Aviso: sem SearXNG, os modos "IA Avançada" e '
      '"Busca Direta" não funcionarão. Use o Chat Offline enquanto '
      'isso.${AnsiCodes.reset}\n',
    );
  }

  return searxngOk && ollamaOk;
}

void _printServiceStatus(String name, String url, bool healthy) {
  final icon = healthy
      ? '${AnsiCodes.green}✓${AnsiCodes.reset}'
      : '${AnsiCodes.yellow}✗${AnsiCodes.reset}';
  stdout.writeln('  $icon $name ${AnsiCodes.gray}($url)${AnsiCodes.reset}');
}

void _printAsciiArt() {
  stdout.writeln('${AnsiCodes.cyan}$_kAsciiArt${AnsiCodes.reset}');
}

/// Exibe o menu de seleção de modo e lê a escolha do usuário.
/// ENTER em branco mantém [current]. Se [searxngHealthy] for falso,
/// avisa que os modos com busca podem falhar, mas não bloqueia a
/// escolha (o usuário pode preferir tentar mesmo assim).
Future<AppMode> _promptModeSelection(
    AppMode current, bool searxngHealthy) async {
  stdout.writeln(
    '${AnsiCodes.cyan}${AnsiCodes.bold}Escolha o modo de operação:'
    '${AnsiCodes.reset}',
  );
  for (final mode in AppMode.values) {
    final marker =
        mode == current ? '${AnsiCodes.green}●' : '${AnsiCodes.gray}○';
    stdout.writeln(
      '  $marker${AnsiCodes.reset} ${AnsiCodes.bold}${mode.menuIndex}. '
      '${mode.title}${AnsiCodes.reset}',
    );
    stdout
        .writeln('     ${AnsiCodes.gray}${mode.description}${AnsiCodes.reset}');
  }
  stdout.write(
    '${AnsiCodes.gray}Digite o número (ENTER mantém "${current.title}"): '
    '${AnsiCodes.reset}',
  );

  final input = stdin.readLineSync()?.trim();
  if (input == null || input.isEmpty) return current;

  final parsed = int.tryParse(input);
  final selected = parsed == null ? null : AppModeInfo.fromMenuIndex(parsed);

  if (selected == null) {
    stdout.writeln(
      '${AnsiCodes.yellow}Opção inválida, mantendo "${current.title}".'
      '${AnsiCodes.reset}',
    );
    return current;
  }

  return selected;
}

void _printModeBanner(AppMode mode) {
  stdout.writeln(
    '${AnsiCodes.green}${AnsiCodes.bold}✔ Modo ativo: ${mode.title}'
    '${AnsiCodes.reset}\n',
  );
}

void _printHelp() {
  stdout.writeln(
    '${AnsiCodes.gray}Digite sua pergunta ou use um dos comandos abaixo:'
    '${AnsiCodes.reset}',
  );
  stdout.writeln('  ${AnsiCodes.yellow}/mode${AnsiCodes.reset}       '
      '— abre o menu para trocar de modo de operação');
  stdout.writeln('  ${AnsiCodes.yellow}/open <nº|url>${AnsiCodes.reset} '
      '— lê uma página inteira (da última busca ou por URL)');
  stdout.writeln('  ${AnsiCodes.yellow}/history${AnsiCodes.reset}    '
      '— mostra o histórico da sessão');
  stdout.writeln('  ${AnsiCodes.yellow}/clear${AnsiCodes.reset}      '
      '— limpa a tela');
  stdout.writeln('  ${AnsiCodes.yellow}/help${AnsiCodes.reset}       '
      '— mostra esta ajuda');
  stdout.writeln('  ${AnsiCodes.yellow}/quit${AnsiCodes.reset}       '
      '— encerra o Levai Scout');
  stdout.writeln();
}

void _printHistory(List<_HistoryEntry> history) {
  if (history.isEmpty) {
    stdout.writeln(
      '${AnsiCodes.gray}Nenhuma interação nesta sessão ainda.'
      '${AnsiCodes.reset}\n',
    );
    return;
  }

  stdout.writeln('${AnsiCodes.cyan}${AnsiCodes.bold}Histórico da sessão:'
      '${AnsiCodes.reset}');
  for (var i = 0; i < history.length; i++) {
    final entry = history[i];
    final time = '${entry.timestamp.hour.toString().padLeft(2, '0')}:'
        '${entry.timestamp.minute.toString().padLeft(2, '0')}';
    stdout.writeln(
      '  ${AnsiCodes.gray}[$time][${entry.mode.shortTag}]${AnsiCodes.reset} '
      '${AnsiCodes.bold}${i + 1}.${AnsiCodes.reset} ${entry.query}',
    );
  }
  stdout.writeln();
}

void _printNumberedResultsHint(List<SearchResult> results) {
  stdout.writeln('${AnsiCodes.gray}Fontes desta resposta (use /open <nº> '
      'para ler a página inteira):${AnsiCodes.reset}');
  for (var i = 0; i < results.length; i++) {
    stdout.writeln(
      '  ${AnsiCodes.yellow}[${i + 1}]${AnsiCodes.reset} '
      '${AnsiCodes.gray}${results[i].url}${AnsiCodes.reset}',
    );
  }
  stdout.writeln();
}

void _clearScreen() {
  if (Platform.isWindows) {
    stdout.write('\x1B[2J\x1B[0f');
  } else {
    stdout.write('\x1B[2J\x1B[H');
  }
}
