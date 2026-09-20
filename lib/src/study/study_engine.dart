class StudyEngine {
  String summaryPrompt(String topic, String material) {
    return '''
Você é o modo de estudo do Levai Scout.

Tema:
$topic

Material pesquisado:
$material

Crie uma explicação clara e progressiva.

Estrutura:

1. O que é
2. Ideia principal
3. Como funciona
4. Exemplo
5. Erros comuns
6. O que pesquisar depois
7. Perguntas para testar compreensão

Não invente informações que não estejam apoiadas pelo material.
''';
  }

  String quizPrompt(String topic, String material) {
    return '''
Crie um quiz sobre "$topic" usando somente o material abaixo.

Material:
$material

Crie 5 perguntas.
Depois coloque as respostas separadamente.
Comece do básico e aumente gradualmente a dificuldade.
''';
  }

  String flashcardPrompt(String topic, String material) {
    return '''
Crie flashcards para estudar "$topic".

Material:
$material

Formato:

CARD 1
Pergunta:
Resposta:

CARD 2
Pergunta:
Resposta:

Crie 10 cards curtos e objetivos.
''';
  }
}
