import 'package:flutter/material.dart';

import '../core/extensions.dart';
import '../core/theme.dart';
import '../data/models/unified_chapter.dart';

/// A single chapter row in the chapter list.
class ChapterListTile extends StatelessWidget {
  const ChapterListTile({
    super.key,
    required this.chapter,
    required this.index,
    required this.isCurrentChapter,
    this.onTap,
  });

  final UnifiedChapter chapter;
  final int index;
  final bool isCurrentChapter;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      label:
          'Chapter ${index + 1}: ${chapter.title}, '
          'duration ${chapter.duration.toHms()}'
          '${isCurrentChapter ? ', currently playing' : ''}',
      child: ListTile(
        leading: SizedBox(
          width: 32,
          child: Center(
            child: isCurrentChapter
                ? const Icon(
                    Icons.equalizer,
                    color: LibrettoTheme.primary,
                    size: 24,
                  )
                : Text('${index + 1}', style: theme.textTheme.bodySmall),
          ),
        ),
        title: Text(
          chapter.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: isCurrentChapter ? LibrettoTheme.primary : null,
            fontWeight: isCurrentChapter ? FontWeight.w600 : null,
          ),
        ),
        trailing: Text(
          chapter.duration.toHms(),
          style: theme.textTheme.bodySmall,
        ),
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        minVerticalPadding: 0,
      ),
    );
  }
}
