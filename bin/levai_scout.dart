/// Levai Scout — ponto de entrada da aplicação de linha de comando.
///
/// Modos principais:
///   - IA Avançada: pesquisa + leitura de fontes + síntese com Ollama.
///   - Busca Direta: apenas pesquisa no SearXNG.
///   - Chat Offline: conversa direta com o Ollama.
///
/// Comandos 2.0:
///   ? pergunta
///   /pop pergunta
///   /search pergunta
///   /ask pergunta
///   /open <nº|url>
///   /models
///   /health
///   /history
///   /clear
///   /help
///   /quit
library levai_scout.main;

import 'dart:io';

import 'package:levai_scout/src/app_mode.dart';
import 'package:levai_scout/src/commands/command_router.dart';
import 'package:levai_scout/src/markdown_renderer.dart';
import 'package:levai_scout/src/ollama/model_manager.dart';
import 'package:levai_scout/src/ollama_client.dart';
import 'package:levai_scout/src/pager.dart';
import 'package:levai_scout/src/core/research_service.dart';
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

class _HistoryEntry {
  final AppMode mode;
  final String query;
  final DateTime timestamp;

  _HistoryEntry(
    this.mode,
    this.query,
  ) : timestamp = DateTime.now();
}

Future<void> main(List<String> arguments) async {
  _printAsciiArt();

  final searxngClient = SearxngClient(
    baseUrl: _kSearxngUrl,
  );

  final ollamaClient = OllamaClient(
    baseUrl: _kOllamaUrl,
    model: _kOllamaModel,
    contextWindow: 8192,
    temperature: 0.35,
  );

  final scraper = WebScraper(
    maxConcurrency: _kScraperConcurrency,
  );

  final renderer = MarkdownRenderer();
  final pager = TerminalPager();

  // Router principal da versão 2.0.
  final commandRouter = CommandRouter();

  // Serviço de pesquisa da arquitetura 2.0.
  final researchService = ResearchService();

  final history = <_HistoryEntry>[];
  final offlineChatHistory = <ChatMessage>[];

  List<SearchResult> lastResults = const [];

  try {
    await researchService.init();
    await scraper.init();

    final healthy = await _runHealthCheck(
      searxngClient,
      ollamaClient,
    );

    var currentMode = await _promptModeSelection(
      AppMode.aiMode,
      healthy,
    );

    _printModeBanner(currentMode);
    _printHelp();

    var running = true;

    while (running) {
      stdout.write(
        '${AnsiCodes.cyan}${AnsiCodes.bold}scout'
        '${AnsiCodes.reset}${AnsiCodes.gray}'
        '[${currentMode.shortTag}]'
        '${AnsiCodes.reset}${AnsiCodes.cyan}${AnsiCodes.bold}'
        '›'
        '${AnsiCodes.reset} ',
      );

      final input = stdin
          .readLineSync(
            encoding: SystemEncoding(),
          )
          ?.trim();

      if (input == null || input.isEmpty) {
        continue;
      }

      /*
       * ================================================================
       * NOVO ROUTER 2.0
       * ================================================================
       */

      final command = commandRouter.parse(input);

      switch (command.type) {
        // --------------------------------------------------------------
        // ? pergunta
        // /pop pergunta
        // --------------------------------------------------------------
        case CommandType.pop:
          final query = command.argument.trim();

          if (query.isEmpty) {
            stdout.writeln(
              '${AnsiCodes.yellow}'
              'Uso: ? <pergunta>'
              '${AnsiCodes.reset}\n',
            );
            continue;
          }

          try {
            final results = await _handlePopCommand(
              query: query,
              researchService: researchService,
            );

            if (results.isNotEmpty) {
              lastResults = results;
            }

            history.add(
              _HistoryEntry(
                currentMode,
                input,
              ),
            );
          } catch (error) {
            stdout.writeln(
              '${AnsiCodes.yellow}'
              'Erro no POP: $error'
              '${AnsiCodes.reset}\n',
            );
          }

          continue;

        // --------------------------------------------------------------
        // /search pergunta
        // --------------------------------------------------------------
        case CommandType.search:
          final query = command.argument.trim();

          if (query.isEmpty) {
            stdout.writeln(
              '${AnsiCodes.yellow}'
              'Uso: /search <pergunta>'
              '${AnsiCodes.reset}\n',
            );
            continue;
          }

          try {
            final results = await _handleSearchOnlyQuery(
              query: query,
              searxngClient: searxngClient,
            );

            lastResults = results;

            history.add(
              _HistoryEntry(
                currentMode,
                input,
              ),
            );
          } catch (error) {
            stdout.writeln(
              '${AnsiCodes.yellow}'
              'Erro na busca: $error'
              '${AnsiCodes.reset}\n',
            );
          }

          continue;

        // --------------------------------------------------------------
        // /ask pergunta
        // --------------------------------------------------------------
        case CommandType.ask:
          final query = command.argument.trim();

          if (query.isEmpty) {
            stdout.writeln(
              '${AnsiCodes.yellow}'
              'Uso: /ask <pergunta>'
              '${AnsiCodes.reset}\n',
            );
            continue;
          }

          try {
            final results = await _handleAskCommand(
              query: query,
              researchService: researchService,
            );

            if (results.isNotEmpty) {
              lastResults = results;
            }

            history.add(
              _HistoryEntry(
                currentMode,
                input,
              ),
            );
          } catch (error) {
            stdout.writeln(
              '${AnsiCodes.yellow}'
              'Erro na pesquisa profunda: $error'
              '${AnsiCodes.reset}\n',
            );
          }

          continue;

        // --------------------------------------------------------------
        // /open
        // --------------------------------------------------------------
        case CommandType.query:
          /*
           * Texto normal continua respeitando o modo atual.
           */
          try {
            switch (currentMode) {
              case AppMode.aiMode:
                final results = await _handleAiQuery(
                  query: command.argument,
                  searxngClient: searxngClient,
                  scraper: scraper,
                  ollamaClient: ollamaClient,
                  renderer: renderer,
                );

                if (results != null) {
                  lastResults = results;
                }
                break;

              case AppMode.noAiMode:
                final results = await _handleSearchOnlyQuery(
                  query: command.argument,
                  searxngClient: searxngClient,
                );

                lastResults = results;
                break;

              case AppMode.offlineMode:
                await _handleOfflineChat(
                  query: command.argument,
                  ollamaClient: ollamaClient,
                  renderer: renderer,
                  history: offlineChatHistory,
                );
                break;
            }

            history.add(
              _HistoryEntry(
                currentMode,
                input,
              ),
            );
          } catch (error) {
            stdout.writeln(
              '${AnsiCodes.yellow}'
              'Erro ao processar: $error'
              '${AnsiCodes.reset}\n',
            );
          }

          continue;

        // --------------------------------------------------------------
        // /history
        // --------------------------------------------------------------
        case CommandType.open:
          await _handleOpenCommand(
            input: input,
            lastResults: lastResults,
            scraper: scraper,
            pager: pager,
          );
          continue;

        case CommandType.mode:
          currentMode = await _promptModeSelection(
            currentMode,
            healthy,
          );

          _printModeBanner(currentMode);
          continue;
        case CommandType.history:
          _printHistory(history);
          continue;

        // --------------------------------------------------------------
        // /clear
        // --------------------------------------------------------------
        case CommandType.clear:
          _clearScreen();
          _printAsciiArt();
          _printModeBanner(currentMode);
          continue;

        // --------------------------------------------------------------
        // /help
        // --------------------------------------------------------------
        case CommandType.help:
          _printHelp();
          continue;

        // --------------------------------------------------------------
        // /quit
        // /exit
        // --------------------------------------------------------------
        case CommandType.quit:
          running = false;
          continue;

        // --------------------------------------------------------------
        // /mode
        // --------------------------------------------------------------
        case CommandType.unknown:
          final raw = input.toLowerCase();

          if (raw == '/mode' || raw == '/modes') {
            currentMode = await _promptModeSelection(
              currentMode,
              healthy,
            );

            _printModeBanner(currentMode);
            continue;
          }

          /*
           * Alguns comandos já foram definidos pelo CommandRouter,
           * mas ainda estão sendo implementados no núcleo 2.0.
           */
          if (raw.startsWith('/study') ||
              raw.startsWith('/summary') ||
              raw.startsWith('/quiz') ||
              raw.startsWith('/flashcard') ||
              raw.startsWith('/flashcards')) {
            stdout.writeln(
              '${AnsiCodes.yellow}'
              'Study Mode 2.0 ainda está sendo integrado.'
              '${AnsiCodes.reset}',
            );
            stdout.writeln(
              '${AnsiCodes.gray}'
              'Por enquanto use /ask para pesquisar e estudar um tema.'
              '${AnsiCodes.reset}\n',
            );
            continue;
          }

          if (raw == '/models') {
            await _handleModelsCommand(
              ollamaUrl: _kOllamaUrl,
            );
            continue;
          }

          if (raw.startsWith('/model')) {
            stdout.writeln(
              '${AnsiCodes.yellow}'
              'Troca de modelo ainda está sendo integrada.'
              '${AnsiCodes.reset}\n',
            );
            continue;
          }

          if (raw == '/sources') {
            _printNumberedResultsHint(lastResults);
            continue;
          }

          if (raw == '/health') {
            await _runHealthCheck(
              searxngClient,
              ollamaClient,
            );
            continue;
          }

          stdout.writeln(
            '${AnsiCodes.yellow}'
            'Comando desconhecido: $input'
            '${AnsiCodes.reset}',
          );
          stdout.writeln(
            '${AnsiCodes.gray}'
            'Use /help para ver os comandos disponíveis.'
            '${AnsiCodes.reset}\n',
          );
          continue;

        // --------------------------------------------------------------
        // Comandos reconhecidos que não precisam de processamento aqui.
        // --------------------------------------------------------------
        case CommandType.study:
        case CommandType.summary:
        case CommandType.quiz:
        case CommandType.flashcards:
        case CommandType.models:
        case CommandType.model:
        case CommandType.sources:
        case CommandType.health:
          /*
           * Estes casos são tratados acima através do conteúdo original
           * quando necessário. Este bloco existe para manter o switch
           * exaustivo e preparado para a próxima etapa do Study Mode.
           */
          continue;
      }
    }
  } finally {
    stdout.writeln(
      '\n${AnsiCodes.gray}'
      'Encerrando o Levai Scout...'
      '${AnsiCodes.reset}',
    );

    await researchService.dispose();

    searxngClient.close();
    ollamaClient.close();

    await scraper.dispose();
  }
}

