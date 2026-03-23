import 'package:audio_service/audio_service.dart';

import '../data/models/book.dart';
import '../services/library_service.dart';
import 'car_audio_handler.dart';

/// Media browse tree for Android Auto's MediaBrowserServiceCompat.
///
/// Structure (max 4 navigation levels):
/// Root
/// ├── Continue Listening (last 5 in-progress books)
/// ├── Recently Added (last 20 books)
/// ├── Authors (grouped by author)
/// └── Library (full alphabetical list)
///
/// Each book → Play (starts/resumes playback)
class MediaBrowseTree {
  MediaBrowseTree({required this.libraryService, required this.carHandler});

  final LibraryService libraryService;
  final CarAudioHandler carHandler;

  static const String rootId = 'root';
  static const String continueListeningId = 'continue_listening';
  static const String recentlyAddedId = 'recently_added';
  static const String authorsId = 'authors';
  static const String libraryId = 'library';

  /// Get the root-level menu items for car display.
  List<MediaItem> getRootItems() {
    return [
      const MediaItem(
        id: continueListeningId,
        title: 'Continue Listening',
        playable: false,
        extras: {'browsable': true},
      ),
      const MediaItem(
        id: recentlyAddedId,
        title: 'Recently Added',
        playable: false,
        extras: {'browsable': true},
      ),
      const MediaItem(
        id: authorsId,
        title: 'Authors',
        playable: false,
        extras: {'browsable': true},
      ),
      const MediaItem(
        id: libraryId,
        title: 'Library',
        playable: false,
        extras: {'browsable': true},
      ),
    ];
  }

  /// Get children for a specific parent ID.
  Future<List<MediaItem>> getChildren(String parentId, String serverId) async {
    switch (parentId) {
      case rootId:
        return getRootItems();

      case continueListeningId:
        final books = await libraryService.getContinueListening(serverId);
        return books.take(5).map((b) => carHandler.bookToMediaItem(b)).toList();

      case recentlyAddedId:
        final books = await libraryService.getCachedBooks(serverId, limit: 20);
        return books.map((b) => carHandler.bookToMediaItem(b)).toList();

      case authorsId:
        return _getAuthorsList(serverId);

      case libraryId:
        final books = await libraryService.getCachedBooks(serverId, limit: 50);
        return books.map((b) => carHandler.bookToMediaItem(b)).toList();

      default:
        // Check if it's an author filter
        if (parentId.startsWith('author:')) {
          final author = parentId.substring(7);
          return _getBooksByAuthor(serverId, author);
        }
        return [];
    }
  }

  Future<List<MediaItem>> _getAuthorsList(String serverId) async {
    final books = await libraryService.getCachedBooks(serverId, limit: 200);

    // Group by author
    final authors = <String>{};
    for (final book in books) {
      if (book.author != null && book.author!.isNotEmpty) {
        authors.add(book.author!);
      }
    }

    return authors.toList()
      ..sort()
      ..map(
        (author) => MediaItem(
          id: 'author:$author',
          title: author,
          playable: false,
          extras: const {'browsable': true},
        ),
      ).toList();
  }

  Future<List<MediaItem>> _getBooksByAuthor(
    String serverId,
    String author,
  ) async {
    final books = await libraryService.getCachedBooks(
      serverId,
      limit: 100,
      author: author,
    );

    return books.map((b) => carHandler.bookToMediaItem(b)).toList();
  }
}
