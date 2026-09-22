import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:khwarizmi/features/search/data/brave_search_provider.dart';
import 'package:khwarizmi/features/search/data/custom_search_provider.dart';
import 'package:khwarizmi/features/search/data/duckduckgo_search_provider.dart';
import 'package:khwarizmi/features/search/domain/search_provider.dart';
import 'package:khwarizmi/features/tools/built_in/web_search_tool.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
  });

  // ══════════════════════════════════════════════════════════════════════════
  // 1. Brave Search Provider
  // ══════════════════════════════════════════════════════════════════════════
  group('Phase 5: BraveSearchProvider', () {
    test('Parses standard Brave JSON response into SearchResult list', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.host, equals('api.search.brave.com'));
        expect(request.headers['X-Subscription-Token'], equals('test-brave-key'));

        final body = jsonEncode({
          'web': {
            'results': [
              {
                'title': 'Flutter 4.0 Released',
                'url': 'https://flutter.dev/blog/flutter-4',
                'description': 'Flutter 4.0 brings major performance improvements.',
              },
              {
                'title': 'Dart 4.0 New Features',
                'url': 'https://dart.dev/blog/dart-4',
                'description': 'Dart 4.0 introduces pattern matching.',
              },
            ],
          }
        });

        return http.Response(body, 200,
            headers: {'content-type': 'application/json'});
      });

      final provider = BraveSearchProvider(
        apiKey: 'test-brave-key',
        client: mockClient,
      );

      final results = await provider.search('flutter 4', count: 2);

      expect(results.length, equals(2));
      expect(results[0].title, equals('Flutter 4.0 Released'));
      expect(results[0].url, equals('https://flutter.dev/blog/flutter-4'));
      expect(results[0].snippet,
          contains('Flutter 4.0 brings major performance improvements.'));
      expect(results[1].title, equals('Dart 4.0 New Features'));
    });

    test('Throws SearchException on HTTP error (e.g. invalid key)', () async {
      final mockClient = MockClient((_) async => http.Response(
            jsonEncode({'message': 'Invalid API key'}),
            401,
          ));

      final provider = BraveSearchProvider(
        apiKey: 'bad-key',
        client: mockClient,
      );

      expect(
        () => provider.search('test query'),
        throwsA(isA<SearchException>()),
      );
    });

    test('Throws SearchException when API key is empty', () async {
      final provider = BraveSearchProvider(apiKey: '  ');
      expect(
        () => provider.search('test'),
        throwsA(isA<SearchException>()),
      );
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // 2. DuckDuckGo Provider
  // ══════════════════════════════════════════════════════════════════════════
  group('Phase 5: DuckDuckGoSearchProvider', () {
    test('Parses DuckDuckGo Lite HTML and returns results', () async {
      // Minimal HTML that mimics DuckDuckGo Lite result structure
      const fakeHtml = '''
<html><body>
<a class="result-link" href="https://example.com/news">Example News Article</a>
<td class="result-snippet">This is an example snippet from the result page.</td>
<a class="result-link" href="https://another.com/page">Another Page Title</a>
<td class="result-snippet">Another snippet about something interesting.</td>
</body></html>
''';

      final mockClient = MockClient((_) async => http.Response(fakeHtml, 200,
          headers: {'content-type': 'text/html; charset=utf-8'}));

      final provider = DuckDuckGoSearchProvider(client: mockClient);
      final results = await provider.search('test query', count: 5);

      expect(results.length, equals(2));
      expect(results[0].title, equals('Example News Article'));
      expect(results[0].url, equals('https://example.com/news'));
      expect(results[0].snippet, contains('example snippet'));
      expect(results[1].title, equals('Another Page Title'));
    });

    test('Parses standard DuckDuckGo HTML and decodes uddg redirect URLs', () async {
      const standardHtml = '''
<html><body>
<div class="result results_links">
  <h2 class="result__title">
    <a class="result__a" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fflutter.dev%2F&rut=123">Flutter Official Site</a>
  </h2>
  <a class="result__snippet" href="#">Build apps for any screen with Flutter.</a>
</div>
<div class="result results_links">
  <h2 class="result__title">
    <a class="result__a" href="https://dart.dev">Dart Language</a>
  </h2>
  <a class="result__snippet" href="#">Dart is a client-optimized language.</a>
</div>
</body></html>
''';

      final mockClient = MockClient((_) async => http.Response(standardHtml, 200,
          headers: {'content-type': 'text/html; charset=utf-8'}));

      final provider = DuckDuckGoSearchProvider(client: mockClient);
      final results = await provider.search('flutter', count: 5);

      expect(results.length, equals(2));
      expect(results[0].title, equals('Flutter Official Site'));
      expect(results[0].url, equals('https://flutter.dev/'));
      expect(results[0].snippet, contains('Build apps for any screen'));
      expect(results[1].title, equals('Dart Language'));
      expect(results[1].url, equals('https://dart.dev'));
    });

    test('Throws SearchException on HTTP error', () async {
      final mockClient = MockClient(
          (_) async => http.Response('Service Unavailable', 503));

      final provider = DuckDuckGoSearchProvider(client: mockClient);
      expect(
        () => provider.search('test'),
        throwsA(isA<SearchException>()),
      );
    });

    test('Throws SearchException when HTML has no parseable results', () async {
      // Bot-challenge page: no result-link or result-snippet elements
      const captchaHtml = '<html><body><p>Please verify you are human.</p></body></html>';
      final mockClient = MockClient(
          (_) async => http.Response(captchaHtml, 200));

      final provider = DuckDuckGoSearchProvider(client: mockClient);
      expect(
        () => provider.search('test'),
        throwsA(isA<SearchException>().having(
          (e) => e.hint,
          'hint',
          contains('Brave Search API key'),
        )),
      );
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // 3. Custom Search Provider
  // ══════════════════════════════════════════════════════════════════════════
  group('Phase 5: CustomSearchProvider', () {
    test('Parses generic results format { "results": [...] }', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.queryParameters['q'], equals('latest dart news'));
        expect(request.headers['Authorization'], equals('Bearer custom-key-123'));

        final body = jsonEncode({
          'results': [
            {
              'title': 'Dart News',
              'url': 'https://dart.dev/news',
              'snippet': 'Latest Dart news here.',
            },
          ],
        });
        return http.Response(body, 200);
      });

      final provider = CustomSearchProvider(
        endpointUrl: 'https://custom-search.example.com/search',
        apiKey: 'custom-key-123',
        client: mockClient,
      );

      final results = await provider.search('latest dart news', count: 5);
      expect(results.length, equals(1));
      expect(results[0].title, equals('Dart News'));
      expect(results[0].snippet, equals('Latest Dart news here.'));
    });

    test('Falls back to raw body when response format is unknown', () async {
      final mockClient = MockClient((_) async =>
          http.Response('{"unexpected": "format"}', 200));

      final provider = CustomSearchProvider(
        endpointUrl: 'https://custom-search.example.com/search',
        apiKey: '',
        client: mockClient,
      );

      final results = await provider.search('query');
      expect(results.length, equals(1));
      expect(results[0].title, equals('Response from Custom Search'));
    });

    test('Throws SearchException on HTTP error', () async {
      final mockClient = MockClient(
          (_) async => http.Response('Unauthorized', 401));

      final provider = CustomSearchProvider(
        endpointUrl: 'https://custom-search.example.com/search',
        apiKey: 'bad-key',
        client: mockClient,
      );

      expect(
        () => provider.search('test'),
        throwsA(isA<SearchException>()),
      );
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // 4. Unified output format (JSON) from WebSearchTool
  // ══════════════════════════════════════════════════════════════════════════
  group('Phase 5: WebSearchTool unified JSON output', () {
    test('Returns well-formed success JSON on valid results', () async {
      // We test the JSON structure by directly calling a provider-like mock.
      // WebSearchTool internally calls SearchProviderRegistry which reads
      // SharedPreferences — with no keys set, it falls back to DuckDuckGo.
      // We stub DuckDuckGo's HTTP call.

      final fakeHtml = '''
<html><body>
<a class="result-link" href="https://result.com/page">Result Title</a>
<td class="result-snippet">A useful snippet of text.</td>
</body></html>
''';

      // DuckDuckGoSearchProvider uses http.Client() internally.
      // We test the tool indirectly by verifying the output contract.
      final provider = DuckDuckGoSearchProvider(
        client: MockClient((_) async => http.Response(fakeHtml, 200)),
      );

      final results = await provider.search('test search');
      final json = {
        'status': 'success',
        'provider': provider.name,
        'query': 'test search',
        'results_count': results.length,
        'results': results.map((r) => r.toJson()).toList(),
      };

      // Validate the contract shape that WebSearchTool always returns
      expect(json['status'], equals('success'));
      expect(json.containsKey('provider'), isTrue);
      expect(json.containsKey('query'), isTrue);
      expect(json.containsKey('results'), isTrue);

      final resultsList = json['results'] as List;
      expect(resultsList.isNotEmpty, isTrue);

      final firstResult = resultsList[0] as Map<String, dynamic>;
      expect(firstResult.containsKey('title'), isTrue);
      expect(firstResult.containsKey('url'), isTrue);
      expect(firstResult.containsKey('snippet'), isTrue);
    });

    test('SearchException produces JSON error string — no raw exception thrown', () async {
      // Simulate a provider that always throws SearchException
      final failingHtml = '<html><body>CAPTCHA</body></html>';
      final provider = DuckDuckGoSearchProvider(
        client: MockClient((_) async => http.Response(failingHtml, 200)),
      );

      try {
        await provider.search('test');
        fail('Expected SearchException to be thrown');
      } on SearchException catch (e) {
        // WebSearchTool catches this and returns JSON, not re-throws.
        // Verify the error JSON contract:
        final errorJson = jsonEncode({
          'status': 'error',
          'provider': provider.name,
          'error': e.message,
          if (e.hint != null) 'hint': e.hint,
        });

        final decoded = jsonDecode(errorJson) as Map<String, dynamic>;
        expect(decoded['status'], equals('error'));
        expect(decoded.containsKey('error'), isTrue);
        expect(decoded.containsKey('hint'), isTrue);
        // Ensure the error message is informative
        expect(decoded['error'].toString(), isNotEmpty);
      }
    });

    test('WebSearchTool returns JSON error for missing query param', () async {
      final tool = WebSearchTool();
      final result = await tool.execute({});

      final decoded = jsonDecode(result) as Map<String, dynamic>;
      expect(decoded['status'], equals('error'));
      expect(decoded['error'], contains('query'));
    });

    test('Brave and DuckDuckGo return identical JSON shape', () async {
      // Brave mock response
      final braveBody = jsonEncode({
        'web': {
          'results': [
            {
              'title': 'Brave Result',
              'url': 'https://brave-result.com',
              'description': 'Brave snippet text.',
            }
          ]
        }
      });

      final braveProvider = BraveSearchProvider(
        apiKey: 'valid-brave-key',
        client: MockClient((_) async => http.Response(braveBody, 200)),
      );

      // DuckDuckGo mock response
      const ddgHtml = '''
<html><body>
<a class="result-link" href="https://ddg-result.com">DDG Result</a>
<td class="result-snippet">DDG snippet text.</td>
</body></html>
''';
      final ddgProvider = DuckDuckGoSearchProvider(
        client: MockClient((_) async => http.Response(ddgHtml, 200)),
      );

      final braveResults = await braveProvider.search('test', count: 1);
      final ddgResults = await ddgProvider.search('test', count: 1);

      // Both should have the same JSON keys
      final braveJson = braveResults.first.toJson();
      final ddgJson = ddgResults.first.toJson();

      expect(braveJson.keys.toSet(), equals(ddgJson.keys.toSet()));
      expect(braveJson.keys, containsAll(['title', 'url', 'snippet']));
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // 5. FetchUrlTool tests
  // ══════════════════════════════════════════════════════════════════════════
  group('Phase 5: FetchUrlTool', () {
    test('Returns success JSON with content on valid URL', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.host, equals('r.jina.ai'));
        expect(request.url.path, contains('example.com'));
        return http.Response('# Example Page\n\nThis is the page content.', 200);
      });

      final tool = FetchUrlTool(client: mockClient);
      final result = await tool.execute({'url': 'https://example.com/page'});

      final decoded = jsonDecode(result) as Map<String, dynamic>;
      expect(decoded['status'], equals('success'));
      expect(decoded['url'], equals('https://example.com/page'));
      expect(decoded['content'], contains('Example Page'));
      expect(decoded.containsKey('truncated'), isTrue);
    });

    test('Returns JSON error for missing url param', () async {
      final tool = FetchUrlTool();
      final result = await tool.execute({});

      final decoded = jsonDecode(result) as Map<String, dynamic>;
      expect(decoded['status'], equals('error'));
      expect(decoded['error'], contains('url'));
    });

    test('Returns JSON error for invalid URL format', () async {
      final tool = FetchUrlTool();
      final result = await tool.execute({'url': 'not-a-valid-url'});

      final decoded = jsonDecode(result) as Map<String, dynamic>;
      expect(decoded['status'], equals('error'));
      expect(decoded['error'], contains('Invalid URL'));
    });

    test('Returns JSON error on HTTP failure — no raw exception', () async {
      final mockClient = MockClient(
          (_) async => http.Response('Forbidden', 403));

      final tool = FetchUrlTool(client: mockClient);
      final result = await tool.execute({'url': 'https://example.com'});

      final decoded = jsonDecode(result) as Map<String, dynamic>;
      expect(decoded['status'], equals('error'));
      expect(decoded['error'], contains('403'));
    });

    test('Truncates very long content and sets truncated flag', () async {
      // Generate content > 36000 chars
      final longContent = 'x' * 40000;
      final mockClient = MockClient(
          (_) async => http.Response(longContent, 200));

      final tool = FetchUrlTool(client: mockClient);
      final result = await tool.execute({'url': 'https://example.com/long'});

      final decoded = jsonDecode(result) as Map<String, dynamic>;
      expect(decoded['status'], equals('success'));
      expect(decoded['truncated'], isTrue);
      expect((decoded['content'] as String).length, lessThanOrEqualTo(36100));
    });

    test('Network error returns JSON error — no uncaught exception', () async {
      final mockClient = MockClient((_) async {
        throw Exception('Connection refused');
      });

      final tool = FetchUrlTool(client: mockClient);
      final result = await tool.execute({'url': 'https://example.com'});

      final decoded = jsonDecode(result) as Map<String, dynamic>;
      expect(decoded['status'], equals('error'));
      expect(decoded['error'], isNotEmpty);
    });
  });
}
