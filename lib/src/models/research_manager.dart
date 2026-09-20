import 'package:levai_scout/src/models/research.dart';

class ResearchManager {
  ResearchSession? current;

  void start(String question, List<String> queries) {
    current = ResearchSession(
      question: question,
      queries: queries,
    );
  }

  void addSource(ResearchSource source) {
    final session = current;

    if (session == null) {
      return;
    }

    final alreadyExists = session.sources.any(
      (item) => item.url == source.url,
    );

    if (alreadyExists) {
      return;
    }

    current = ResearchSession(
      question: session.question,
      queries: session.queries,
      sources: [
        ...session.sources,
        source,
      ],
    );
  }

  List<ResearchSource> get sources {
    return current?.sources ?? const [];
  }

  String get question {
    return current?.question ?? '';
  }

  void clear() {
    current = null;
  }
}
