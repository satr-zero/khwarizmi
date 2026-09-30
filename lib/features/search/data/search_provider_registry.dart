import 'package:flutter/foundation.dart';
import 'package:khwarizmi/core/security/secure_storage_service.dart';
import 'package:khwarizmi/features/search/data/brave_search_provider.dart';
import 'package:khwarizmi/features/search/data/custom_search_provider.dart';
import 'package:khwarizmi/features/search/data/duckduckgo_search_provider.dart';
import 'package:khwarizmi/features/search/domain/search_provider.dart';

/// Manages search backend selection with automatic priority-based discovery.
///
/// Priority order (first configured wins):
///   1. Custom search endpoint (if URL + optional key configured by user)
///   2. Brave Search (if API key present)
///   3. DuckDuckGo scraping (zero-config free fallback — always available)
class SearchProviderRegistry {
  // Storage keys are managed by SecureStorageService (see getCustomSearchUrl/Name).
  static const _braveKeyId = 'brave_search';

  /// Returns the active [SearchProvider] based on current configuration.
  /// Always returns a valid provider (falls back to DuckDuckGo if nothing configured).
  static Future<SearchProvider> getActiveProvider() async {
    // 1. Check custom endpoint
    final customUrl = await getCustomSearchUrl();
    if (customUrl != null && customUrl.trim().isNotEmpty) {
      final customKey = await SecureStorageService.getApiKey('custom_search') ?? '';
      final customName = await getCustomSearchName() ?? 'Custom Search';
      debugPrint('[SearchRegistry] Using custom search: $customUrl');
      return CustomSearchProvider(
        endpointUrl: customUrl,
        apiKey: customKey,
        displayName: customName,
      );
    }

    // 2. Check Brave Search API key
    final braveKey = await SecureStorageService.getApiKey(_braveKeyId) ?? '';
    if (braveKey.trim().isNotEmpty) {
      debugPrint('[SearchRegistry] Using Brave Search');
      return BraveSearchProvider(apiKey: braveKey);
    }

    // 3. DuckDuckGo fallback (zero config)
    debugPrint('[SearchRegistry] Using DuckDuckGo fallback (no API key configured)');
    return DuckDuckGoSearchProvider();
  }

  /// Returns a description of the currently active backend for display in UI.
  static Future<String> getActiveProviderName() async {
    final customUrl = await getCustomSearchUrl();
    if (customUrl != null && customUrl.trim().isNotEmpty) {
      return await getCustomSearchName() ?? 'Custom Search';
    }
    final braveKey = await SecureStorageService.getApiKey(_braveKeyId) ?? '';
    if (braveKey.trim().isNotEmpty) return 'Brave Search';
    return 'DuckDuckGo (مجاني — بدون مفتاح)';
  }

  // ── Brave Search ──────────────────────────────────────────────────────────
  static Future<void> saveBraveApiKey(String key) =>
      SecureStorageService.saveApiKey(_braveKeyId, key);

  static Future<String?> getBraveApiKey() =>
      SecureStorageService.getApiKey(_braveKeyId);

  static Future<void> clearBraveApiKey() =>
      SecureStorageService.deleteApiKey(_braveKeyId);

  // ── Custom Search ─────────────────────────────────────────────────────────
  static Future<void> saveCustomSearch({
    required String url,
    required String apiKey,
    required String name,
  }) async {
    await SecureStorageService.saveCustomSearchUrl(url);
    await SecureStorageService.saveCustomSearchName(name);
    if (apiKey.trim().isNotEmpty) {
      await SecureStorageService.saveApiKey('custom_search', apiKey);
    } else {
      await SecureStorageService.deleteApiKey('custom_search');
    }
  }

  static Future<void> clearCustomSearch() async {
    await SecureStorageService.saveCustomSearchUrl('');
    await SecureStorageService.saveCustomSearchName('');
    await SecureStorageService.deleteApiKey('custom_search');
  }

  static Future<String?> getCustomSearchUrl() =>
      SecureStorageService.getCustomSearchUrl();

  static Future<String?> getCustomSearchName() =>
      SecureStorageService.getCustomSearchName();
}
