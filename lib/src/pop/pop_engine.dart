class PopEngine {
  static PopQuery analyze(String input) {
    var query = input.trim();

    if (query.startsWith('?')) {
      query = query.substring(1).trim();
    }

    final programming = RegExp(
      r'\b(c\+\+|cpp|dart|flutter|lua|python|rust|java|'
      r'git|github|linux|api|sql|programming|programação|'
      r'code|codigo|código|function|função|class|classe|'
      r'algorithm|algoritmo|database|banco|framework|'
      r'compiler|compilador|lexer|parser|pointer|ponteiro|'
      r'vector|array|memory|memória)\b',
      caseSensitive: false,
    ).hasMatch(query);

    final keywords =
        query.split(RegExp(r'\s+')).where((word) => word.isNotEmpty).toList();

    return PopQuery(
      original: query,
      keywords: keywords,
      programming: programming,
    );
  }

  static List<String> generateSearchQueries(
    String input, {
    int maxQueries = 3,
  }) {
    final result = analyze(input);

    if (result.original.isEmpty) {
      return const [];
    }

    final queries = <String>[
      result.original,
    ];

    if (result.programming) {
      queries.add('${result.original} documentation');
      queries.add('${result.original} examples');
    } else {
      queries.add('${result.original} explained');
      queries.add('${result.original} guide');
    }

    return queries.take(maxQueries).toList();
  }
}

class PopQuery {
  final String original;
  final List<String> keywords;
  final bool programming;

  const PopQuery({
    required this.original,
    required this.keywords,
    required this.programming,
  });
}
