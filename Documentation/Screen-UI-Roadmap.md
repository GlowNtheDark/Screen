# Screen tvOS Redesign Roadmap

This roadmap replaces the earlier incremental polish plan. The redesign prioritizes a quieter, sharper television interface with fixed deep-navy surfaces, square geometry, direct navigation, and media-first layouts. Screen Ice Blue (`#2EA8FF`) communicates focus and action.

## Locked design rules

- Do not change backgrounds in response to focused movies or shows.
- Use square corners for Screen-owned artwork, buttons, cards, menus, panels, search controls, overlays, and progress surfaces.
- Use Ice Blue outlines, restrained glow, elevation, and scale to communicate focus.
- Treat section headings as labels, not navigation links. Users enter content directly through the visible titles.
- Remove Next Up from Home. Any remaining Next Up heading is a non-interactive label above its items.
- Keep profile and account information out of the main menu and routine content screens.
- Preserve the iOS target and shared internals, but keep Screen product changes tvOS-only.

## Phase 1: Visual foundation

- [x] Replace focused-poster and color-changing backgrounds with fixed deep navy.
- [x] Remove rounded geometry from shared tvOS components.
- [x] Establish the square Ice Blue focus treatment.
- [x] Convert linked collection headings into labels.
- Audit remote focus paths after the shared-style changes.

## Phase 2: Navigation and Home

- [x] Build a fixed Plex-style sidebar that may collapse.
- Allow customization of shortcuts shown while collapsed.
- [x] Hide profile and account information.
- [x] Remove Next Up from Home.
- [x] Add Popular Movies to Home.

## Phase 3: Search and libraries

- [x] Add Plex-style letter navigation.
- [x] Add movie sorting controls.
- [x] Left-align Suggested on Search.
- Keep directional focus inside the search controls instead of jumping to the sidebar.

## Phase 4: Movie and TV details

- [x] Redesign movie details as a simple two-column page: artwork and compact actions on the left, title and description on the right.
- [x] Include Play, Play From Beginning, and Mark Watched without an overflow menu.
- Implement Watch Together with a functional Jellyfin SyncPlay flow.
- [x] Remove Recommended from movie details.
- [x] Put TV year, genre, season and episode, runtime, and rating on one metadata line.
- [x] Remove the TV-show About section.

## Phase 5: Player

- Reorganize progress, playback settings, information, and technical details around a Plex-like tab structure.
- Open the tabs with a Down press on the remote.
- Shift the playing video upward to reveal the tabs instead of placing a swipe-down menu over it.
- Preserve Screen intro, credits, and episode-transition behavior.

## Phase 6: Apple TV Top Shelf

- Replace static promotional Top Shelf artwork with dynamic Continue Watching content.
- Add the required TV Services extension and a safe shared-data path for the active server session.
- Keep artwork, titles, and progress useful when the main app is not running.

## Phase 7: Typography and accessibility

- Compare television-readable system and bundled font options before selecting a final family.
- Verify contrast, focus visibility, Reduce Motion, VoiceOver, overscan-safe layout, and long-title behavior.

## Current focus

Validate Phases 1-4 on a physical Apple TV, especially focus movement and overscan. Then continue with Phase 5: Player.
