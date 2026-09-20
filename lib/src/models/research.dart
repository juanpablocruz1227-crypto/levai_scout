class ResearchSession {
  final String question;
  final List<String> queries;
  final List<ResearchSource> sources;

  ResearchSession({
    required this.question,
    this.queries = const [],
    this.sources = const [],
  });
}

class ResearchSource {
  final String title;
  final String url;
  final String? content;

  const ResearchSource({
    required this.title,
    required this.url,
    this.content,
  });
}
