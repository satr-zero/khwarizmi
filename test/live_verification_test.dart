// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:khwarizmi/core/security/secure_storage_service.dart';
import 'package:khwarizmi/features/search/data/brave_search_provider.dart';
import 'package:khwarizmi/features/search/data/duckduckgo_search_provider.dart';
import 'package:khwarizmi/features/search/data/search_provider_registry.dart';
import 'package:khwarizmi/features/tools/built_in/web_search_tool.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _RealHttpOverrides extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = _RealHttpOverrides();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  group('Live Manual Verification Tests (Phase 5 Requirements)', () {
    test('Test 1: Real DuckDuckGo search without any API key', () async {
      // 1. Ensure no Brave or custom key is set
      await SecureStorageService.deleteApiKey('brave_search');
      await SecureStorageService.deleteApiKey('custom_search');
      await SecureStorageService.saveCustomSearchUrl('');

      // 2. Verify registry auto-detects DuckDuckGo
      final provider = await SearchProviderRegistry.getActiveProvider();
      expect(provider, isA<DuckDuckGoSearchProvider>());
      expect(provider.name, contains('DuckDuckGo'));

      // 3. Execute real live search via WebSearchTool
      final tool = WebSearchTool();
      final resultJsonStr = await tool.execute({
        'query': 'Flutter release notes',
        'count': 3,
      });

      final result = jsonDecode(resultJsonStr) as Map<String, dynamic>;
      print('=== TEST 1: DuckDuckGo Live Search Result ===');
      print('Status: ${result['status']}');
      print('Provider: ${result['provider']}');
      print('Results Count: ${result['results_count']}');

      expect(result['status'], equals('success'));
      expect(result['provider'], contains('DuckDuckGo'));
      final results = result['results'] as List;
      expect(results.isNotEmpty, isTrue);

      for (var i = 0; i < results.length; i++) {
        final item = results[i] as Map<String, dynamic>;
        print('[$i] Title: ${item['title']}');
        print('    URL: ${item['url']}');
        print('    Snippet: ${item['snippet']}');
      }
    });

    test('Test 2: Provider switching when Brave API key is configured', () async {
      // 1. Store a Brave Search API key
      const testBraveKey = 'BSA-live-test-key-sample-12345';
      await SecureStorageService.saveApiKey('brave_search', testBraveKey);

      // 2. Verify active provider switches immediately to BraveSearchProvider
      final activeProvider = await SearchProviderRegistry.getActiveProvider();
      final activeName = await SearchProviderRegistry.getActiveProviderName();

      print('=== TEST 2: Provider Switching Proof ===');
      print('Active Provider Type: ${activeProvider.runtimeType}');
      print('Active Provider Name: $activeName');
      print('Brave Key Present: ${(activeProvider as BraveSearchProvider).apiKey.isNotEmpty}');

      expect(activeProvider, isA<BraveSearchProvider>());
      expect(activeName, equals('Brave Search'));
      expect(activeProvider.apiKey, equals(testBraveKey));

      // 3. Verify WebSearchTool executes under Brave Search provider tag
      final tool = WebSearchTool();
      final resultJsonStr = await tool.execute({
        'query': 'Dart programming',
        'count': 2,
      });

      final result = jsonDecode(resultJsonStr) as Map<String, dynamic>;
      print('WebSearchTool Provider Tag: ${result['provider']}');
      expect(result['provider'], equals('Brave Search'));

      // Clean up
      await SecureStorageService.deleteApiKey('brave_search');
    });

    test('Test 3: FetchUrlTool real live extraction from a real URL', () async {
      final fetchTool = FetchUrlTool();
      const targetUrl = 'https://dart.dev';

      print('=== TEST 3: Real FetchUrlTool Execution ===');
      print('Fetching: $targetUrl');

      final resultJsonStr = await fetchTool.execute({'url': targetUrl});
      final result = jsonDecode(resultJsonStr) as Map<String, dynamic>;

      print('Status: ${result['status']}');
      print('URL: ${result['url']}');
      print('Content Length: ${result['content_length']}');
      print('Truncated: ${result['truncated']}');

      final content = result['content'] as String?;
      expect(result['status'], equals('success'));
      expect(content, isNotNull);
      expect(content!.isNotEmpty, isTrue);

      final snippetPreview = content.length > 300 ? content.substring(0, 300) : content;
      print('Preview of Fetched Content:\n$snippetPreview...');
    });
  });
}
