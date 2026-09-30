import 'search_result.dart';

/// Abstract interface for all search backends.
/// All providers expose the same contract; swapping the backend is transparent
/// to [WebSearchTool] and to the AI model.
abstract class SearchProvider {
  /// Human-readable backend name (used in log messages).
  String get name;

  /// Performs a web search and returns up to [count] results.
  ///
  /// Throws [SearchException] on unrecoverable error; callers should catch it
  /// and return a JSON error string to the model.
  Future<List<SearchResult>> search(String query, {int count = 5});
}

/// Thrown when a search backend encounters an unrecoverable error.
class SearchException implements Exception {
  final String message;
  final String? hint; // Optional hint shown to the AI / user
  const SearchException(this.message, {this.hint});

  @override
  String toString() => 'SearchException: $message';
}
