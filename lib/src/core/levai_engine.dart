import 'package:levai_scout/src/core/config.dart';
import 'package:levai_scout/src/ollama/model_manager.dart';
import 'package:levai_scout/src/ollama_client.dart';
import 'package:levai_scout/src/pop/pop_engine.dart';
import 'package:levai_scout/src/search_engine.dart';
import 'package:levai_scout/src/study/study_engine.dart';

class LevaiEngine {
  final LevaiConfig config;
  final SearxngClient search;
  final OllamaClient ollama;
  final OllamaModelManager models;
  final StudyEngine study;

  LevaiEngine({
    this.config = const LevaiConfig(),
  })  : search = SearxngClient(baseUrl: config.searxngUrl),
        ollama = OllamaClient(
          baseUrl: config.ollamaUrl,
          model: config.model,
          contextWindow: config.contextWindow,
          temperature: config.temperature,
        ),
        models = OllamaModelManager(baseUrl: config.ollamaUrl),
        study = StudyEngine();

  PopQuery analyzeResearch(String input) {
    return PopEngine.analyze(input);
  }

  List<String> generateResearchQueries(String input) {
    return PopEngine.generateSearchQueries(input);
  }

  Future<List<String>> availableModels() {
    return models.listModels();
  }

  Future<bool> ollamaAvailable() {
    return models.isAvailable();
  }

  String createStudyPrompt(
    String topic,
    String material,
  ) {
    return study.summaryPrompt(topic, material);
  }

  String createQuizPrompt(
    String topic,
    String material,
  ) {
    return study.quizPrompt(topic, material);
  }

  String createFlashcardPrompt(
    String topic,
    String material,
  ) {
    return study.flashcardPrompt(topic, material);
  }
}
