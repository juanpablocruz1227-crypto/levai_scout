import 'package:puppeteer/puppeteer.dart';

class WebScraper {
  final int navigationTimeout;
  final int retries;

  WebScraper({
    this.navigationTimeout = 60000,
    this.retries = 2,
  });

  Future<String?> scrape(String url) async {
    Browser? browser;

    try {
      browser = await puppeteer.launch(
        headless: true,
      );

      final page = await browser.newPage();

      await page.setUserAgent(
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
        'AppleWebKit/537.36 (KHTML, like Gecko) '
        'Chrome/131.0.0.0 Safari/537.36',
      );

      String? result;

      for (var attempt = 1; attempt <= retries + 1; attempt++) {
        try {
          await page.goto(
            url,
            wait: Until.domContentLoaded,
            timeout: navigationTimeout,
          );

          result = await page.evaluate<String>(
            '''() {
              const selectors = [
                'main',
                'article',
                '[role="main"]',
                '.content',
                '.markdown-body',
                'body'
              ];

              for (const selector of selectors) {
                const element = document.querySelector(selector);

                if (element && element.innerText.trim().length > 100) {
                  return element.innerText;
                }
              }

              return document.body?.innerText ?? '';
            }''',
          );

          if (result != null && result!.trim().isNotEmpty) {
            return result!.trim();
          }
        } catch (_) {
          if (attempt >= retries + 1) {
            return null;
          }

          await Future<void>.delayed(
            Duration(seconds: attempt * 2),
          );
        }
      }

      return result?.trim();
    } finally {
      await browser?.close();
    }
  }

  Future<void> close() async {}
}
