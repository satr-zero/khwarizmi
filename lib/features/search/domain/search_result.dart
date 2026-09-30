/// Unified search result returned by ALL search providers.
/// The model always sees this fixed shape regardless of which backend is active.
class SearchResult {
  /// Page title
  final String title;

  /// Page URL
  final String url;

  /// Snippet/excerpt text (truncated to ~500–800 words max before injection)
  final String snippet;

  const SearchResult({
    required this.title,
    required this.url,
    required this.snippet,
  });

  Map<String, dynamic> toJson() => {
        'title': title,
        'url': url,
        'snippet': snippet,
      };
}
