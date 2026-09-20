class DevMode {
  static const languages = [
    'cpp',
    'c++',
    'dart',
    'flutter',
    'lua',
    'python',
    'rust',
    'java',
  ];

  static String detectLanguage(String input) {
    final value = input.toLowerCase();

    if (value.contains('c++') || value.contains('cpp')) {
      return 'C++';
    }

    if (value.contains('flutter')) {
      return 'Flutter';
    }

    if (value.contains('dart')) {
      return 'Dart';
    }

    if (value.contains('lua')) {
      return 'Lua';
    }

    if (value.contains('python')) {
      return 'Python';
    }

    if (value.contains('rust')) {
      return 'Rust';
    }

    if (value.contains('java')) {
      return 'Java';
    }

    return 'Geral';
  }

  static List<String> queries(String input) {
    final language = detectLanguage(input);

    final result = <String>[
      input,
      '$input documentation',
      '$input examples',
    ];

    if (language != 'Geral') {
      result.add('$input $language official documentation');
      result.add('$input $language examples');
    }

    return result.toSet().toList();
  }
}