// ===========================================================================
// POP 2.0
// ===========================================================================

Future<List<SearchResult>> _handlePopCommand({
  required String query,
  required ResearchService researchService,
}) async {
  stdout.writeln(
    '\n${AnsiCodes.cyan}${AnsiCodes.bold}'
    'POP — Pesquisa Orientada à Pesquisa'
    '${AnsiCodes.reset}',
  );

  stdout.writeln(
    '${AnsiCodes.gray}'
    'Pergunta: $query'
    '${AnsiCodes.reset}\n',
  );

  stdout.writeln(
    '${AnsiCodes.gray}'
    'Gerando pesquisas relacionadas...'
    '${AnsiCodes.reset}',
  );

  final results = await researchService.popSearch(
    query,
    maxQueries: 3,
  );

  if (results.isEmpty) {
    stdout.writeln(
      '${AnsiCodes.yellow}'
      'Nenhum resultado encontrado.'
      '${AnsiCodes.reset}\n',
    );

    return const [];
  }

  stdout.writeln();

  final visibleResults = results.take(8).toList();

  for (var i = 0; i < visibleResults.length; i++) {
    final result = visibleResults[i];

    stdout.writeln(
      '${AnsiCodes.yellow}${AnsiCodes.bold}'
      '[${i + 1}]'
      '${AnsiCodes.reset} '
      '${AnsiCodes.white}${AnsiCodes.bold}'
      '${result.title}'
      '${AnsiCodes.reset}',
    );

    stdout.writeln(
      '    ${AnsiCodes.blue}'
      '${result.url}'
      '${AnsiCodes.reset}',
    );

    if (result.snippet.isNotEmpty) {
      stdout.writeln(
        '    ${AnsiCodes.gray}'
        '${_truncate(result.snippet, 220)}'
        '${AnsiCodes.reset}',
      );
    }

    stdout.writeln();
  }

  stdout.writeln(
    '${AnsiCodes.gray}'
    'POP terminou sem Chromium e sem síntese do Ollama.'
    '${AnsiCodes.reset}',
  );

  stdout.writeln(
    '${AnsiCodes.gray}'
    'Use /open <nº> para ler uma fonte.'
    '${AnsiCodes.reset}\n',
  );

  return visibleResults;
}

