class PopEngine {
  static PopQuery analyze(String input) {
    var query = input.trim();

    if (query.startsWith('?')) {
      query = query.substring(1).trim();
    }

    final words =
        query.split(RegExp(r'\s+')).where((word) => word.isNotEmpty).toList();

    final programming = RegExp(
      r'\b(c\+\+|cpp|dart|flutter|lua|python|git|github|linux|api|sql|'
      r'programming|programação|code|codigo|código|function|class|'
      r'algorithm|algoritmo|database|framework)\b',
      caseSensitive: false,
    ).hasMatch(query);

    return PopQuery(
      original: query,
      keywords: words,
      programming: programming,
    );
  }

  static List<String> generateSearchQueries(String input) {
    final result = analyze(input);

    final queries = <String>[
      result.original,
    ];

    if (result.programming) {
      queries.add('${result.original} documentation');
      queries.add('${result.original} examples');
      queries.add('${result.original} tutorial');
    } else {
      queries.add('${result.original} explained');
      queries.add('${result.original} guide');
    }

    return queries.toSet().toList();
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
