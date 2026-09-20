class CommandRouter {
  bool isCommand(String input) => input.trim().startsWith('/');

  Command parse(String input) {
    final value = input.trim();

    if (!value.startsWith('/')) {
      return Command(CommandType.query, value);
    }

    final parts = value.substring(1).split(RegExp(r'\s+'));
    final name = parts.isEmpty ? '' : parts.first.toLowerCase();
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

      case 'help':
        return Command(CommandType.help, argument);

      case 'clear':
        return Command(CommandType.clear, argument);

      case 'history':
        return Command(CommandType.history, argument);

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
  help,
  clear,
  history,
  quit,
  unknown,
}

class Command {
  final CommandType type;
  final String argument;

  const Command(this.type, this.argument);
}