// ===========================================================================
// ASK 2.0
// ===========================================================================

Future<List<SearchResult>> _handleAskCommand({
  required String query,
  required ResearchService researchService,
}) async {
  stdout.writeln(
    '\n${AnsiCodes.cyan}${AnsiCodes.bold}'
    'Levai Scout — Pesquisa Profunda'
    '${AnsiCodes.reset}\n',
  );

  final results = await researchService.deepSearch(
    query,
    depth: ResearchDepth.standard,
  );

  if (results.isEmpty) {
    stdout.writeln(
      '${AnsiCodes.yellow}'
      'Nenhuma fonte encontrada para "$query".'
      '${AnsiCodes.reset}\n',
    );

    return const [];
  }

  stdout.writeln(
    '${AnsiCodes.gray}'
    '${results.length} fonte(s) encontrada(s).'
    '${AnsiCodes.reset}',
  );

  final answer = await researchService.synthesize(
    query,
    results,
  );

  if (answer == null || answer.trim().isEmpty) {
    stdout.writeln(
      '${AnsiCodes.yellow}'
      'Não foi possível sintetizar uma resposta.'
      '${AnsiCodes.reset}\n',
    );

    return results;
  }

  _printNumberedResultsHint(results);

  return results;
}

// ===========================================================================
// MODO IA — fluxo legado compatível
// ===========================================================================

