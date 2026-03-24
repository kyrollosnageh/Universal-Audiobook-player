# UI/UX Revamp — "Berry Garden" Design Spec

## Goal
Transform Libretto's visual identity from a generic dark theme to a playful, colorful "Berry Garden" aesthetic across all screens.

## Color Palette

| Token | Value | Usage |
|-------|-------|-------|
| primary | `#E91E80` (magenta/berry) | Buttons, active states, progress bars, toggles |
| accent | `#A8E824` (lime green) | Badges, counts, success, highlights |
| background | `#1A1A2E` (deep charcoal) | Scaffold background |
| surface | `#232340` (lighter charcoal) | Elevated surfaces |
| cardColor | `#2D2B55` (purple-tinted dark) | Cards, tiles, sheets |
| onSurface | `#F5F0FF` (warm white) | Primary text |
| onSurfaceVariant | `#9B95B8` (muted lavender) | Secondary text, icons |
| error | `#FF6B6B` (soft coral) | Errors, offline status |
| divider | `#3D3A66` (muted purple) | Dividers, borders |

## Typography

- **Headings:** Nunito (Extra-Bold / Bold) — rounded, friendly
- **Body:** System default (already in Flutter) — clean readability
- **Monospace/numbers:** Use tabular figures for time displays

Add `google_fonts` dependency for Nunito.

## Shared Design Tokens

- **Border radius:** 16px on cards/buttons/sheets, 20px on cover art, 24px on bottom sheets
- **Card elevation:** subtle shadow (`0, 4, 12, rgba(0,0,0,0.3)`)
- **Gradient overlays:** linear bottom-to-top on cover art (transparent → cardColor)
- **Animations:** 200ms ease-out for taps, 300ms for page transitions, staggered 50ms delay per list item on entry

## Screen Designs

### Library Home (library_home_screen.dart)

**AppBar:**
- Transparent background, no elevation
- Title: active filter name in Nunito Extra-Bold
- Hamburger icon: berry glow ring when drawer open

**Book Grid Cards:**
- Cover art fills entire card, rounded 16px
- Gradient overlay at bottom with title (Nunito Bold, 14sp) and author (regular, 12sp, lavender)
- Progress: thin 3px lime bar at card bottom edge (only if progress > 0)
- Subtle shadow on card

**Search Bar:**
- Pill-shaped (borderRadius 24px)
- Frosted glass effect: semi-transparent cardColor with slight blur
- Berry border on focus
- Search icon in lavender, clears to X when text entered

**Drawer:**
- Header: gradient background (charcoal → purple-tinted), "Libretto" in Nunito Extra-Bold berry, server name in lavender
- Active item: berry text + berry/alpha background
- Count badges: lime background with dark text, pill-shaped
- Genre section: berry icon, expands with smooth animation
- Footer: "Switch Server" with subtle divider above

### Book Detail (book_detail_screen.dart)

**Hero Section:**
- Large cover art (width: 200px phone, 280px tablet) with 20px rounded corners
- Blurred copy of cover behind as backdrop (sigma: 30, dark overlay 0.6)
- Title: Nunito Bold, 24sp
- Author/narrator: lavender, 16sp

**Metadata Chips:**
- Horizontal row of pill-shaped chips (duration, genre, year)
- Lime icon + lavender text on each chip
- cardColor background

**Play Button:**
- Full-width pill shape, berry gradient (primary → slightly darker)
- White text Nunito Bold
- Bounce animation on press (scale 0.95 → 1.0)
- Icon: play_arrow or replay based on finished state

**Chapter List:**
- Numbered items with berry number circle
- Active/playing chapter: berry background highlight
- Duration on right in lavender
- Subtle purple dividers

**Description:**
- Max 4 lines with gradient fade
- "Read more" tap to expand with smooth height animation

### Player (player_screen.dart)

**Background:**
- Blurred cover art (sigma: 40) + dark overlay (0.7)
- Fills entire screen

**Cover Art:**
- Centered, large (280px phone, 400px tablet)
- 20px rounded corners, elevated shadow

**Now Playing Info:**
- Book title: Nunito Bold, 20sp, white
- Chapter name: regular, 16sp, lavender
- Centered below cover

**Progress Bar:**
- Thick (6px), rounded caps
- Track: berry with 0.3 alpha
- Fill: lime gradient
- Thumb: lime circle 16px
- Time labels below: current left, remaining right, lavender

**Controls:**
- Center row: rewind (30s) | previous | play/pause | next | forward (30s)
- Play/pause: large circle (64px) with berry gradient, white icon
- Skip buttons: 40px, lavender icons, bounce on tap
- Speed chip: pill-shaped below controls, lime text on cardColor

**Sleep Timer:**
- Moon icon in top-right, berry when active

### Server Hub (server_hub_screen.dart)

**Server Cards:**
- cardColor background, 16px radius
- Left: server type icon (colored per type)
- Center: server name (Nunito Bold), URL below (lavender, 12sp)
- Right: status dot (lime = online, coral = offline)
- Tap highlight: berry alpha

**Empty State:**
- Large dns_outlined icon (80px) in lavender
- "No servers added" in Nunito Bold
- Subtitle in lavender
- "Add Server" button: berry gradient, pill-shaped, bounce animation
- "Sign in" button: outlined with berry border

**Settings Gear:**
- Top-right, always visible (both empty and populated states)

### Settings (settings_screen.dart)

**Section Groups:**
- Rounded cardColor containers with 16px radius
- Section headers: Nunito Bold, berry color, 14sp
- Tiles: standard ListTile with lavender icons

**Toggles:**
- Berry when on, muted when off

**Update Dialog:**
- Berry "Update" button, lime "Later" text button

**Version Footer:**
- Centered, lavender text with lime version number

### Genres Screen (genres_screen.dart)

**Grid:**
- 2-column grid of genre cards
- Each card: cardColor, 16px radius, genre name centered in Nunito Bold
- Berry gradient overlay on tap/selected
- Icon above name (music_note, psychology, etc. mapped per genre)

## Files to Modify

### Theme
- `lib/core/theme.dart` — complete rewrite of color palette, text theme, component themes

### Dependencies
- `pubspec.yaml` — add `google_fonts: ^6.0.0`

### Screens (UI updates only, no logic changes)
- `lib/screens/library_home/library_home_screen.dart`
- `lib/screens/book_detail/book_detail_screen.dart`
- `lib/screens/player/player_screen.dart`
- `lib/screens/server_hub/server_hub_screen.dart`
- `lib/screens/settings/settings_screen.dart`
- `lib/screens/genres/genres_screen.dart`
- `lib/widgets/app_drawer.dart`
- `lib/widgets/book_cover.dart`

## Out of Scope
- No logic changes — only visual/styling updates
- No new features — only restyling existing UI
- No navigation changes — routes stay the same
