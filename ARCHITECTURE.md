# Architecture

Source map inspected on 2026-09-14 against the working tree, including pre-existing
uncommitted changes. This is a code-level map, not evidence of a successful build or
runtime validation. Product contracts live in [docs/PRODUCT.md](docs/PRODUCT.md).

## Targets and layers

| Area | Ownership and entry points |
| --- | --- |
| tvOS app | [`Screen tvOS/App/ScreenApp.swift`](<Screen tvOS/App/ScreenApp.swift>) calls shared configuration, wraps authentication/toasts, and opens `RootView`. Xcode project: `Screen.xcodeproj`; scheme/target: `Screen tvOS`; product: `Screen.app`. |
| Bootstrap/session | [`Shared/Coordinators/Root/`](Shared/Coordinators/Root/) initializes storage/preferences; `UserSessionRootView` switches sign-in and tab content. [`UserSessionManager.swift`](Shared/Services/UserSession/UserSessionManager.swift) owns the current session. |
| Navigation | [`Shared/Coordinators/Tabs/`](Shared/Coordinators/Tabs/) owns tab selection and one coordinator per tab. [`Shared/Coordinators/Navigation/`](Shared/Coordinators/Navigation/) owns route paths and nested presentations. |
| Screen composition | [`Shared/Views/`](Shared/Views/) and [`Shared/Components/`](Shared/Components/) compose content groups, details, libraries, search, and reusable controls; [`Screen tvOS/`](<Screen tvOS/>) provides TV-specific UI. |
| Data presentation | [`ContentGroupViewModel`](Shared/ViewModels/ContentGroupViewModel/ContentGroupViewModel.swift) resolves groups; [`PagingLibraryViewModel`](Shared/Objects/PagingLibrary/PagingLibraryViewModel.swift) owns loaded pages. [`Shared/Objects/Libraries/`](Shared/Objects/Libraries/) builds server queries. |
| Playback | [`MediaPlayerManager`](Shared/Objects/MediaPlayerManager/MediaPlayerManager.swift) owns playback state, item replacement, queue, and proxy. [`Shared/Views/VideoPlayer/`](Shared/Views/VideoPlayer/) owns custom controls/container; [`NativeVideoPlayer`](Shared/Components/NativeVideoPlayer.swift) wraps AVPlayerViewController. |
| Services/persistence | [`Shared/Services/`](Shared/Services/) owns session networking, sockets, notifications, keychain, defaults and downloads. [`Shared/ScreenStore/`](Shared/ScreenStore/) owns versioned CoreStore/SQLite data and stored preferences. |
| Top Shelf | [`ScreenTopShelfSnapshotWriter`](<Screen tvOS/Services/ScreenTopShelfSnapshotWriter.swift>) writes Continue Watching data/artwork; [`ContentProvider`](<Screen Top Shelf/ContentProvider.swift>) reads the app-group snapshot for TV Services. |
| Other targets/tooling | [`Screen/`](Screen/) retains iOS UI. [`PreferencesView/`](PreferencesView/) is a local package. [`Scripts/`](Scripts/), [`fastlane/`](fastlane/), and [CI](.github/workflows/ci.yml) support builds; [`Resources/`](Resources/) and [`Translations/`](Translations/) hold assets/localization. |

## Representative flows

- Startup: app configuration → authentication wrapper → `RootView`/`RootCoordinator`
  → store initialization → `UserSessionRootView` → `MainTabView`.
- Home: `DefaultContentGroupProvider` → content-group view models → paging libraries
  → `UserSession.client` → Jellyfin DTOs → rows/poster buttons.
- Episode: Home's `CinematicSelectionContentGroup` routes `.item` → `ItemView`
  owns an `ItemContentGroupProvider` → `PlayButton` creates an episode queue and
  `.videoPlayer` route → manager → selected player/proxy.
- Return: player stop/dismissal affects its presenting coordinator; `MainTabView`
  observes Home/details presentations while `FocusCoordinator` waits for the
  appropriate dismissal, refreshed row manifests, and a ready tile.

## State and feature ownership

| Concern | Start here |
| --- | --- |
| Navigation stack vs presentation | [Navigation design](docs/design-docs/navigation-stack.md) |
| Home focus restoration | [`FocusCoordinator.swift`](Shared/Objects/FocusCoordinator.swift), [`MainTabView.swift`](Shared/Coordinators/Tabs/MainTabView.swift), [`ContentGroupView.swift`](Shared/Views/ContentGroupView.swift); [focus design](docs/design-docs/focus-system.md) |
| Watched/progress | Jellyfin `BaseItemDto.userData` (`UserItemDataDto`); [`PosterIndicatorsOverlay.swift`](Shared/Components/PosterIndicators/PosterIndicatorsOverlay.swift), [`BaseItemDto.swift`](Shared/Extensions/JellyfinAPI/BaseItemDto/BaseItemDto.swift), [`MediaProgressObserver.swift`](Shared/Objects/MediaPlayerManager/MediaProgressObserver.swift) |
| Continue Watching derivation | [`ResumeItemsLibrary.swift`](Shared/Objects/Libraries/ResumeItemsLibrary.swift); TV presentation/dedup in [`CinematicSelectionContentGroup.swift`](<Screen tvOS/Objects/CinematicSelectionContentGroup.swift>) |
| Play Next | [`Shared/Screen/PlaybackSegments/`](Shared/Screen/PlaybackSegments/) owns segment policy/presentation; [`EpisodeMediaPlayerQueue.swift`](Shared/Objects/MediaPlayerManager/Supplements/EpisodeMediaPlayerQueue.swift) resolves adjacent episodes; [lifecycle](docs/design-docs/playback-lifecycle.md) |
| Model/service propagation | [State management](docs/design-docs/state-management.md) |

## Models and dependencies

JellyfinAPI supplies `BaseItemDto`, `UserItemDataDto`, `MediaSourceInfo`, and segment DTOs.
Local `ServerState`/`UserState` map persisted session data. `MediaPlayerItemProvider`
builds a playable `MediaPlayerItem`; `NavigationRoute` describes a destination and
transition; `HomeTile` identifies a focus origin by group/item/series/index.

Key dependencies in [the project](Screen.xcodeproj/project.pbxproj) include
JellyfinAPI, FactoryKit (injection), StatefulMacros (action/state machinery),
CoreStore, Defaults, KeychainSwift, Nuke (images), Pulse (logging), CollectionHStack/
CollectionVGrid (collections), Transmission (presentation), and VLCUI.
[Cartfile](Cartfile) pins MobileVLCKit/TVVLCKit; AVKit provides native playback.
Use the checked-in package resolutions and [quality guide](docs/QUALITY.md), not
this map, to diagnose a particular dependency/build failure.

## Existing information and limits

[README](README.md), [contributing](Documentation/contributing.md),
[player capabilities](Documentation/players.md), and [library support](Documentation/libraries.md)
retain upstream Swiftfin context. Their branding, design guidance, capability claims,
and setup assumptions are not automatically current Screen contracts.
The [Screen roadmap](Documentation/Screen-UI-Roadmap.md) preserves design direction,
but unchecked phases are not a reliable inventory: dynamic Top Shelf already has code.
Specific observed disagreements and review needs are in [tech debt](docs/exec-plans/tech-debt.md).
