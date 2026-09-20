/// Paginador de terminal ("pager") simples, no estilo `less`/`more`,
/// usado para exibir textos longos (páginas web lidas na íntegra,
/// respostas extensas) em blocos, sem estourar o buffer do terminal.
library levai_scout.pager;

import 'dart:io';

import 'markdown_renderer.dart';

/// Exibe texto em páginas, aguardando ENTER para avançar e aceitando
/// 'q' para interromper a exibição a qualquer momento.
class TerminalPager {
  /// Quantas linhas são exibidas por página.
  final int linesPerPage;

  TerminalPager({int? linesPerPage})
      : linesPerPage = linesPerPage ?? _detectTerminalHeight();

  static int _detectTerminalHeight() {
    try {
      final height = stdout.terminalLines;
      if (height > 6) return height - 6;
    } catch (_) {
      // Terminal não suporta detecção de tamanho (ex: redirecionado
      // para um arquivo); usa um valor padrão razoável.
    }
    return 30;
  }

  /// Exibe [text] paginado. Se [title] for informado, é impresso em
  /// destaque antes do conteúdo.
  void show(String text, {String? title}) {
    final lines = text.split('\n');
    final total = lines.length;

    if (total == 0) {
      stdout.writeln(
        '${AnsiCodes.gray}(nenhum conteúdo para exibir)${AnsiCodes.reset}\n',
      );
      return;
    }

    final totalPages = (total / linesPerPage).ceil().clamp(1, 1 << 30);

    if (title != null && title.isNotEmpty) {
      stdout.writeln(
        '${AnsiCodes.cyan}${AnsiCodes.bold}$title${AnsiCodes.reset}\n',
      );
    }

    var index = 0;
    var pageNumber = 1;

    while (index < total) {
      final end = (index + linesPerPage).clamp(0, total);
      for (var i = index; i < end; i++) {
        stdout.writeln(lines[i]);
      }
      index = end;

      if (index >= total) break;

      stdout.write(
        '${AnsiCodes.gray}-- página $pageNumber/$totalPages | ENTER '
        'para continuar, "q" + ENTER para sair --${AnsiCodes.reset} ',
      );
      final input = stdin.readLineSync()?.trim().toLowerCase();
      if (input == 'q') {
        stdout.writeln();
        return;
      }
      pageNumber++;
    }

    stdout.writeln();
  }
}
