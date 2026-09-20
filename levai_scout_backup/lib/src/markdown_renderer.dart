/// Renderizador ANSI básico para exibir Markdown formatado
/// diretamente no terminal (títulos, negrito, itálico, blocos de
/// código e listas).
///
/// Não depende de um parser completo de Markdown (AST); trabalha
/// linha a linha e com expressões regulares, o que é suficiente para
/// formatar as respostas geradas pelo LLM local em tempo real.
library levai_scout.markdown_renderer;

/// Códigos de escape ANSI utilizados pelo renderizador.
class AnsiCodes {
  static const String reset = '\x1B[0m';
  static const String bold = '\x1B[1m';
  static const String dim = '\x1B[2m';
  static const String italic = '\x1B[3m';
  static const String underline = '\x1B[4m';

  static const String cyan = '\x1B[36m';
  static const String green = '\x1B[32m';
  static const String yellow = '\x1B[33m';
  static const String magenta = '\x1B[35m';
  static const String blue = '\x1B[34m';
  static const String gray = '\x1B[90m';
  static const String white = '\x1B[97m';
}

/// Converte um bloco de texto em Markdown simples para uma string
/// já formatada com códigos ANSI, pronta para ser impressa no
/// terminal.
class MarkdownRenderer {
  static final RegExp _boldPattern = RegExp(r'\*\*(.+?)\*\*');
  static final RegExp _italicPattern = RegExp(r'(?<!\*)\*(?!\*)(.+?)\*(?!\*)');
  static final RegExp _inlineCodePattern = RegExp(r'`([^`]+)`');
  static final RegExp _headingPattern = RegExp(r'^(#{1,6})\s+(.*)$');
  static final RegExp _bulletPattern = RegExp(r'^(\s*)[-*]\s+(.*)$');
  static final RegExp _numberedPattern = RegExp(r'^(\s*)(\d+)\.\s+(.*)$');
  static final RegExp _codeFencePattern = RegExp(r'^```(\w*)\s*$');

  /// Renderiza um texto Markdown completo (potencialmente multi-linha)
  /// retornando a versão formatada com ANSI.
  String render(String markdown) {
    final buffer = StringBuffer();
    final lines = markdown.split('\n');

    bool insideCodeBlock = false;

    for (final rawLine in lines) {
      final codeFenceMatch = _codeFencePattern.firstMatch(rawLine);
      if (codeFenceMatch != null) {
        insideCodeBlock = !insideCodeBlock;
        buffer.writeln(
          '${AnsiCodes.gray}${'─' * 40}${AnsiCodes.reset}',
        );
        continue;
      }

      if (insideCodeBlock) {
        buffer.writeln('${AnsiCodes.green}$rawLine${AnsiCodes.reset}');
        continue;
      }

      buffer.writeln(_renderLine(rawLine));
    }

    return buffer.toString().trimRight();
  }

  String _renderLine(String line) {
    final headingMatch = _headingPattern.firstMatch(line);
    if (headingMatch != null) {
      final level = headingMatch.group(1)!.length;
      final text = headingMatch.group(2)!;
      final color = level == 1 ? AnsiCodes.cyan : AnsiCodes.blue;
      return '$color${AnsiCodes.bold}${_applyInline(text)}${AnsiCodes.reset}';
    }

    final bulletMatch = _bulletPattern.firstMatch(line);
    if (bulletMatch != null) {
      final indent = bulletMatch.group(1)!;
      final text = bulletMatch.group(2)!;
      return '$indent${AnsiCodes.yellow}•${AnsiCodes.reset} '
          '${_applyInline(text)}';
    }

    final numberedMatch = _numberedPattern.firstMatch(line);
    if (numberedMatch != null) {
      final indent = numberedMatch.group(1)!;
      final number = numberedMatch.group(2)!;
      final text = numberedMatch.group(3)!;
      return '$indent${AnsiCodes.yellow}$number.${AnsiCodes.reset} '
          '${_applyInline(text)}';
    }

    return _applyInline(line);
  }

  /// Aplica formatação inline (negrito, itálico, código) em uma
  /// única linha de texto, preservando o restante do conteúdo.
  String _applyInline(String text) {
    var result = text;

    result = result.replaceAllMapped(_inlineCodePattern, (match) {
      return '${AnsiCodes.magenta}${match.group(1)}${AnsiCodes.reset}';
    });

    result = result.replaceAllMapped(_boldPattern, (match) {
      return '${AnsiCodes.bold}${AnsiCodes.white}'
          '${match.group(1)}${AnsiCodes.reset}';
    });

    result = result.replaceAllMapped(_italicPattern, (match) {
      return '${AnsiCodes.italic}${match.group(1)}${AnsiCodes.reset}';
    });

    return result;
  }
}
