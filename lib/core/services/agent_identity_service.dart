import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class AgentIdentityService {
  static String? _cachedPrompt;

  /// Loads the AGENT.md content.
  /// 
  /// In Production / Release:
  ///   Always loads from bundled Flutter assets (`rootBundle.loadString('AGENT.md')`).
  /// 
  /// In Local Development (kDebugMode):
  ///   Allows a local disk override if `File('AGENT.md')` exists to facilitate
  ///   rapid editing during dev, falling back to the bundled asset automatically.
  static Future<String> loadSystemPrompt() async {
    if (_cachedPrompt != null) {
      return _cachedPrompt!;
    }

    // 1. Development override: only active in debug mode
    if (kDebugMode) {
      try {
        final diskFile = File('AGENT.md');
        if (await diskFile.exists()) {
          final content = await diskFile.readAsString();
          if (content.trim().isNotEmpty) {
            _cachedPrompt = content;
            debugPrint('[AgentIdentityService] (Dev Override) Loaded AGENT.md from local disk (${content.length} chars)');
            return _cachedPrompt!;
          }
        }
      } catch (e) {
        debugPrint('[AgentIdentityService] Local disk check failed: $e, falling back to asset bundle.');
      }
    }

    // 2. Primary / Production source: Bundled Flutter asset
    try {
      final assetContent = await rootBundle.loadString('AGENT.md');
      if (assetContent.trim().isNotEmpty) {
        _cachedPrompt = assetContent;
        debugPrint('[AgentIdentityService] Loaded AGENT.md from Flutter asset bundle (${assetContent.length} chars)');
        return _cachedPrompt!;
      }
    } catch (e) {
      debugPrint('[AgentIdentityService] Asset bundle read of AGENT.md failed: $e');
    }

    // 3. Fallback default prompt if both asset and disk are unavailable
    _cachedPrompt = '''
You are Khwarizmi, an autonomous desktop AI agent for Windows.
Always assist the user directly, execute actions using your real tools, and maintain persistent memory.
''';
    debugPrint('[AgentIdentityService] Using built-in fallback prompt.');
    return _cachedPrompt!;
  }

  /// Invalidate the cached prompt (e.g. for testing or hot updates)
  static void reloadPrompt() {
    _cachedPrompt = null;
  }
}
