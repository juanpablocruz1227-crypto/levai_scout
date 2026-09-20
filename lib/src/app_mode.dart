/// Modos de operação do Levai Scout.
///
/// Cada modo altera o comportamento do loop principal: quais serviços
/// são consultados (SearXNG, Chromium, Ollama) e como a resposta é
/// apresentada ao usuário.
library levai_scout.app_mode;

/// Os quatro modos de operação suportados pelo Levai Scout.
enum AppMode {
  /// Busca na web + scraping + síntese avançada com o LLM local,
  /// incluindo múltiplas sub-buscas e perguntas relacionadas — uma
  /// versão local e mais aberta do "Modo IA" de motores de busca.
  aiMode,

  /// Apenas busca e lista os resultados (título, URL, resumo), sem
  /// usar o LLM. Mais rápido e 100% determinístico.
  noAiMode,

  /// Conversa direta com o LLM local, sem buscar nada na web. Útil
  /// quando o SearXNG está fora do ar ou sem internet disponível.
  offlineMode,
}

/// Informações de exibição associadas a cada [AppMode].
extension AppModeInfo on AppMode {
  /// Nome curto exibido no prompt do terminal, ex: "[IA]".
  String get shortTag {
    switch (this) {
      case AppMode.aiMode:
        return 'IA';
      case AppMode.noAiMode:
        return 'BUSCA';
      case AppMode.offlineMode:
        return 'OFFLINE';
    }
  }

  /// Título completo do modo, usado no menu de seleção.
  String get title {
    switch (this) {
      case AppMode.aiMode:
        return 'IA Avançada (busca + leitura + síntese)';
      case AppMode.noAiMode:
        return 'Busca Direta (sem IA)';
      case AppMode.offlineMode:
        return 'Chat Offline (sem busca na web)';
    }
  }

  /// Descrição de uma linha do que o modo faz.
  String get description {
    switch (this) {
      case AppMode.aiMode:
        return 'Gera sub-buscas automáticas, lê as páginas mais '
            'relevantes com o Chromium e sintetiza uma resposta '
            'única com fontes e perguntas relacionadas.';
      case AppMode.noAiMode:
        return 'Mostra a lista de resultados da busca sem chamar o '
            'LLM. Use /open <nº> para ler uma página inteira.';
      case AppMode.offlineMode:
        return 'Conversa direto com o modelo local, sem internet. '
            'Mantém o histórico da conversa em memória.';
    }
  }

  /// Índice de exibição no menu (1-based).
  int get menuIndex => AppMode.values.indexOf(this) + 1;

  /// Resolve um [AppMode] a partir do índice digitado pelo usuário
  /// no menu (1-based). Retorna `null` se inválido.
  static AppMode? fromMenuIndex(int index) {
    if (index < 1 || index > AppMode.values.length) return null;
    return AppMode.values[index - 1];
  }
}
