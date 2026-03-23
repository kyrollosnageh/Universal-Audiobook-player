import '../models/auth_result.dart';
import '../models/book.dart';
import '../models/series.dart';
import '../models/unified_chapter.dart';

/// Abstract interface for all media server integrations.
///
/// The rest of the app NEVER knows which server type it's talking to.
/// All server-specific logic is encapsulated behind this interface.
abstract class ServerProvider {
  /// Human-readable provider name (e.g., "Emby", "Jellyfin").
  String get providerName;

  /// The base URL of the connected server.
  String get serverUrl;

  /// Whether the provider currently has a valid auth token.
  bool get isAuthenticated;

  // ── Authentication ──────────────────────────────────────────────────

  /// Authenticate with username and password.
  /// Returns [AuthResult] on success.
  /// Throws [AuthenticationException] on failure.
  ///
  /// Implementations MUST discard the password from memory immediately
  /// after the auth request completes.
  Future<AuthResult> authenticate(String username, String password);

  /// Log out: clear local token AND revoke server-side session.
  Future<void> logout();

  // ── Library Browsing ────────────────────────────────────────────────

  /// Fetch a paginated list of audiobooks.
  ///
  /// Supports server-side search, filtering, and sorting.
  /// Always uses server-side pagination — never fetches the full library.
  Future<PaginatedResult<Book>> fetchLibrary({
    int offset = 0,
    int limit = 50,
    String? searchTerm,
    String? genre,
    String? author,
    String? narrator,
    String? libraryId,
    SortOrder sort = SortOrder.titleAsc,
  });

  // ── Book Details ────────────────────────────────────────────────────

  /// Fetch full details for a specific book (on-demand).
  Future<BookDetail> getBookDetail(String bookId);

  /// Get the unified chapter list for a book.
  ///
  /// Handles all formats: M4B embedded, MP3-per-chapter, no chapters.
  Future<List<UnifiedChapter>> getChapters(String bookId);

  // ── Streaming ───────────────────────────────────────────────────────

  /// Get the streaming URL for an audio item.
  ///
  /// [itemId] is the specific track/file ID (from UnifiedChapter.trackItemId).
  /// [transcode] optionally requests server-side transcoding.
  Uri getStreamUrl(String itemId, {AudioFormat? transcode});

  /// Get the cover art URL for an item.
  ///
  /// [maxWidth] controls the server-side resize for bandwidth optimization.
  Uri getCoverArtUrl(String itemId, {int maxWidth = 300});

  // ── Progress Sync ──────────────────────────────────────────────────

  /// Report the current playback position to the server.
  Future<void> reportPosition(String bookId, Duration position);

  /// Get the last-known position from the server.
  /// Returns null if no position is stored.
  Future<Duration?> getServerPosition(String bookId);

  // ── Finished Status ────────────────────────────────────────────────

  /// Mark a book as finished or unfinished on the server.
  Future<void> reportFinished(String bookId, bool isFinished);

  /// Get whether a book is marked as finished on the server.
  /// Returns null if unknown.
  Future<bool?> getServerFinished(String bookId);

  // ── Favorites ──────────────────────────────────────────────────────

  /// Set or unset a book as a favorite on the server.
  /// Not all servers support this — implementations that don't should no-op.
  Future<void> setFavorite(String bookId, bool isFavorite);

  /// Set a user rating for a book (0.0 to 1.0 normalized).
  /// Not all servers support this — implementations that don't should no-op.
  Future<void> setRating(String bookId, double rating);

  // ── Series ─────────────────────────────────────────────────────────

  /// Fetch all series available in the library.
  Future<List<Series>> getSeries();

  /// Fetch all books in a specific series, in order.
  Future<List<Book>> getSeriesBooks(String seriesId);

  // ── Lifecycle ──────────────────────────────────────────────────────

  /// Dispose of resources (Dio instance, etc.).
  void dispose();
}
