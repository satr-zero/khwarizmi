import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:khwarizmi/features/search/domain/search_provider.dart';
import 'package:khwarizmi/features/search/domain/search_result.dart';

/// Generic search provider for any custom endpoint the user configures.
///
/// Expects the endpoint to accept a `GET ?q=<query>&count=<n>` request and
/// return JSON in OpenAI/Brave-compatible format:
///   { "results": [ { "title": "...", "url": "...", "snippet": "..." } ] }
/// or the standard Brave format:
///   { "web": { "results": [ { "title": "...", "url": "...", "description": "..." } ] } }
///
/// If the response does not match either known format, the raw text (truncated)
/// is returned as a single result so the model can still act on it.
class CustomSearchProvider implements SearchProvider {
  final String endpointUrl;
  final String apiKey;
  final String displayName;
  final http.Client? client;

  CustomSearchProvider({
    required this.endpointUrl,
    required this.apiKey,
    this.displayName = 'Custom Search',
    this.client,
  });

  @override
  String get name => displayName;

  @override
  Future<List<SearchResult>> search(String query, {int count = 5}) async {
    if (endpointUrl.trim().isEmpty) {
      throw const SearchException('Custom search endpoint URL is empty.');
    }

    final uri = Uri.tryParse(endpointUrl.trim());
    if (uri == null) {
      throw SearchException('Invalid custom search endpoint URL: $endpointUrl');
    }

    final fullUri = uri.replace(queryParameters: {
      ...uri.queryParameters,
      'q': query.trim(),
      'count': count.toString(),
    });

    final headers = <String, String>{
      'Accept': 'application/json',
    };
    if (apiKey.trim().isNotEmpty) {
      headers['Authorization'] = 'Bearer ${apiKey.trim()}';
    }

    final httpClient = client ?? http.Client();
    try {
      final response = await httpClient
          .get(fullUri, headers: headers)
          .timeout(const Duration(seconds: 12));

      if (response.statusCode != 200) {
        throw SearchException(
          '$displayName returned HTTP ${response.statusCode}',
          hint: 'Verify the custom endpoint URL and API key in Settings.',
        );
      }

      return _parseResponse(response.body, count);
    } catch (e) {
      if (e is SearchException) rethrow;
      debugPrint('[$displayName] error: $e');
      throw SearchException('$displayName request failed: $e');
    } finally {
      if (client == null) httpClient.close();
    }
  }

  List<SearchResult> _parseResponse(String body, int count) {
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;

      // Try Brave-style format first
      final braveResults = json['web']?['results'] as List<dynamic>?;
      if (braveResults != null && braveResults.isNotEmpty) {
        return _mapResults(braveResults, count);
      }

      // Try generic format: { "results": [...] }
      final genericResults = json['results'] as List<dynamic>?;
      if (genericResults != null && genericResults.isNotEmpty) {
        return _mapResults(genericResults, count);
      }

      // Try flat array
      if (json.isEmpty) {
        final list = jsonDecode(body) as List<dynamic>?;
        if (list != null && list.isNotEmpty) {
          return _mapResults(list, count);
        }
      }
    } catch (_) {}

    // Fallback: return raw body as a single text result
    return [
      SearchResult(
        title: 'Response from $displayName',
        url: endpointUrl,
        snippet: body.length > 3000 ? '${body.substring(0, 3000)}…' : body,
      )
    ];
  }

  static List<SearchResult> _mapResults(List<dynamic> items, int count) {
    return items.take(count).map((item) {
      final m = item as Map<String, dynamic>;
      final snippet = (m['snippet'] ?? m['description'] ?? m['body'] ?? '') as String;
      return SearchResult(
        title: (m['title'] as String? ?? '').trim(),
        url: (m['url'] as String? ?? m['link'] as String? ?? '').trim(),
        snippet: snippet.length > 3000 ? '${snippet.substring(0, 3000)}…' : snippet,
      );
    }).toList();
  }
}
