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

On the Info section, Down hands focus to Restart Episode and Up returns focus to Info.
Restart Episode uses Screen's semantic secondary-action appearance and retains a clear
focused state; its enabled state follows whether the action is available.

The custom tvOS HUD keeps episode/title metadata at the lower left. Its primary
transport is the progress bar, with a small Play/Pause status symbol immediately to
its left in the same horizontal row. The symbol shows Play while paused and Pause while
playing; it is display-only and never receives focus or input. Elapsed and remaining
time stay with the bar and use the same current time and duration as its fill and
playhead. The HUD uses Screen's square geometry and selected accent for active progress
and focus, over the existing dimmed video and gradient. When the HUD appears, the
progress bar receives initial focus. Select on the focused bar toggles playback when
idle and commits a pending directional seek. Left/Right adjusts the pending seek
position. While the HUD is hidden during seekable video playback, a horizontal Siri
Remote touch-surface swipe begins scrubbing immediately, reveals the seek timeline, and
shows the pending position during the gesture without requiring Select or prior focus
on the progress bar. When the HUD is visible, a horizontal pan on the slider continues
scrubbing while the progress bar is focused. The player container owns Siri Remote pan
recognition in both HUD states; the progress slider's own pan recognizer stays disabled
so one gesture cannot be consumed twice. Each update applies the translation since the
previous update to the pending position, and every new swipe starts from the current
position, so consecutive swipes continue from the prior committed seek. A horizontal
intent classifier uses velocity when decisive and translation as a fallback; vertical
swipes remain available to the Up/Down navigation handlers. Both pan paths commit
automatically when the gesture ends. Targets are clamped to the valid runtime, and VLC
targets also stay at least one millisecond before the shorter reported media length or
runtime. Scrubbing is unavailable for live or loading media and while another player
surface or presented child owns interaction. Back cancels a pending seek before hiding
the HUD. The HUD has no Rewind, Forward, Previous Episode, or Next Episode buttons.

Up from the hidden HUD reveals the HUD only. Up from the visible HUD opens a separate
Episodes shelf for episode playback while video continues behind it. The currently
playing episode is highlighted; selecting an episode uses the existing queue
selection and `playNewItem` path. Episode navigation exists only in this Up Episodes
surface. Back closes Episodes and restores the playback HUD. Back from the HUD hides
it; only a subsequent Back follows the existing player-exit behavior. The Info
supplement is available through the dropdown and is not opened by swiping Up. Episodes
is not a dropdown section or a HUD button. Down continues to open the playback
dropdown, whose Up/Back behavior above remains unchanged.
Episode cards keep 16:9 artwork and size vertically to their metadata; season/episode
and duration labels reserve their rows so missing values do not shift neighboring
cards' title or runtime alignment.

**Physical Apple TV report (2026-11-04).** Jamie reports that the current physical and
UI regression checks pass for hidden-HUD and focused-progress scrubbing, playback
navigation, overlay presentation, Restart Episode styling, episode-card layout, and
focus handoffs. This report covers those checked paths; no automated tests or build
were run as part of this documentation checkpoint.

The dropdown's Quality, Audio, and Subtitles controls show their current item/player
selection as the primary value and the setting name below it. They reuse the existing
selection bindings and picker actions. Technical Details groups existing playback,
video, audio, source, and session diagnostics without changing session or progress
reporting.
