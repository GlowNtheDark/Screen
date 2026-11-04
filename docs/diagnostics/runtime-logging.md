# Runtime diagnostics on Apple TV

Screen writes event-driven diagnostics to Apple's unified logging system. The
subsystem is the installed app bundle identifier (currently `com.screen.tvos`)
and categories are `lifecycle`, `requests`, `playback`, and `playback.segments`.
Messages use stable `event=` names such as `scene.background`,
`status_refresh.failed`, `audio_session.activation_failed`, and
`countdown.canceled`. Durations use monotonic uptime. The `notice` and `error`
levels mark key lifecycle and failure events; `info` records supporting events.

## Live logs from a paired Apple TV

1. Pair/connect the Apple TV to the Mac in Xcode's **Window > Devices and
   Simulators** window.
2. Open the device console from that window, or open macOS **Console**, select
   the Apple TV in the sidebar, and start streaming.
3. Filter by process `Screen` or subsystem `com.screen.tvos`, then search for
   `event=` or a specific event name. For another installed build, use its
   bundle identifier as the subsystem.
4. Save/export the relevant console interval as soon as possible and record the
   incident time. A live Xcode debug console is not required for device logging.

Apple's [device-log guide](https://developer.apple.com/documentation/xcode/acquiring-crash-reports-and-diagnostic-logs)
explains access to device console logs. A practical Console filter is subsystem
`com.screen.tvos` plus message contains `event=`; narrow by category or an event
such as `countdown.canceled` when supported by the Console filter UI. The macOS
`log` command only queries the Mac or an explicitly supplied log archive; it
cannot be assumed to query an unattached Apple TV.

## Preserve diagnostics after an incident

Keep the Apple TV paired and connected, then use Xcode's device console or
Console to export logs promptly. If the incident needs broader system evidence,
open Apple's [Profiles and Logs for tvOS](https://developer.apple.com/feedback-assistant/profiles-and-logs/?platform=tvos) page, choose **Sysdiagnose for tvOS**, and follow its current trigger and transfer instructions for that hardware and tvOS release. Preserve the original archive unchanged with the exported Screen log interval. The instructions may require Apple Developer sign-in, and triggers/transfer steps can vary by Apple TV generation and software version; do not assume an iPhone button sequence applies. Include the approximate trigger time when sharing the archive.

Unified logging uses bounded system-managed storage. Older entries may have
rolled off, and debug/info visibility can depend on logging configuration and
retention. A sysdiagnose may not be available, may omit the needed time window,
or may require Apple/support tooling to inspect. Collect logs as soon as
possible; this app does not keep its own history or background logging service.

## Interpreting wake reports

- `scene.background` followed later by `app.foreground_return` and
  `player.foreground_transition` indicates Screen observed backgrounding and
  later returned to the foreground. It does not identify what woke the Apple TV.
- If `scene.background` is absent and Screen continues emitting foreground
  events while the TV was expected to sleep, the app may have remained active;
  the app log alone cannot prove display/sleep state. Correlate with system
  power, display, and wake records in the device log/sysdiagnose.
- `player.background_transition` records player and requested playback state.
  `player.pause_requested source=background` indicates Screen's configured
  background pause path ran. Playback may resume after an external wake only if
  the player state says it was already playing; this log does not prove audio
  or video output resumed.
- Compare timestamps across Screen, SpringBoard, and other system processes to
  distinguish an app foreground return from the system/device wake event.

## Incident notes

Record the Apple TV model/device, date and time with time zone, installed bundle
ID and Screen build/version, and whether playback resumed. Also note what the TV
was doing before the incident, the approximate time it was expected to sleep,
what input or external event preceded it, and when logs/sysdiagnose were
collected.
