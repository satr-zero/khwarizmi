import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:khwarizmi/features/search/domain/search_provider.dart';
import 'package:khwarizmi/features/search/domain/search_result.dart';

/// Brave Search API provider.
///
/// Requires a Brave Search API key (free tier: 2 000 queries/month, no credit
/// card required). Key can be obtained from https://api.search.brave.com/
///
/// Endpoint: GET https://api.search.brave.com/res/v1/web/search
/// Docs:     https://api.search.brave.com/app/documentation/web-search
///
/// NOTE: The Brave Search API version string ("2025-03-03") is set as a
/// constant below. If Brave deprecates this version, the search will fail
/// with an HTTP 400/422 error and fall back to DuckDuckGo automatically in
/// [SearchProviderRegistry]. Check https://api.search.brave.com/app/changelog
/// periodically and update the constant below if needed.
class BraveSearchProvider implements SearchProvider {
  static const String _baseUrl =
      'https://api.search.brave.com/res/v1/web/search';

  // NOTE(maintainer): Update if Brave deprecates this header version.
  // Latest version: https://api.search.brave.com/app/changelog
  static const String _apiVersion = '2025-03-03';

  final String apiKey;
  final http.Client? client;

  BraveSearchProvider({required this.apiKey, this.client});

  @override
  String get name => 'Brave Search';

  @override
  Future<List<SearchResult>> search(String query, {int count = 5}) async {
    if (apiKey.trim().isEmpty) {
      throw const SearchException('Brave API key is empty');
    }

    final uri = Uri.parse(_baseUrl).replace(queryParameters: {
      'q': query.trim(),
      'count': count.clamp(1, 20).toString(),
      'text_decorations': '0',
      'safesearch': 'moderate',
    });

    final httpClient = client ?? http.Client();
    try {
      final response = await httpClient.get(
        uri,
        headers: {
          'Accept': 'application/json',
          'Accept-Encoding': 'gzip',
          'X-Subscription-Token': apiKey.trim(),
          'Api-Version': _apiVersion,
        },
      ).timeout(const Duration(seconds: 12));

      if (response.statusCode != 200) {
        throw SearchException(
          'Brave Search HTTP ${response.statusCode}',
          hint:
              'Check that your Brave API key is valid and has not exceeded its quota.',
        );
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final webResults = json['web']?['results'] as List<dynamic>? ?? [];

      return webResults.take(count).map((item) {
        final m = item as Map<String, dynamic>;
        return SearchResult(
          title: (m['title'] as String? ?? '').trim(),
          url: (m['url'] as String? ?? '').trim(),
          snippet: _truncateSnippet(
            (m['description'] as String?) ??
                (m['extra_snippets'] as List?)?.join(' ') ??
                '',
          ),
        );
      }).toList();
    } catch (e) {
      if (e is SearchException) rethrow;
      debugPrint('[BraveSearch] error: $e');
      throw SearchException('Brave Search request failed: $e');
    } finally {
      if (client == null) httpClient.close();
    }
  }

  /// Truncates snippet to ≤500 words (≈3 000 chars) to keep context size sane.
  static String _truncateSnippet(String text) {
    const maxChars = 3000;
    if (text.length <= maxChars) return text;
    return '${text.substring(0, maxChars)}…';
  }
}
