# Hamburger Menu Drawer — Design Spec

## Goal
Add a navigation drawer (hamburger menu) to the library home screen with filter tabs for browsing audiobooks by category, replacing the inline "Continue Listening" section.

## Scope
- Library home screen only — other screens keep their current navigation
- No new screens — drawer items filter the existing library grid

## Drawer Structure

### Header
- App name "Libretto"
- Active server name (from `authState.activeServer?.name`)
- Server type icon (Emby/Jellyfin/Plex/Audiobookshelf color-coded)

### Navigation Items
1. **All Books** — default view, full library grid (current behavior)
2. **Recently Added** — sorted by `dateAddedDesc`
3. **Currently Reading** — books with `0 < progress < 1.0` (replaces inline "Continue Listening" section)
4. **Favorites** — books where `isFavorite == true`
5. **Finished** — books where `isFinished == true`
6. *(Divider)*
7. **Settings** — navigates to `/settings`

### Footer
- "Switch Server" link — navigates to `/hub`

## Behavior

### Filtering
- Selecting a drawer item sets a `LibraryFilter` enum on the `LibraryNotifier`
- The existing grid re-renders with the filtered book list
- AppBar title updates to reflect active filter (e.g., "Currently Reading")
- "All Books" clears the filter and restores default behavior

### Sort
- The sort popup menu remains in the AppBar actions (right side)
- Sort applies within the active filter

### AppBar Changes
- Leading icon changes from none/back to hamburger menu icon (`Icons.menu`)
- Title shows active filter name instead of server name
- Server name moves to drawer header
- Settings icon removed from AppBar actions (moved to drawer)

### Removed
- Inline "Continue Listening" horizontal scroll section — replaced by "Currently Reading" drawer filter

## Files to Modify
- `lib/screens/library_home/library_home_screen.dart` — add Drawer, hamburger icon, remove Continue Listening section, apply filter to grid
- `lib/state/library_provider.dart` — add `LibraryFilter` enum and filter logic to `LibraryNotifier`
- `lib/widgets/app_drawer.dart` (new) — extracted drawer widget

## Styling
- Follow existing `LibrettoTheme` dark theme
- Drawer background: `LibrettoTheme.surface`
- Active item highlight: `LibrettoTheme.primary` with alpha
- Icons for each item: `Icons.library_books` (All), `Icons.new_releases` (Recently Added), `Icons.auto_stories` (Currently Reading), `Icons.favorite` (Favorites), `Icons.check_circle` (Finished), `Icons.settings` (Settings), `Icons.swap_horiz` (Switch Server)
