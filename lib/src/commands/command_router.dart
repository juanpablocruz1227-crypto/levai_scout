class CommandRouter {
  bool isCommand(String input) {
    final value = input.trim();
    return value.startsWith('/') || value.startsWith('?');
  }

  Command parse(String input) {
    final value = input.trim();

    if (value.isEmpty) {
      return const Command(CommandType.unknown, '');
    }

    if (value.startsWith('?')) {
      return Command(
        CommandType.pop,
        value.substring(1).trim(),
      );
    }

    if (!value.startsWith('/')) {
      return Command(
        CommandType.query,
        value,
      );
    }

    final commandLine = value.substring(1).trim();

    if (commandLine.isEmpty) {
      return const Command(CommandType.unknown, '');
    }

    final parts = commandLine
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();

    final name = parts.first.toLowerCase();
    final argument = parts.length > 1 ? parts.sublist(1).join(' ') : '';

    switch (name) {
      case 'search':
        return Command(CommandType.search, argument);
      case 'ask':
        return Command(CommandType.ask, argument);
      case 'pop':
        return Command(CommandType.pop, argument);
      case 'study':
        return Command(CommandType.study, argument);
      case 'summary':
        return Command(CommandType.summary, argument);
      case 'quiz':
        return Command(CommandType.quiz, argument);
      case 'flashcards':
      case 'flashcard':
        return Command(CommandType.flashcards, argument);
      case 'models':
        return Command(CommandType.models, argument);
      case 'model':
        return Command(CommandType.model, argument);
      case 'sources':
        return Command(CommandType.sources, argument);
      case 'health':
        return Command(CommandType.health, argument);
      case 'history':
        return Command(CommandType.history, argument);
      case 'help':
        return Command(CommandType.help, argument);
      case 'clear':
        return Command(CommandType.clear, argument);
      case 'open':
        return Command(CommandType.open, argument);
      case 'mode':
      case 'modes':
        return Command(CommandType.mode, argument);
      case 'quit':
      case 'exit':
        return Command(CommandType.quit, argument);
      default:
        return Command(CommandType.unknown, argument);
    }
  }
}

enum CommandType {
  query,
  search,
  ask,
  pop,
  study,
  summary,
  quiz,
  flashcards,
  models,
  model,
  sources,
  health,
  history,
  help,
  clear,
  open,
  mode,
  quit,
  unknown,
}

class Command {
  final CommandType type;
  final String argument;

  const Command(this.type, this.argument);
}
