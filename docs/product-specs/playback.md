# Playback

Status: explicit dismissal direction and existing playback capabilities.

Start the selected item with the chosen source and available resume position, or
from zero when explicitly requested. Preserve existing pause, seek, stream settings,
queue, and error handling unless the task changes them.

Dismissal returns to the launching screen under the [navigation contract](navigation.md).
Stopping playback does not itself authorize a Home navigation reset. Preserve genuine
direct-play origins as well as details-origin playback.

Report progress/stop state to Jellyfin and use returned user data for watched state;
a high local percentage is not the definition of watched. The
[Play Next contract](play-next.md) governs the near-end experience. Natural-end
queue autoplay and credits-driven transitions are distinct paths today.

The app has custom VLC and native AVPlayer presentation paths. Do not assume feature
parity or identical dismissal mechanics; see [lifecycle and limits](../design-docs/playback-lifecycle.md).

The custom tvOS player exposes a playback dropdown over the continuing video. Down
opens it; its top-level sections are Info, Playback Settings, and Technical Details.
Playback Settings contains Quality, Audio, and Subtitles. Up from a setting restores
focus to the section row, and Up from that row closes the dropdown. Back/Menu first
dismisses an open selection popover; at the dropdown root it closes the dropdown.
Only a later Back applies the existing player-exit behavior. Opening or browsing the
dropdown does not change playback, session, or progress semantics. Credits and Play
Next remain a separate playback state. Entering the background cancels an active
next-episode countdown and retains the manual Play Next choice; returning to the app
does not restart the countdown. The native AVPlayer path is unchanged.

The custom tvOS HUD keeps episode/title metadata at the lower left. Its primary
transport is the progress bar, with a small Play/Pause status symbol immediately to
its left in the same horizontal row. The symbol shows Play while paused and Pause while
playing; it is display-only and never receives focus or input. Elapsed and remaining
time stay with the bar and use the same current time and duration as its fill and
playhead. The HUD uses Screen's square geometry and selected accent for active progress
and focus, over the existing dimmed video and gradient. When the HUD appears, the
progress bar receives initial focus. Select on the focused bar toggles playback when
idle and commits an active scrub. Left/Right adjusts the pending seek position, while
the slider's horizontal pan gesture continues to scrub continuously. The HUD has no
Rewind, Forward, Previous Episode, or Next Episode buttons.

Up from the hidden HUD reveals the HUD only. Up from the visible HUD opens a separate
Episodes shelf for episode playback while video continues behind it. The currently
playing episode is highlighted; selecting an episode uses the existing queue
selection and `playNewItem` path. Episode navigation exists only in this Up Episodes
surface. Back closes Episodes and restores the playback HUD. Back from the HUD hides
it; only a subsequent Back follows the existing player-exit behavior. The Info
supplement is available through the dropdown and is not opened by swiping Up. Episodes
is not a dropdown section or a HUD button. Down continues to open the playback
dropdown, whose Up/Back behavior above remains unchanged.

The dropdown's Quality, Audio, and Subtitles controls show their current item/player
selection as the primary value and the setting name below it. They reuse the existing
selection bindings and picker actions. Technical Details groups existing playback,
video, audio, source, and session diagnostics without changing session or progress
reporting.
