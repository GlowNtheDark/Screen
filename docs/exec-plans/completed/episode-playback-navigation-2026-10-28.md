# Episode playback and navigation regressions

Status: user-reported Apple TV Simulator regression checks passed on 2026-10-28.

## Resolved regressions

- **Episode artwork playback after repeated player dismissal:** 15 consecutive playback cycles launched from episode artwork while staying in Show Details. Each completed fullscreen player released its registered presentation; the following activation created a fresh player directly from Show Details. The presentation lifecycle is owned by `NavigationCoordinator` and `NavigationInjectionView`: the disappearing cover records its `PresentedRoute`, and fullscreen `onDismiss` clears the route only when the registered destination coordinator is the same object. A stale completion cannot clear a newer presentation. `PresentedRoute.notifyWillDismiss()` preserves one-time dismissal callback behavior.
- **Episodes Back exiting playback:** SwiftUI `onExitCommand` dismissed Episodes without exiting the player.
- **Player Back and origin restoration:** Normal player Back returned to Show Details, and Show Details → Home restored the expected Home focus.

The user reported all five latest Simulator regression checks passing. The 15-cycle result and the three additional behaviors above are recorded from that report; no new Simulator run or build was performed during commit preparation. See the [bug-burndown checkpoint](../bug-burndown.md#2026-10-28-episode-playback-and-back-regression-checkpoint).

## Still open

- Quality, Audio, Subtitles, and nested picker Back behavior need a dedicated regression run.
- English audio preference remains unresolved.
- The Next Episode countdown ring remains unresolved.
- Other route/focus cases marked unverified in the bug-burndown register retain their existing status.

## Source areas

- Fullscreen presentation ownership and cleanup: `Shared/Coordinators/Navigation/NavigationCoordinator.swift`, `Shared/Coordinators/Navigation/NavigationInjectionView.swift`, and `Shared/Coordinators/Navigation/Router.swift`.
- Episode route, player lifecycle, and Episodes Back handling: `Shared/Views/ItemView/Components/PlayButton.swift`, `Shared/Views/VideoPlayer/VideoPlayer.swift`, `Shared/Views/VideoPlayer/VideoPlayerContainerView/VideoPlayerContainerView.swift`, and `Screen tvOS/Views/VideoPlayer/PlaybackControls/PlaybackControls+Episodes.swift`.

## Verification limits

No physical Apple TV result is claimed. Commit preparation does not repeat the Simulator regression; runtime evidence above is user-reported. Quality/audio/subtitle/picker dismissal, English audio selection, and the countdown ring remain outstanding.
