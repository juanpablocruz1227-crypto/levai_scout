# Levai Scout

Chatbot de pesquisa avançada, local e gratuito, escrito em Dart puro.
Alternativa 100% offline ao Google Search: combina **SearXNG** (busca),
**Chromium headless via puppeteer** (scraping) e **Qwen2.5-Coder via
Ollama** (síntese com LLM local) para responder perguntas citando as
fontes consultadas.

## Pré-requisitos

1. **Dart SDK** >= 3.3.0
2. **Ollama** instalado e rodando (`ollama serve`), com o modelo baixado:
   ```bash
   ollama pull qwen2.5-coder
   ```
3. **SearXNG** rodando localmente (porta padrão `8080`), por exemplo via
   Docker:
   ```bash
   docker run -d --name searxng -p 8080:8080 searxng/searxng
   ```
   > Garanta que `search.formats` inclua `json` no `settings.yml` do
   > SearXNG — por padrão esse formato vem desabilitado por segurança.
4. **Chromium/Chrome**: o `puppeteer` baixa uma versão compatível
   automaticamente na primeira execução (requer conexão à internet
   apenas nesse passo único de instalação).

## Instalação

```bash
dart pub get
```

## Execução

```bash
dart run bin/main.dart
```

## Modos de operação

O Levai Scout tem três modos, escolhidos no início (e trocáveis a
qualquer momento com `/mode`):

| Modo | O que faz |
|------|-----------|
| **IA Avançada** | Gera 2-3 sub-buscas automáticas sobre o tema, busca todas no SearXNG, lê as páginas mais relevantes com o Chromium e sintetiza uma única resposta, com fontes e "Perguntas relacionadas" ao final — no espírito de um "Modo IA" de busca, porém 100% local. |
| **Busca Direta (sem IA)** | Só busca no SearXNG e lista título/URL/resumo de cada resultado, sem chamar o LLM. Mais rápido e determinístico. |
| **Chat Offline** | Conversa direto com o Qwen2.5-Coder local, sem buscar nada na web. Mantém o histórico da conversa em memória. Funciona mesmo com o SearXNG fora do ar. |

## Comandos disponíveis no loop interativo

| Comando            | Ação                                                             |
|---------------------|-------------------------------------------------------------------|
| `/mode`             | Abre o menu para trocar de modo de operação                      |
| `/open <nº\|url>`   | Lê uma página inteira (da última busca ou por URL), paginado no terminal |
| `/history`          | Mostra o histórico de perguntas da sessão, com o modo usado em cada uma |
| `/clear`            | Limpa a tela do terminal                                          |
| `/help`             | Mostra a ajuda                                                    |
| `/quit`             | Encerra o Levai Scout                                             |

Qualquer outro texto digitado é tratado como pergunta/pesquisa, de
acordo com o modo ativo. O comando `/open` funciona como um mini
navegador de terminal: abre a página com o Chromium headless, limpa
o HTML e exibe o texto paginado (ENTER para avançar, "q" para sair).

## Arquitetura

```
lib/src/search_engine.dart     -> SearxngClient + SearchResult
lib/src/scraper.dart           -> WebScraper (Chromium headless, pool de 3)
lib/src/ollama_client.dart     -> OllamaClient (Modo IA, Modo Offline, sub-buscas)
lib/src/app_mode.dart          -> enum AppMode (IA / Busca Direta / Offline)
lib/src/pager.dart             -> TerminalPager (leitura paginada de páginas)
lib/src/markdown_renderer.dart -> Renderizador ANSI de Markdown
bin/main.dart                  -> CLI interativa + health check + menu de modos
```

## Configuração

Os endpoints e parâmetros (URL do SearXNG, URL/modelo do Ollama,
concorrência do scraper, número de resultados) estão centralizados em
constantes no topo de `bin/main.dart`.
