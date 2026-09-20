import 'package:levai_scout/src/pop/pop_engine.dart';
import 'package:test/test.dart';

void main() {
  group('POP Engine', () {
    test('remove ? da pesquisa', () {
      final result = PopEngine.analyze(
        '? std::vector C++',
      );

      expect(
        result.original,
        'std::vector C++',
      );

      expect(result.programming, isTrue);
    });

    test('gera pesquisas de documentação', () {
      final result = PopEngine.generateSearchQueries(
        'std::vector C++',
      );

      expect(result.length, 3);
      expect(
        result.any(
          (query) => query.contains('documentation'),
        ),
        isTrue,
      );
    });
  });
}