Future<List<SearchResult>?> _handleAiQuery({
  required String query,
  required SearxngClient searxngClient,
  required WebScraper scraper,
  required OllamaClient ollamaClient,
  required MarkdownRenderer renderer,
}) async {
  stdout.writeln(
    '${AnsiCodes.gray}'
    'Buscando no SearXNG...'
    '${AnsiCodes.reset}',
  );

  /*
   * O modo IA normal agora começa pela pergunta original.
   *
   * Isso evita chamar Ollama apenas para criar sub-buscas antes
   * de qualquer pesquisa. Para pesquisa profunda, use /ask.
   */
  final results = await searxngClient.search(
    query,
    maxResults: _kMaxSearchResults,
  );

  if (results.isEmpty) {
    stdout.writeln(
      '${AnsiCodes.yellow}'
      'Nenhum resultado encontrado para "$query".'
      '${AnsiCodes.reset}\n',
    );

    return null;
  }

  final topResults = results.take(_kMaxSearchResults).toList();

  stdout.writeln(
    '${AnsiCodes.gray}'
    '${topResults.length} resultado(s) encontrado(s).'
    '${AnsiCodes.reset}',
  );

  stdout.writeln(
    '${AnsiCodes.gray}'
    'Lendo páginas com Chromium...'
    '${AnsiCodes.reset}',
  );

  final urls = topResults
      .map((result) => result.url)
      .where((url) => url.isNotEmpty)
      .toList();

  final scrapedPages = await scraper.scrapeAll(urls);

  final successfulPages = scrapedPages.where((page) => page.success).toList();

  if (successfulPages.isEmpty) {
    stdout.writeln(
      '${AnsiCodes.yellow}'
      'Não foi possível extrair conteúdo das páginas.'
      '${AnsiCodes.reset}\n',
    );

    return topResults;
  }

  final combinedContext = successfulPages
      .map(
        (page) => '### Fonte: ${page.url}\n${_truncate(page.content, 6000)}',
      )
      .join('\n\n---\n\n');

  stdout.writeln(
    '${AnsiCodes.gray}'
    'Sintetizando resposta com $_kOllamaModel...'
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

  stdout.writeln(
    renderer.render(
      rawAnswerBuffer.toString(),
    ),
  );

  stdout.writeln();

  _printNumberedResultsHint(topResults);

  return topResults;
}

// ===========================================================================
// BUSCA DIRETA
// ===========================================================================

Future<List<SearchResult>> _handleSearchOnlyQuery({
  required String query,
  required SearxngClient searxngClient,
}) async {
  final results = await searxngClient.search(
    query,
    maxResults: _kMaxSearchResults,
  );

  if (results.isEmpty) {
    stdout.writeln(
      '${AnsiCodes.yellow}'
      'Nenhum resultado encontrado para "$query".'
      '${AnsiCodes.reset}\n',
    );

    return const [];
  }

  stdout.writeln();

  for (var i = 0; i < results.length; i++) {
    final result = results[i];

    stdout.writeln(
      '${AnsiCodes.yellow}${AnsiCodes.bold}'
      '[${i + 1}]'
      '${AnsiCodes.reset} '
      '${AnsiCodes.white}${AnsiCodes.bold}'
      '${result.title}'
      '${AnsiCodes.reset}',
    );

    stdout.writeln(
      '    ${AnsiCodes.blue}'
      '${result.url}'
      '${AnsiCodes.reset}',
    );

    if (result.snippet.isNotEmpty) {
      stdout.writeln(
        '    ${AnsiCodes.gray}'
        '${_truncate(result.snippet, 200)}'
        '${AnsiCodes.reset}',
      );
    }

    stdout.writeln();
  }

  stdout.writeln(
    '${AnsiCodes.gray}'
    'Use /open <nº> para ler a página inteira.'
    '${AnsiCodes.reset}\n',
  );

  return results;
}

// ===========================================================================
// MODELO OFFLINE
// ===========================================================================

Future<void> _handleOfflineChat({
  required String query,
  required OllamaClient ollamaClient,
  required MarkdownRenderer renderer,
  required List<ChatMessage> history,
}) async {
  history.add(
    ChatMessage(
      role: 'user',
      content: query,
    ),
  );

  final buffer = StringBuffer();

  await for (final token in ollamaClient.chatStream(
    messages: history,
  )) {
    buffer.write(token);
  }

  final answer = buffer.toString();

  history.add(
    ChatMessage(
      role: 'assistant',
      content: answer,
    ),
  );

  stdout.writeln(
    renderer.render(answer),
  );

  stdout.writeln();
}

// ===========================================================================
// /open
// ===========================================================================

Future<void> _handleOpenCommand({
  required String input,
  required List<SearchResult> lastResults,
  required WebScraper scraper,
  required TerminalPager pager,
}) async {
  final argument = input
      .replaceFirst(
        RegExp(r'^/open\s*'),
        '',
      )
      .trim();

  if (argument.isEmpty) {
    stdout.writeln(
      '${AnsiCodes.yellow}'
      'Uso: /open <nº do resultado> ou /open <url>'
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
        '${AnsiCodes.yellow}'
        'Não há resultado nº $asNumber na última busca.'
        '${AnsiCodes.reset}\n',
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
      '${AnsiCodes.yellow}'
      'Argumento inválido. Use um número da última busca ou '
      'uma URL começando com http:// ou https://.'
      '${AnsiCodes.reset}\n',
    );
    return;
  }

  stdout.writeln(
    '${AnsiCodes.gray}'
    'Abrindo $targetUrl...'
    '${AnsiCodes.reset}',
  );

  final page = await scraper.scrapeOne(targetUrl);

  if (!page.success) {
    stdout.writeln(
      '${AnsiCodes.yellow}'
      'Não foi possível abrir a página: ${page.error}'
      '${AnsiCodes.reset}\n',
    );
    return;
  }

  pager.show(
    page.content,
    title: title,
  );
}

// ===========================================================================
// /models
// ===========================================================================

Future<void> _handleModelsCommand({
  required String ollamaUrl,
}) async {
  final manager = OllamaModelManager(
    baseUrl: ollamaUrl,
  );

  try {
    final models = await manager.listModels();

    if (models.isEmpty) {
      stdout.writeln(
        '${AnsiCodes.yellow}'
        'Nenhum modelo encontrado no Ollama.'
        '${AnsiCodes.reset}\n',
      );
      return;
    }

    stdout.writeln(
      '\n${AnsiCodes.cyan}${AnsiCodes.bold}'
      'Modelos disponíveis no Ollama:'
      '${AnsiCodes.reset}',
    );

    for (final model in models) {
      stdout.writeln(
        '  ${AnsiCodes.green}•${AnsiCodes.reset} $model',
      );
    }

    stdout.writeln();
  } catch (error) {
    stdout.writeln(
      '${AnsiCodes.yellow}'
      'Não foi possível consultar os modelos: $error'
      '${AnsiCodes.reset}\n',
    );
  }
}

// ===========================================================================
// HEALTH CHECK
// ===========================================================================

Future<bool> _runHealthCheck(
  SearxngClient searxngClient,
  OllamaClient ollamaClient,
) async {
  stdout.writeln(
    '${AnsiCodes.gray}'
    'Executando health check...'
    '${AnsiCodes.reset}',
  );

  bool searxngOk;

  try {
    await searxngClient.search(
      'ping',
      maxResults: 1,
    );

    searxngOk = true;
  } catch (_) {
    searxngOk = false;
  }

  final ollamaOk = await ollamaClient.healthCheck();

  _printServiceStatus(
    'SearXNG',
    _kSearxngUrl,
    searxngOk,
  );

  _printServiceStatus(
    'Ollama ($_kOllamaModel)',
    _kOllamaUrl,
    ollamaOk,
  );

  stdout.writeln();

  if (!searxngOk) {
    stdout.writeln(
      '${AnsiCodes.yellow}'
      'Aviso: sem SearXNG, os modos de pesquisa podem falhar. '
      'O Chat Offline continua disponível.'
      '${AnsiCodes.reset}\n',
    );
  }

  return searxngOk && ollamaOk;
}

void _printServiceStatus(
  String name,
  String url,
  bool healthy,
) {
  final icon = healthy
      ? '${AnsiCodes.green}✓${AnsiCodes.reset}'
      : '${AnsiCodes.yellow}✗${AnsiCodes.reset}';

  stdout.writeln(
    '  $icon $name '
    '${AnsiCodes.gray}($url)${AnsiCodes.reset}',
  );
}

// ===========================================================================
// INTERFACE
// ===========================================================================

void _printAsciiArt() {
  stdout.writeln(
    '${AnsiCodes.cyan}$_kAsciiArt${AnsiCodes.reset}',
  );
}

Future<AppMode> _promptModeSelection(
  AppMode current,
  bool searxngHealthy,
) async {
  stdout.writeln(
    '${AnsiCodes.cyan}${AnsiCodes.bold}'
    'Escolha o modo de operação:'
    '${AnsiCodes.reset}',
  );

  for (final mode in AppMode.values) {
    final marker =
        mode == current ? '${AnsiCodes.green}●' : '${AnsiCodes.gray}○';

    stdout.writeln(
      '  $marker${AnsiCodes.reset} '
      '${AnsiCodes.bold}${mode.menuIndex}. '
      '${mode.title}${AnsiCodes.reset}',
    );

    stdout.writeln(
      '     ${AnsiCodes.gray}'
      '${mode.description}'
      '${AnsiCodes.reset}',
    );
  }

  stdout.write(
    '${AnsiCodes.gray}'
    'Digite o número '
    '(ENTER mantém "${current.title}"): '
    '${AnsiCodes.reset}',
  );

  final input = stdin.readLineSync()?.trim();

  if (input == null || input.isEmpty) {
    return current;
  }

  final parsed = int.tryParse(input);

  final selected = parsed == null ? null : AppModeInfo.fromMenuIndex(parsed);

  if (selected == null) {
    stdout.writeln(
      '${AnsiCodes.yellow}'
      'Opção inválida, mantendo "${current.title}".'
      '${AnsiCodes.reset}',
    );

    return current;
  }

  return selected;
}

void _printModeBanner(AppMode mode) {
  stdout.writeln(
    '${AnsiCodes.green}${AnsiCodes.bold}'
    '✔ Modo ativo: ${mode.title}'
    '${AnsiCodes.reset}\n',
  );
}

void _printHelp() {
  stdout.writeln(
    '${AnsiCodes.gray}'
    'Digite sua pergunta ou use um dos comandos abaixo:'
    '${AnsiCodes.reset}',
  );

  stdout.writeln(
    '  ${AnsiCodes.yellow}? <pergunta>${AnsiCodes.reset}'
    '     — POP rápido: pesquisa sem IA',
  );

  stdout.writeln(
    '  ${AnsiCodes.yellow}/pop <pergunta>${AnsiCodes.reset}'
    ' — POP rápido',
  );

  stdout.writeln(
    '  ${AnsiCodes.yellow}/search <pergunta>${AnsiCodes.reset}'
    ' — pesquisa direta no SearXNG',
  );

  stdout.writeln(
    '  ${AnsiCodes.yellow}/ask <pergunta>${AnsiCodes.reset}'
    '    — pesquisa profunda + Chromium + Ollama',
  );

  stdout.writeln(
    '  ${AnsiCodes.yellow}/open <nº|url>${AnsiCodes.reset}'
    '   — lê uma página inteira',
  );

  stdout.writeln(
    '  ${AnsiCodes.yellow}/models${AnsiCodes.reset}'
    '           — lista modelos do Ollama',
  );

  stdout.writeln(
    '  ${AnsiCodes.yellow}/sources${AnsiCodes.reset}'
    '          — mostra as últimas fontes',
  );

  stdout.writeln(
    '  ${AnsiCodes.yellow}/health${AnsiCodes.reset}'
    '           — verifica SearXNG e Ollama',
  );

  stdout.writeln(
    '  ${AnsiCodes.yellow}/mode${AnsiCodes.reset}'
    '             — troca o modo de operação',
  );

  stdout.writeln(
    '  ${AnsiCodes.yellow}/history${AnsiCodes.reset}'
    '          — mostra o histórico',
  );

  stdout.writeln(
    '  ${AnsiCodes.yellow}/clear${AnsiCodes.reset}'
    '            — limpa a tela',
  );

  stdout.writeln(
    '  ${AnsiCodes.yellow}/help${AnsiCodes.reset}'
    '             — mostra esta ajuda',
  );

  stdout.writeln(
    '  ${AnsiCodes.yellow}/quit${AnsiCodes.reset}'
    '             — encerra o Levai Scout',
  );

  stdout.writeln();
}

void _printHistory(
  List<_HistoryEntry> history,
) {
  if (history.isEmpty) {
    stdout.writeln(
      '${AnsiCodes.gray}'
      'Nenhuma interação nesta sessão ainda.'
      '${AnsiCodes.reset}\n',
    );

    return;
  }

  stdout.writeln(
    '${AnsiCodes.cyan}${AnsiCodes.bold}'
    'Histórico da sessão:'
    '${AnsiCodes.reset}',
  );

  for (var i = 0; i < history.length; i++) {
    final entry = history[i];

    final time = '${entry.timestamp.hour.toString().padLeft(2, '0')}:'
        '${entry.timestamp.minute.toString().padLeft(2, '0')}';

    stdout.writeln(
      '  ${AnsiCodes.gray}'
      '[$time][${entry.mode.shortTag}]'
      '${AnsiCodes.reset} '
      '${AnsiCodes.bold}${i + 1}.${AnsiCodes.reset} '
      '${entry.query}',
    );
  }

  stdout.writeln();
}

void _printNumberedResultsHint(
  List<SearchResult> results,
) {
  if (results.isEmpty) {
    return;
  }

  stdout.writeln(
    '${AnsiCodes.gray}'
    'Fontes desta resposta '
    '(use /open <nº> para ler a página inteira):'
    '${AnsiCodes.reset}',
  );

  for (var i = 0; i < results.length; i++) {
    stdout.writeln(
      '  ${AnsiCodes.yellow}'
      '[${i + 1}]'
      '${AnsiCodes.reset} '
      '${AnsiCodes.gray}'
      '${results[i].url}'
      '${AnsiCodes.reset}',
    );
  }

  stdout.writeln();
}

// ===========================================================================
// UTILITÁRIOS
// ===========================================================================

String _truncate(
  String text,
  int maxChars,
) {
  if (text.length <= maxChars) {
    return text;
  }

  return '${text.substring(0, maxChars)}\n[...conteúdo truncado...]';
}

void _clearScreen() {
  if (Platform.isWindows) {
    stdout.write('\x1B[2J\x1B[0f');
  } else {
    stdout.write('\x1B[2J\x1B[H');
  }
}
