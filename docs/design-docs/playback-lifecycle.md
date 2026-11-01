# Playback lifecycle

Contracts: [playback](../product-specs/playback.md), [Play Next](../product-specs/play-next.md).

## Launch and ownership

[`PlayButton`](../../Shared/Views/ItemView/Components/PlayButton.swift) uses the details
provider's `MediaPlayerItemProvider`, optionally zeroing its start ticks for Play From
Beginning. Episodes receive an [`EpisodeMediaPlayerQueue`](../../Shared/Objects/MediaPlayerManager/Supplements/EpisodeMediaPlayerQueue.swift).
[`NavigationRoute+Media`](../../Shared/Coordinators/Navigation/NavigationRoute/NavigationRoute+Media.swift)
creates/registers a `MediaPlayerManager` and presents a full-screen player route.
The shim selects custom `VideoPlayer` or `NativeVideoPlayer` from the player preference.

[`MediaPlayerManager`](../../Shared/Objects/MediaPlayerManager/MediaPlayerManager.swift)
owns playback state, current item, supplements/queue, and a weak playback proxy.
The provider resolves server playback information into `MediaPlayerItem`; VLC/AV
proxies execute media operations. UI/container state lives separately in
[`VideoPlayerContainerState`](../../Shared/Objects/VideoPlayerContainerState.swift).

## Progress, replacement, and dismissal

[`MediaProgressObserver`](../../Shared/Objects/MediaPlayerManager/MediaProgressObserver.swift)
sends start, progress, and stop reports. Acknowledged TV progress/stop reports post refresh signals.
The manager captures outgoing seconds before stopping/replacing a proxy.
`playNewItemCompletingCurrent` explicitly marks the outgoing item played on Jellyfin
before replacement; ordinary `playNewItem` does not perform that mark request.
These are distinct existing paths, not permission to alter watched semantics.

The custom [`VideoPlayer`](../../Shared/Views/VideoPlayer/VideoPlayer.swift) dismisses
through its router on stopped only when `shouldSuppressStopDismissal` is false.
The TV container's `viewWillDisappear` sets this guard through
`onPresentationWillStopPlayback` before stopping the manager. This avoids a second
dismissal when presentation teardown already began; preserve the distinction when
tracing Back behavior. Its
[UIKit container](../../Shared/Views/VideoPlayer/VideoPlayerContainerView/VideoPlayerContainerView.swift)
handles remote controls, supplements, and exit behavior. Native playback has its own
presentation/disappearance stop handling in [`NativeVideoPlayer`](../../Shared/Components/NativeVideoPlayer.swift).
Do not equate disappearance with Home visibility; [navigation](navigation-stack.md)
and [focus](focus-system.md) own the return path.

On tvOS, the custom player's dropdown is composed in
[`PlaybackControls+Dropdown`](<../../Screen tvOS/Views/VideoPlayer/PlaybackControls/PlaybackControls+Dropdown.swift>)
over the existing player layer. Its settings reuse the existing quality, audio, and
subtitle action views; Info and Technical Details reuse the manager's media and
playback-information supplements. `VideoPlayerContainerState` owns dropdown visibility
and focus requests, while the UIKit container routes remote presses and guards the
full-screen presentation from dismissing on the same Menu press that closes either
custom surface. This surface does not own playback, session, progress, segment, or
queue state.

The UIKit container's tvOS upward-pan handling reveals a hidden HUD on the first swipe
and opens Episodes only when the HUD was already visible. It does not select the first
legacy supplement (Info). Menu dismissal closes dropdown, Episodes, then the normal
HUD before reaching the existing player-exit path.

The tvOS-only Episodes shelf is presented independently by the custom playback
controls from `VideoPlayerContainerState`; it is not a `selectedSupplement` and does
not share the dropdown's visibility/focus state. `EpisodeMediaPlayerQueue` supplies
the existing series/season paging model and selection provider. The shelf selects via
`MediaPlayerManager.playNewItem`, preserving the ordinary replacement and resume
behavior rather than the completion-marking Play Next path. Back closes the shelf
before the existing player dismissal handler can stop playback. The shelf neither
pauses playback nor reports progress itself.

## Segments and Play Next

[`ScreenPlaybackSegmentCoordinator`](../../Shared/Screen/PlaybackSegments/ScreenPlaybackSegmentCoordinator.swift)
fetches Jellyfin intro/outro segments, observes time crossings and queue resolution,
and owns skip/credits policy plus cancellable countdown state.
[`ScreenPlaybackSegmentOverlay`](../../Shared/Screen/PlaybackSegments/ScreenPlaybackSegmentOverlay.swift)
renders a scaled 1920×1080 TV layout with current/next panels, countdown, and a
Continue Watching shelf derived from `ResumeItemsLibrary`. Play Now is the intended
initial action focus; directional handling controls entry into the shelf.

Play Next calls `playNewItemCompletingCurrent`; selecting another Continue Watching
item calls `playNewItem`. Natural-end handling separately checks near-runtime completion
and the user's next-episode autoplay setting. Trace the relevant path rather than
assuming all transitions share one completion policy.

The segment overlay gives Skip Intro, Play Next, and Keep Watching their own focused
actions. Keep Watching closes the segment UI and leaves the current item playing;
Play Next retains the completion-marking replacement path above. Menu is handled by
the segment coordinator before the HUD/player stack: Back on intro dismisses only its
prompt, Back during countdown cancels the countdown and retains the choice, and a later
Back dismisses the remaining Play Next presentation. These dismissals restore HUD
Play/Pause focus. Continue Watching selection continues to use ordinary `playNewItem`.

The current candidate UI is implemented inside the custom player overlay today;
that implementation does not establish the final intended design.
The native player view does not attach that overlay. Product acceptance and backend
scope remain [review findings](../exec-plans/tech-debt.md), not bootstrap fixes.
