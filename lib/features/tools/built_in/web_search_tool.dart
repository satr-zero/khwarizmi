import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:khwarizmi/features/agent/domain/entities/tool_definition.dart';
import 'package:khwarizmi/features/search/data/search_provider_registry.dart';
import 'package:khwarizmi/features/search/domain/search_provider.dart';
import 'package:khwarizmi/features/tools/domain/agent_tool.dart';

// ══════════════════════════════════════════════════════════════════════════════
// web_search — unified web search tool
// ══════════════════════════════════════════════════════════════════════════════

/// Provides real-time web search capability to all AI providers.
///
/// The tool definition exposed to the model is FIXED regardless of which
/// backend is active (Brave / DuckDuckGo / Custom). Swapping the backend in
/// Settings is transparent from the model's perspective.
///
/// Response format (always JSON):
/// {
///   "status": "success",
///   "provider": "Brave Search",
///   "query": "...",
///   "results": [
///     { "title": "...", "url": "...", "snippet": "..." },
///     ...
///   ]
/// }
///
/// On failure:
/// { "status": "error", "error": "...", "hint": "..." }
class WebSearchTool implements AgentTool {
  @override
  ToolDefinition get definition => const ToolDefinition(
        name: 'web_search',
        description:
            'Searches the web for real-time information, recent events, current facts, '
            'or any information that may not be in the model\'s training data. '
            'Use this whenever the user asks about something recent, current, or that '
            'requires up-to-date information. Returns a list of results with titles, '
            'URLs, and text snippets.',
        parameters: {
          'type': 'OBJECT',
          'properties': {
            'query': {
              'type': 'STRING',
              'description':
                  'The search query string. Be specific and concise for best results.'
            },
            'count': {
              'type': 'INTEGER',
              'description':
                  'Number of results to return (1–5, default 5). Use fewer for focused queries.'
            },
          },
          'required': ['query'],
        },
      );

  @override
  Future<String> execute(Map<String, dynamic> arguments) async {
    final query = arguments['query'] as String?;
    if (query == null || query.trim().isEmpty) {
      return jsonEncode({
        'status': 'error',
        'error': 'Missing required parameter: query',
      });
    }

    final count = ((arguments['count'] as num?)?.toInt() ?? 5).clamp(1, 5);

    SearchProvider provider;
    try {
      provider = await SearchProviderRegistry.getActiveProvider();
    } catch (e) {
      return jsonEncode({
        'status': 'error',
        'error': 'Failed to initialize search provider: $e',
      });
    }

    try {
      final results = await provider.search(query.trim(), count: count);
      return jsonEncode({
        'status': 'success',
        'provider': provider.name,
        'query': query.trim(),
        'results_count': results.length,
        'results': results.map((r) => r.toJson()).toList(),
      });
    } on SearchException catch (e) {
      debugPrint('[WebSearchTool] SearchException: ${e.message}');
      return jsonEncode({
        'status': 'error',
        'provider': provider.name,
        'error': e.message,
        if (e.hint != null) 'hint': e.hint,
      });
    } catch (e) {
      debugPrint('[WebSearchTool] Unexpected error: $e');
      return jsonEncode({
        'status': 'error',
        'provider': provider.name,
        'error': 'Unexpected search error: $e',
      });
    }
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// fetch_url — fetches the full readable content of a specific URL
// ══════════════════════════════════════════════════════════════════════════════

/// Fetches and returns the readable text content of a specific URL.
///
/// Uses the free Jina AI Reader service (https://r.jina.ai/) which extracts
/// clean Markdown from any webpage — no API key or registration required.
///
/// NOTE(maintainer): r.jina.ai is a free public service with rate limits.
/// If it becomes unavailable or rate-limited, the tool will return an error
/// JSON with a clear message. No silent fallback to raw HTML to avoid
/// injecting unreadable markup into the model context.
///
/// Response format on success:
/// { "status": "success", "url": "...", "content": "... (markdown text) ..." }
///
/// On failure:
/// { "status": "error", "url": "...", "error": "..." }
class FetchUrlTool implements AgentTool {
  // NOTE: r.jina.ai is a free, unofficial content-extraction service by Jina AI.
  // Check https://jina.ai/reader/ for availability and rate limits.
  static const String _jinaReaderBase = 'https://r.jina.ai/';

  // Maximum content length returned to the model (in characters, ≈6 000 words)
  static const int _maxContentChars = 36000;

  final http.Client? client;

  FetchUrlTool({this.client});

  @override
  ToolDefinition get definition => const ToolDefinition(
        name: 'fetch_url',
        description:
            'Fetches and reads the full text content of a specific webpage URL. '
            'Use this AFTER obtaining a URL from web_search results to get detailed '
            'information from that page. Returns clean readable text (Markdown format). '
            'Do NOT use this for general search — use web_search first, then fetch_url '
            'on a specific result URL if you need more detail.',
        parameters: {
          'type': 'OBJECT',
          'properties': {
            'url': {
              'type': 'STRING',
              'description': 'The full URL of the webpage to fetch and read.'
            },
          },
          'required': ['url'],
        },
      );

  @override
  Future<String> execute(Map<String, dynamic> arguments) async {
    final url = (arguments['url'] as String?)?.trim();
    if (url == null || url.isEmpty) {
      return jsonEncode({
        'status': 'error',
        'error': 'Missing required parameter: url',
      });
    }

    // Validate URL format before making the request
    final parsed = Uri.tryParse(url);
    if (parsed == null || !parsed.hasScheme) {
      return jsonEncode({
        'status': 'error',
        'url': url,
        'error': 'Invalid URL format. Provide a full URL starting with https:// or http://',
      });
    }

    final jinaUrl = '$_jinaReaderBase$url';
    final httpClient = client ?? http.Client();

    try {
      final response = await httpClient.get(
        Uri.parse(jinaUrl),
        headers: {
          'Accept': 'text/plain,text/markdown,*/*',
          'X-Return-Format': 'markdown',
        },
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode != 200) {
        return jsonEncode({
          'status': 'error',
          'url': url,
          'error':
              'Failed to fetch page content (HTTP ${response.statusCode}). '
              'The page may require authentication or be blocked.',
        });
      }

      var content = response.body.trim();
      final wasTruncated = content.length > _maxContentChars;
      if (wasTruncated) {
        content = '${content.substring(0, _maxContentChars)}\n\n[... content truncated for context size ...]';
      }

      return jsonEncode({
        'status': 'success',
        'url': url,
        'content_length': response.body.length,
        'truncated': wasTruncated,
        'content': content,
      });
    } catch (e) {
      debugPrint('[FetchUrlTool] error fetching $url: $e');
      return jsonEncode({
        'status': 'error',
        'url': url,
        'error': 'Network error while fetching URL: $e',
      });
    } finally {
      if (client == null) httpClient.close();
    }
  }
}
