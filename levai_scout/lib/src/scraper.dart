/// Raspagem web assíncrona e concorrente usando Chromium headless
/// via `package:puppeteer`.
///
/// O [WebScraper] abre um único navegador Chromium e distribui as
/// URLs recebidas entre no máximo [WebScraper.maxConcurrency] abas
/// simultâneas, controlando o acesso através de um semáforo manual
/// implementado com [Completer].
library levai_scout.scraper;

import 'dart:async';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:meta/meta.dart';
import 'package:puppeteer/puppeteer.dart' as pptr;

/// Tags HTML consideradas ruído para fins de extração de conteúdo
/// textual (menus, scripts, estilos, propaganda estrutural, etc).
const List<String> _kIgnoredTags = [
  'script',
  'style',
  'nav',
  'header',
  'footer',
  'iframe',
  'noscript',
  'svg',
  'form',
  'aside',
];

/// Resultado da raspagem de uma única página.
@immutable
class ScrapedPage {
  /// URL originalmente solicitada.
  final String url;

  /// Texto limpo e consolidado extraído da página. Vazio em caso de
  /// falha (ver [success] e [error]).
  final String content;

  /// Indica se a raspagem foi concluída com sucesso.
  final bool success;

  /// Mensagem de erro, presente apenas quando [success] é `false`.
  final String? error;

  const ScrapedPage({
    required this.url,
    required this.content,
    required this.success,
    this.error,
  });

  factory ScrapedPage.failure(String url, Object error) => ScrapedPage(
        url: url,
        content: '',
        success: false,
        error: error.toString(),
      );

  @override
  String toString() =>
      'ScrapedPage(url: $url, success: $success, chars: ${content.length})';
}

/// Semáforo simples baseado em [Completer], usado para limitar o
/// número de tarefas assíncronas concorrentes.
class _ConcurrencyPool {
  final int maxConcurrency;
  int _active = 0;
  final List<Completer<void>> _waiters = [];

  _ConcurrencyPool(this.maxConcurrency);

  /// Aguarda até que haja uma "vaga" livre no pool.
  Future<void> acquire() async {
    if (_active < maxConcurrency) {
      _active++;
      return;
    }
    final completer = Completer<void>();
    _waiters.add(completer);
    await completer.future;
    _active++;
  }

  /// Libera uma vaga, acordando o próximo aguardando na fila (FIFO).
  void release() {
    _active--;
    if (_waiters.isNotEmpty) {
      final next = _waiters.removeAt(0);
      next.complete();
    }
  }
}

/// Raspador web baseado em Chromium headless (via puppeteer), com
/// pool de concorrência limitado para evitar sobrecarregar a máquina
/// local ao processar múltiplos resultados de busca ao mesmo tempo.
class WebScraper {
  /// Número máximo de páginas abertas simultaneamente.
  final int maxConcurrency;

  /// Tempo máximo de espera pelo carregamento de cada página.
  final Duration navigationTimeout;

  pptr.Browser? _browser;
  late final _ConcurrencyPool _pool = _ConcurrencyPool(maxConcurrency);

  WebScraper({
    this.maxConcurrency = 3,
    this.navigationTimeout = const Duration(seconds: 20),
  });

  /// Inicializa o Chromium headless. Deve ser chamado uma única vez
  /// antes de [scrapeAll] ou [scrapeOne].
  Future<void> init() async {
    if (_browser != null) return;
    _browser = await pptr.puppeteer.launch(
      headless: true,
      args: const [
        '--no-sandbox',
        '--disable-setuid-sandbox',
        '--disable-dev-shm-usage',
        '--disable-gpu',
      ],
    );
  }

  /// Raspa uma lista de URLs respeitando o limite de concorrência de
  /// [maxConcurrency] páginas simultâneas. A ordem do resultado
  /// corresponde à ordem de [urls].
  Future<List<ScrapedPage>> scrapeAll(List<String> urls) async {
    _ensureInitialized();
    final futures = urls.map(scrapeOne).toList(growable: false);
    return Future.wait(futures);
  }

  /// Raspa uma única URL, aguardando uma vaga no pool de concorrência
  /// caso o limite já tenha sido atingido.
  Future<ScrapedPage> scrapeOne(String url) async {
    _ensureInitialized();
    await _pool.acquire();
    pptr.Page? page;
    try {
      page = await _browser!.newPage();
      await page.setUserAgent(
        'Mozilla/5.0 (X11; Linux x86_64) LevaiScout/1.0 (+local-research-bot)',
      );
      await page.goto(
        url,
        wait: pptr.Until.networkIdle,
        timeout: navigationTimeout,
      );
      final rawHtml = await page.content ?? '';
      final cleaned = _extractCleanText(rawHtml);
      return ScrapedPage(url: url, content: cleaned, success: true);
    } catch (e) {
      return ScrapedPage.failure(url, e);
    } finally {
      await page?.close();
      _pool.release();
    }
  }

  /// Remove tags irrelevantes do HTML bruto e retorna apenas o texto
  /// visível consolidado, com linhas em branco e espaços redundantes
  /// removidos.
  String _extractCleanText(String rawHtml) {
    final dom.Document document = html_parser.parse(rawHtml);

    for (final tagName in _kIgnoredTags) {
      final elements = document.querySelectorAll(tagName);
      for (final element in elements) {
        element.remove();
      }
    }

    final bodyText = document.body?.text ?? '';

    final lines = bodyText
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty);

    return lines.join('\n');
  }

  void _ensureInitialized() {
    if (_browser == null) {
      throw StateError(
        'WebScraper não inicializado. Chame init() antes de raspar páginas.',
      );
    }
  }

  /// Encerra o navegador Chromium e libera todos os recursos.
  Future<void> dispose() async {
    await _browser?.close();
    _browser = null;
  }
}
