# Product

Screen is a native tvOS media client for Jellyfin, with shared Screen foundations.
Its television experience is media-first: recognizable artwork, readable metadata,
compact actions, and clear remote focus.

## Principles

- Preserve the user's place and the screen that launched an action.
- Back navigation follows the existing hierarchy without surprising jumps.
- Focus continuity supports navigation; it does not redefine the navigation stack.
- Keep browsing and playback predictable with native SwiftUI/UIKit interaction.
- Treat Jellyfin user data as the authority for watched/progress state.
- Keep Screen-specific TV changes from silently changing the retained iOS client.

## Behavior contracts

| Experience | Specification |
| --- | --- |
| Hierarchy and Back | [Navigation](product-specs/navigation.md) |
| Browsing entry point | [Home](product-specs/home.md) |
| TV Show Details | [TV Show Details](product-specs/show-details.md) |
| Episode context/actions | [Episode Details](product-specs/episode-details.md) |
| Starting/stopping media | [Playback](product-specs/playback.md) |
| Episode transition | [Play Next](product-specs/play-next.md) |
| Resume and next episodes | [Continue Watching](product-specs/continue-watching.md) |
| App UI typography | [App font](product-specs/app-font.md) |
| Returning to content | [Focus restoration](product-specs/focus-restoration.md) |

These specs distinguish explicit direction from implementation-derived behavior.
Implementation-derived details are provisional descriptions, not independently
approved product requirements. Preserve them outside the task's scope; do not treat
them as authority over explicit product direction.
They are not proof that every flow has been validated on Apple TV.
Implementation maps belong in [ARCHITECTURE.md](../ARCHITECTURE.md) and
[design docs](design-docs/); global visual conventions are in [DESIGN.md](DESIGN.md).
