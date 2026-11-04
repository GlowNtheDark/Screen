# Screen bug-burn-down register

Audit date: 2026-10-10
Scope: Final runtime verification of outstanding Home state, Search, playback focus/layering, presentation, and regression gaps after the A01/A02, B01, A03, and F06 checkpoints; prior evidence is retained.
Original audit baseline: `8da2e06b1935bb7fa86b2b08a0705acf6d1dea2f` on `codex/phase1-shared-item-state`. B01 follow-up started from `aba7494196f8be6dba4a32542d3b00b4fc609776` on the same branch and was checkpointed before the current verification.
Runtime target: Apple TV 4K (3rd generation), 1080p, tvOS 27.0 simulator. No physical Apple TV was used.

## Executive summary

The 26 initial register items plus one newly discovered Episodes boundary case were reviewed: **0 confirmed open bugs**, **13 runtime passes**, **8 source-verified cases with runtime coverage still incomplete**, **1 previously reported issue not reproduced**, **4 unverified cases**, and **1 blocked case**. No P0 was found. A01, A02, A03, B01, and F06 pass their focused simulator acceptance paths; this verification added partial Home, Episodes, and navigation evidence but did not close the remaining server-state, request-failure, EPG, subtitle, or full focus-matrix gaps.

**A01/A02 remediation:** both failures shared the outer Menu/Back delivery path, while the coordinator's Intro and credits transitions remain distinct. The corrected simulator runs confirm a single Back press is consumed by the active segment layer; details are recorded below.

HUD metadata root cause and current behavior: `HUDMetadata` receives the current `MediaPlayerManager.item`. Jellyfin's episode `name` is already available there. Before the fix, the HUD bottom line selected `BaseItemDto.episodeLocator` instead of the DTO's `displayTitle`/`name`; `episodeLocator` locally formats `indexNumber` as `Episode N`. `seasonEpisodeLabel` separately supplies `Sx:Ey`. No additional metadata request was needed. The current HUD title selection trims `item.name`, rejects blank text and the locally synthesized locator, then uses the localized locator as fallback; the top series line and `Sx:Ey` are retained. Both metadata lines are single-line. See [HUDMetadata](<../../Screen tvOS/Views/VideoPlayer/PlaybackControls/PlaybackControls+HUD.swift:19>) and [episode labels](<../../Shared/Extensions/JellyfinAPI/BaseItemDto/BaseItemDto.swift:34>).

Current evidence does **not** establish a known-bug-free baseline. Membership/focus behavior, a controlled Search request failure, EPG geometry, and several boundaries still need the checks below. The A01/A02 remediation was signed-built and installed on the specified simulator; the temporary credits setting was restored to Show Next Episode with its original 10-second duration.

### Classification counts

| Status | Count | IDs |
| --- | ---: | --- |
| CONFIRMED BUG | 0 | — |
| PASS | 13 | A01, A02, A03, A04, A05, B01, C02, D01, D03, E03, F01, F03, F06 |
| SOURCE VERIFIED | 8 | B02-B07, E02, F02 |
| NOT REPRODUCED | 1 | C01 |
| UNVERIFIED | 4 | B08, D02, F04, F05 |
| BLOCKED | 1 | E01 |

Severity describes the impact if a behavior regresses, not its current status. Across the 27 tracked items: **16 P1, 10 P2, 1 P3, 0 P0**. Confirmed open bugs: **0**.

## Confirmed bug reports and dispositions

### A03 — Up Episodes can reopen focused on the season selector

- **Subsystem / severity / status:** Playback Episodes focus restoration; P1; **PASS**.
- **Reproduction:** On the 2026-09-28 simulator run, select S2:E1 from Season 2, close Episodes, then reopen it and press Right once.
- **Expected:** Reopening selects the current playing season and focuses the current episode card (S2:E1); Right then advances within that episode shelf.
- **Observed / evidence:** The original Right-to-Season-3 reproduction passed on the signed Apple TV 4K (3rd generation), 1080p, tvOS 27.0 simulator after the fix. Same-season S3:E11 and cross-season S2:E1 reopens focused the currently playing card; selecting S2:E2 started it and the next reopen focused S2:E2. In this final verification, S2:E2 reopened focused; changing the selector to Season 1 and pressing Down focused S1:E1 because S2:E2 is absent there; Left at S1:E1 retained that boundary. Back closed Episodes to the HUD, then separate presses hid the HUD and returned to the original Details route. No corrective jump occurred. Slow-loading acquisition was not stress-tested because cached season data loaded quickly.
- **Root cause / fix:** The shelf's old `focus(_:)` scrolled and assigned `focusedTarget` before the matching episode Button registered. After season/item replacement, the default-focus request could target a candidate that did not yet exist, leaving focus with the selector. The shelf now waits for the target card's `onAppear` registration and issues one deduplicated focus request. During acquisition, only the requested card is an eligible episode Button and season chips are non-focusable. Episodes directional input is consumed at the player press-event owner and converted into a unique move request; the surface applies one-step movement and clamps boundaries instead of competing with native spatial focus.
- **References:** [tech-debt evidence](tech-debt.md#deferred-findings-and-review-needs), [Episodes contract](../design-docs/focus-navigation-contract.md#up-episodes-surface), lines 466-480, and [playback focus notes](../design-docs/focus-system.md).
- **Dependencies / blocker:** None for the verified simulator paths. A truly missing episode uses the first eligible card; this is source-reviewed, while the cross-season fallback to S2:E1 was runtime-tested.
- **Next action:** Keep the cross-season reopen, missing-current-season fallback, directional boundaries, and Episodes Back path in the playback regression checklist.

### B01 — Sidebar return restores the remembered Home tile

- **Subsystem / severity / status:** Home/sidebar focus acquisition; P1; **PASS**.
- **Original reproduction / pre-fix evidence:** Focus the first tile in Home's Recently Added TV Shows row (The Secret Lives of Mormon Wives), press Left to enter the Home sidebar, then press Right once. The pre-fix simulator returned to Continue Watching S3:E10 instead of the remembered tile, reproducing the earlier sidebar-entry timing report.
- **Expected:** Sidebar return restores the last valid Home tile, reveals it if its shelf is horizontally scrolled, preserves initial Home launch focus, and performs one transition without a delayed corrective jump.
- **Corrected runtime evidence:** On the Apple TV 4K (3rd generation), 1080p, tvOS 27.0 simulator, the original Left/Right path restored The Secret Lives of Mormon Wives. Repeating the return with Select also restored it. Returning from Circle in Recently Added Movies restored Circle; returning from Coyote vs. Acme with the Movies shelf horizontally scrolled restored that exact tile and kept the scroll offset. After sidebar return, Up to Circle then Down restored the exact Secret Lives tile. Opening the series Details from that tile and pressing Back returned to it. Initial Home entry focused Futurama, the first Continue Watching candidate. Each sampled press produced one visible transition, and no later first-tile jump was observed.
- **Root cause / fix:** `FocusCoordinator` kept only the currently focused Home tile, which was cleared as focus moved to the sidebar. The root-tab repeat path then requested the first Home group, while each row's high-priority `defaultFocus` could reacquire its first poster after restoration. Home now retains the last semantic tile, resolves exact item then nearest same-row then first available fallback, reveals the target row/cell, and waits for the sidebar to relinquish focus before requesting it. The exact-target path skips the competing generic root request, invalidates stale focus requests, and keeps row default focus suppressed after the remembered tile is acquired. Initial Home entry still uses its original first-candidate request.
- **References:** [Home focus ownership](<../../Shared/Objects/FocusCoordinator.swift:32>), [sidebar activation](<../../Shared/Coordinators/Tabs/MainTabView.swift:135>), [Home initial/root focus](<../../Shared/Views/ContentGroupView.swift:61>), [row default focus](<../../Shared/Components/PosterHStackLibrarySection.swift:87>), [focus contract](../design-docs/focus-navigation-contract.md#root-and-launch), lines 145-156 and 547.
- **Dependencies / blocker:** No blocker for the verified simulator paths. Physical Apple TV behavior was not tested, as requested.
- **Next action:** Keep B01 in the sidebar/Home regression checklist; include Right and Select, an offscreen shelf target, Home vertical reverse, and Details return after future focus changes.

## Previously reported bugs not reproduced

### C01 — Video Player Type menu loses its row focus after Back

- **Subsystem / severity / status:** Settings/native menu focus; P1; **NOT REPRODUCED**.
- **Reproduction:** In Settings, focus Video Player Type, Select to open its Native/Screen menu, press Back, inspect the invoking row, then Select once.
- **Expected:** Back dismisses only the menu, the original row is visibly focused, and one Select immediately reopens the menu.
- **Observed / evidence:** In this audit, Back closed the native menu with Video Player Type visibly highlighted. One Select immediately reopened it with Native focused and Screen still selected. No delayed corrective jump was observed.
- **References:** [ListRowMenu](<../../Screen tvOS/Components/ListRowMenu.swift:86>), [focus contract Settings row](../design-docs/focus-navigation-contract.md#settings-root-and-nested-settings), lines 271-281.
- **Dependencies / blocker:** tvOS 27.0 simulator only; native form behavior may vary by OS/device.
- **Next action:** Retain as not reproduced, not fixed. Repeat on physical Apple TV when testing a Settings/menu change.

## Runtime passes

### A01 — Intro overlay Back dismisses only the prompt

- **Subsystem / severity / status:** Playback Back ownership; P1; **PASS**.
- **Reproduction:** On the corrected build, play Futurama S10:E4, “The Numberland Gap”, wait for its active Skip Intro prompt, confirm the action is available, then press Back once.
- **Expected:** Dismiss only the Intro prompt, keep the same playback active, and do not seek.
- **Observed / evidence:** The prompt disappeared and the same player returned to its HUD over the continuing episode at about 0:23. The player did not exit or jump to the intro boundary. A later Skip Intro Select check still sought forward and left playback running.
- **Root cause / fix:** The segment overlay was a SwiftUI sibling outside the UIKit player container, so the focused overlay's Menu/Back could bypass the container's Menu owner and dismiss the player presentation. The presentation publisher also emits its new value before storage; the old subscriber discarded that value and reread stale `presentation`, leaving the full-screen presentation dismissible. The overlay is now hosted inside the UIKit container, Menu is consumed once there, and dismissibility uses the emitted presentation value.
- **References:** [player press ownership](<../../Shared/Views/VideoPlayer/VideoPlayerContainerView/VideoPlayerContainerView.swift:1003>), [segment Back transitions](<../../Shared/Screen/PlaybackSegments/ScreenPlaybackSegmentCoordinator.swift:163>), [presentation dismissibility](<../../Shared/Views/VideoPlayer/VideoPlayer.swift:94>), [focus contract](../design-docs/focus-navigation-contract.md#intro-credits-and-play-next).
- **Next action:** Keep A01 in the playback Back regression checklist; no additional fix remains for this register item.

### A02 — Credits countdown Back cancels before dismissing

- **Subsystem / severity / status:** Playback Back ownership; P1; **PASS**.
- **Reproduction:** Temporarily set Credits / Outro to Countdown + Autoplay, reach Futurama S10:E4's Up Next countdown, then press Back once and again.
- **Expected:** The first Back cancels only the countdown and retains both choices; a later Back dismisses the choice to the HUD without exiting playback.
- **Observed / evidence:** First Back replaced the countdown with `AUTOPLAY CANCELLED` while keeping Keep Watching and Play Next visible. Second Back dismissed that presentation and returned to the same S10:E4 HUD/video near 24:14. Neither press exited the player. The temporary setting was restored afterward.
- **Root cause / fix:** A02 shared A01's outer event-delivery and stale-presentation-dismissibility defect. The coordinator's transitions remain separate: countdown Back cancels and retains the next-episode choice; a later Back dismisses that choice. The UIKit container consumes each press before player dismissal and suppresses the paired Menu-ended phase after handling at press-began.
- **References:** [player press ownership](<../../Shared/Views/VideoPlayer/VideoPlayerContainerView/VideoPlayerContainerView.swift:1003>), [countdown and choice transitions](<../../Shared/Screen/PlaybackSegments/ScreenPlaybackSegmentCoordinator.swift:166>), [focus contract](../design-docs/focus-navigation-contract.md#intro-credits-and-play-next).
- **Next action:** Keep A02 in the playback Back regression checklist; no additional fix remains for this register item.

### A04 — Player → Details → Home exact tile restoration

- **Subsystem / severity / status:** Playback route and Home restoration; P1; **PASS**.
- **Reproduction:** From the existing Home Continue item, resume its episode, then Back through the visible HUD/player to Episode Details and Back to Home.
- **Expected:** Each Back dismisses one layer; the player returns to its Details route, then Home restores the exact originating tile.
- **Observed / evidence:** HUD/player dismissal and Details return were separate; the next Back returned Home with the same S3:E10 Continue tile visibly focused. No premature Home restoration occurred.
- **References:** [navigation contract](../product-specs/navigation.md), [player return contract](../design-docs/focus-navigation-contract.md#player-dismissal-and-return-focus), lines 525-537.
- **Dependencies / blocker:** One direct Continue-origin episode route tested; this does not cover every deeper Details/shelf route.
- **Next action:** Keep the exact Details and Home return in the navigation regression checklist.

### A05 — Movie Details Play / Replay action restoration

- **Subsystem / severity / status:** Movie Details action focus; P1; **PASS**.
- **Reproduction:** From Movie Details for the already-watched “Wuthering Heights”, start Play, Back through the player HUD to Details, then focus Replay, start it, and return the same way.
- **Expected:** Play returns with Play focused; Replay/Play From Beginning returns with that action focused. If Replay is unavailable, fall back to Play.
- **Observed / evidence:** The first Details return highlighted Play. Replay was selectable, started at 0:00, and after return the Replay action had the focus outline. Movie Details continued to show Watched. The no-Replay fallback was source-reviewed only.
- **References:** [focus contract Details actions](../design-docs/focus-navigation-contract.md#details-screens-and-nested-shelves), lines 297-313; [navigation implementation](../design-docs/navigation-stack.md).
- **Dependencies / blocker:** Fallback when Replay is unavailable was not encountered in this Movie's metadata.
- **Next action:** Preserve the return target and retain a separate regression case for the unavailable-Replay fallback.

### C02 — App Font dismissal and selection return focus

- **Subsystem / severity / status:** Settings custom menu focus; P2; **PASS**.
- **Reproduction:** Open App Font, Back; reopen and select another option; Select once to reopen.
- **Expected:** Back and selection return focus to App Font; the next Select reopens with no delayed focus jump.
- **Observed / evidence:** Both dismissal paths visibly restored App Font. One Select reopened the menu. Serif was selected temporarily and then Rounded was restored, its original value.
- **References:** [App Font row/menu](<../../Shared/Views/SettingsView/SettingsView.swift:256>), [focus contract Settings](../design-docs/focus-navigation-contract.md#settings-root-and-nested-settings), lines 273-275.
- **Dependencies / blocker:** None in this simulator scenario.
- **Next action:** Keep the immediate reopen and no-delayed-jump case in the Settings regression checklist.

### D01 — Search no-results focus stays in the input region

- **Subsystem / severity / status:** Search focus; P2; **PASS**.
- **Reproduction:** Enter a query with no matching results, focus the first on-screen key, then press Down; also test Down from the search field.
- **Expected:** With no results, focus alternates between input field and keyboard rather than entering empty result content.
- **Observed / evidence:** “No Results” was shown; Down from the first key focused the field, and Down from the field focused the first key. Left from the first key entered the sidebar once. The Device Hub keyboard capture produced `aaaaa` instead of the intended synthetic query; this was a harness input issue, not a product defect.
- **References:** [Search focus routing](<../../Shared/Views/SearchView.swift:86>), [contract Search](../design-docs/focus-navigation-contract.md#search), lines 232-249.
- **Dependencies / blocker:** No matching results were available for this query; controlled request failure is tracked separately as D02.
- **Next action:** Retain no-results input/keyboard alternation in the Search regression checklist.

### D03 — Search result Details return and favorite update

- **Subsystem / severity / status:** Search result focus/state; P1; **PASS**.
- **Reproduction:** Use the existing 2026-10-08 simulator evidence: open an Arcane Search result's Details, change Favorite, return with Back.
- **Expected:** One Back returns to the same Search result, and accepted watched/favorite presentation updates are visible without reopening Search.
- **Observed / evidence:** The same Arcane result returned focused with its updated favorite badge. The audit did not repeat this mutation. Search retains local query/results while result cards observe shared item state.
- **References:** [state-management runtime evidence](../design-docs/state-management.md#migration-coverage-and-remaining-scope), lines 318-326; [Search focus contract](../design-docs/focus-navigation-contract.md#search), lines 237-249.
- **Dependencies / blocker:** Recent simulator evidence covers Favorite; a Search-specific watched mutation was not separately captured.
- **Next action:** Keep exact result and favorite update in the Search regression checklist; add watched-state coverage when a safe test item is available.

### E03 — Episode title, locator, series, fallback, and Movie HUD

- **Subsystem / severity / status:** Playback HUD metadata; P2; **PASS**.
- **Reproduction:** Resume The Secret Lives of Mormon Wives S3:E10 and show the HUD; separately start the Movie “Wuthering Heights”.
- **Expected:** Episode HUD shows S3:E10, series title, and Jellyfin episode title. `Episode N` is fallback only. Movie metadata remains unchanged.
- **Observed / evidence:** The episode HUD showed `S3:E10`, `The Secret Lives of Mormon Wives`, and `The Book of Enlightenment`; no generic `Episode 10` appeared. That title fit on one line at 1080p without colliding with controls/progress/timestamps. Movie playback showed only `"Wuthering Heights"` with its time/progress display and no episode locator. The missing/blank-title fallback is source-reviewed, not runtime-fed.
- **References:** [HUD title selection](<../../Screen tvOS/Views/VideoPlayer/PlaybackControls/PlaybackControls+HUD.swift:19>), [localized fallback and Sx:Ey](<../../Shared/Extensions/JellyfinAPI/BaseItemDto/BaseItemDto.swift:134>), [metadata state ownership](../design-docs/state-management.md).
- **Dependencies / blocker:** Simulator had no blank-title episode. Only the observed title length was visually measured; no additional long-title sample was needed for the audit matrix.
- **Next action:** Retain this episode and Movie pair as a regression check. If a blank-title episode becomes available, verify localized fallback runtime.

### F01 — Representative exact restoration through Home, libraries, and Search

- **Subsystem / severity / status:** Route/focus restoration; P1; **PASS**.
- **Reproduction:** Use the 2026-10-08 signed simulator checks for Movies poster → Details → Back, TV Shows poster → Details → Back, and Search result → Details → Back; Home direct-to-Details route was also exercised in this audit.
- **Expected:** One Back dismisses the child and returns focus to the exact originating item in its still-visible parent.
- **Observed / evidence:** Movies, TV Shows, Search, and the current Home Continue route returned to their exact originating item in one route-level Back. The current episode player first hid its HUD, then returned to Details, then Home and its original Continue item.
- **References:** [state-management runtime evidence](../design-docs/state-management.md), lines 418-425; [navigation contract](../product-specs/navigation.md).
- **Dependencies / blocker:** Prior evidence is from the installed simulator app; not every nested shelf/action route was included.
- **Next action:** Keep representative exact-return flows in navigation regression checks; treat B01's sidebar entry separately.

### F03 — Representative remote presses produce one transition

- **Subsystem / severity / status:** tvOS remote navigation; P1; **PASS**.
- **Reproduction:** During this audit, test Home row Down/Up and Left/Right, Search no-results Down, Settings menu Select/Back, Episodes open/Back, and player/Details/Home Back one press at a time.
- **Expected:** One remote press produces at most one region/route transition and no delayed corrective jump.
- **Observed / evidence:** The sampled presses produced one visible transition each. Immediate App Font reopen worked. The pre-fix Home Right result was one transition to the wrong tile (B01); the B01 follow-up restored exact targets through Right and Select without a delayed jump. This sample is not a claim that every app boundary was tested.
- **References:** [one-press contract](../design-docs/focus-navigation-contract.md#root-and-launch), lines 145-156 and 558-568; [Home vertical focus](../design-docs/focus-navigation-contract.md#home-and-shelves).
- **Dependencies / blocker:** Covers representative simulator paths only; hardware input remains untested.
- **Next action:** Recheck one-press ownership alongside each confirmed fix; do not infer full navigation coverage from this sample.

### F06 — Episodes directional focus can wrap at a shelf boundary

- **Subsystem / severity / status:** Playback Episodes focus boundaries; P1; **PASS**.
- **Reproduction:** During A03 simulator validation, focus the final S3:E11 card while S3:E11 is playing, then press Right once.
- **Expected:** The last eligible card retains focus; one press cannot wrap to a different card or change seasons.
- **Observed / evidence:** Before the retained press-owner change, Right wrapped from S3:E11 to the currently playing S2:E2 card. The final signed build routes all four Episodes directions through one player press-event owner and clamps movement at collection bounds. On the Apple TV 4K (3rd generation), 1080p, tvOS 27.0 simulator, Right at S3:E11 remained there; Left moved once to S3:E10. Left at the first S1 selector remained on Season 1; Right at the last selector remained on Season 5. Season3 Left selected Season2 once, and Down from Season2 focused the first eligible card S2:E1. Back layering remained Episodes → HUD → hidden HUD → Details.
- **Root cause / fix:** Episodes arrows previously fell through to native tvOS spatial movement while the surface also changed selected content from focus updates. Native geometry could wrap to a visible card. UIKit press delivery now consumes each directional press once; the Episodes surface applies one adjacent index move and keeps focus unchanged at either boundary.
- **References:** [Episodes directional contract](../design-docs/focus-navigation-contract.md#up-episodes-surface), [press handling](<../../Screen tvOS/Views/VideoPlayer/PlaybackControls/Components/PlaybackControls+PressHandling.swift:103>), [Episodes surface](<../../Screen tvOS/Views/VideoPlayer/PlaybackControls/PlaybackControls+Episodes.swift:245>).
- **Dependencies / blocker:** None for the tested simulator paths; physical Apple TV behavior was not requested or tested.
- **Next action:** Keep these first/last card and season-selector paths in the playback focus checklist.

## Source-verified; runtime verification remains incomplete

### B02 — Focused Home tile updates live

- **Subsystem / severity / status:** Home shared item state; P2; **SOURCE VERIFIED**.
- **Reproduction:** Final verification focused Futurama S10:E7 on Home, opened its Details, temporarily changed Favorite from off to on, and returned; then restored Favorite to off.
- **Expected:** Presentation updates in place, preserving tile identity and focus without a corrective jump.
- **Observed / evidence:** The Home tile displayed its heart badge after returning from Details, without a tab switch or manual refresh. Pressing Right then advanced from Futurama S10:E7 to NCIS, confirming Futurama had been the restoration origin. Favorite was toggled back off and the badge disappeared. This is a reversible poster-state and focus-return check, but it did not mutate state while Home remained visible/focused or test an unfocused visible tile; those live-update cases remain incomplete. Source sends accepted item updates through session-scoped `ItemState`; poster/tile presentation observes that state while collection identity stays local.
- **References:** [state-management ownership and migration](../design-docs/state-management.md#existing-propagation-and-current-stale-state-paths), lines 138-165 and 260-288.
- **Dependencies / blocker:** Favorite state was recorded as off and restored. A direct in-place update and an unfocused visible-tile update still need a server-accepted progress/state event; no separate test feed is configured.
- **Next action:** On a safe test item, verify one direct progress update on a focused tile and one update on an unfocused visible tile, preserving exact Home focus.

### B03 — Focused Continue item disappears and receives fallback focus

- **Subsystem / severity / status:** Home focus fallback; P1; **SOURCE VERIFIED**.
- **Reproduction:** Not performed in this audit; remove a currently focused Continue item through completion or a membership change.
- **Expected:** Focus resolves deterministically to the nearest valid tile in the original row, then the row's first tile, then the first valid Home tile.
- **Observed / evidence:** `FocusCoordinator.resolveHomeReturn` implements exact item → same-series replacement → nearest original-row tile → first available Home tile. Runtime membership disappearance/fallback was not tested.
- **References:** [focus fallback](<../../Shared/Objects/FocusCoordinator.swift:326>), [state-management Home invalidation](../design-docs/state-management.md#existing-propagation-and-current-stale-state-paths), lines 179-186.
- **Dependencies / blocker:** Not exercised in this pass. The available Continue entries are real Jellyfin user data, and no disposable item with a recorded/restorable watched and resume baseline was identified.
- **Next action:** Verify the fallback chain with test content, including when the exact item and then its row are absent.

### B04 — New Continue item appears after resume threshold

- **Subsystem / severity / status:** Continue membership refresh; P2; **SOURCE VERIFIED**.
- **Reproduction:** Not performed in this audit; start an item absent from Continue Watching and report progress past Jellyfin's resume threshold.
- **Expected:** Home re-queries affected Continue membership without manual refresh and adds the item in the right order.
- **Observed / evidence:** `ResumeItemsLibrary` requests membership refresh when positive playback ticks arrive for an item not already present; acknowledged updates carry item identity/revision and Home refresh is targeted. No absent-item threshold transition was tested.
- **References:** [ResumeItemsLibrary membership decision](<../../Shared/Objects/Libraries/ResumeItemsLibrary.swift:51>), [state-management Continue rules](../design-docs/state-management.md#continue-watching-and-refresh), lines 39-61 and 149-155.
- **Dependencies / blocker:** Not exercised in this pass. No disposable item absent from Continue with a restorable server baseline was identified; the resume threshold must be measured from acknowledged updates, not assumed.
- **Next action:** Record the item's pre-test membership and position, cross the server threshold, verify Home ordering, then restore the starting position/state.

### B05 — Existing Continue progress updates while its tile stays onscreen

- **Subsystem / severity / status:** Continue presentation state; P2; **SOURCE VERIFIED**.
- **Reproduction:** Not performed in this audit; leave an existing Continue tile onscreen and focused while acknowledged progress changes.
- **Expected:** Its label/bar update without hover, click, navigation, or manual refresh; focus identity remains stable.
- **Observed / evidence:** Typed progress ticks patch the same session item state and tvOS poster/card reads that state. Home progress presentation without an actual playback update is not proof of live refresh.
- **References:** [ItemState update](<../../Shared/Objects/ItemState.swift:34>), [PagingLibraryViewModel update](<../../Shared/Objects/PagingLibrary/PagingLibraryViewModel.swift:176>), [state-management](../design-docs/state-management.md#existing-propagation-and-current-stale-state-paths), lines 149-155.
- **Dependencies / blocker:** Not exercised in this pass; requires a disposable Continue item and an exact starting resume position so the server-backed progress mutation can be restored or accurately reported.
- **Next action:** Validate the visible focused tile with one small progress change, then restore or document the resulting resume position.

### B06 — Episode completion replaces Continue with Next Up

- **Subsystem / severity / status:** Playback completion/Home membership; P2; **SOURCE VERIFIED**.
- **Reproduction:** This audit did not complete an episode. Existing 2026-10-08 simulator evidence exercised a near-end Play Next transition, not the whole Home focus acceptance path.
- **Expected:** Finished item leaves or is replaced in Continue, correct Next Up item/order appears, and focus falls back deterministically.
- **Observed / evidence:** Existing runtime evidence says the finished episode became watched and Continue advanced to the next episode; it does not establish focused-Home-card disappearance and replacement behavior. Source uses targeted membership invalidation and revision guards.
- **References:** [state-management episode completion evidence](../design-docs/state-management.md#migration-coverage-and-remaining-scope), lines 298-313; [Continue membership rules](../design-docs/state-management.md#continue-watching-and-refresh), lines 41-61.
- **Dependencies / blocker:** Not exercised in this pass. Requires a disposable near-end episode, recorded Continue/Next Up state, and a restoration plan; no full episode was completed.
- **Next action:** Use an explicit near-end test item, capture before/after server and Home memberships, and verify focus on the replacement or deterministic fallback.

### B07 — Series Mark Unwatched propagates through loaded rows and Home

- **Subsystem / severity / status:** Episode watched state and Continue membership; P2; **SOURCE VERIFIED**.
- **Reproduction:** Not repeated in this audit. Existing 2026-10-08 runtime tested loaded Arcane episode/season rows and series Mark Unwatched.
- **Expected:** Loaded episode states and Continue membership update; unrelated shelves remain stable and Home needs no manual reload.
- **Observed / evidence:** Prior simulator evidence reports watched/progress indicators changed in loaded rows and Arcane was removed from Continue after reset. Source reconciles exact loaded descendant IDs and targets only affected Home collections. Stability of unrelated shelves was not explicitly captured.
- **References:** [state-management reconciliation/runtime evidence](../design-docs/state-management.md#migration-coverage-and-remaining-scope), lines 290-313; [notification reconciliation](<../../Shared/Services/Notifications.swift:152>).
- **Dependencies / blocker:** Not repeated in this pass. The existing Arcane evidence is retained; there is no disposable series with all descendant watched/resume states recorded and restorable, so bulk Mark Unwatched was not invoked.
- **Next action:** Repeat only with recorded before-state; assert all loaded children, Continue, unrelated rows, and focus, then restore the initial state.

### E02 — App Font is independent from subtitle font settings

- **Subsystem / severity / status:** Typography/subtitle configuration; P2; **SOURCE VERIFIED**.
- **Reproduction:** In this final verification, Settings visibly showed App Font = Rounded; a subtitle-bearing S2:E2 playback frame displayed captions. System/Rounded/Serif comparison was not performed.
- **Expected:** App-wide SwiftUI type design does not replace the separately configured rendered subtitle font.
- **Observed / evidence:** `AppFontEnvironment` applies SwiftUI `.fontDesign`; subtitle font name/size/color remain in `subtitleConfiguration` and the VLC proxy configures subtitle rendering from that setting. Native AVPlayer remains AVKit-owned. Rounded and a visible subtitle track were observed, but subtitle rendering was not compared across app-font settings.
- **References:** [App Font environment](<../../Screen tvOS/App/ScreenApp.swift:34>), [subtitle setting](<../../Shared/Views/SettingsView/VideoPlayerSettingsView.swift:348>), [VLC subtitle font](<../../Shared/Objects/MediaPlayerManager/MediaPlayerProxy/MediaPlayerProxy+VLC.swift:99>).
- **Dependencies / blocker:** A subtitle-bearing sample was available, but this verification did not change App Font or inspect/record the subtitle-font setting. No setting was changed in this pass.
- **Next action:** Compare actual subtitle rendering before/after App Font change while leaving subtitle configuration unchanged, then restore Rounded.

### F02 — Hidden/inactive controls cannot acquire focus

- **Subsystem / severity / status:** Focus eligibility of inactive content; P1; **SOURCE VERIFIED**.
- **Reproduction:** No dedicated hidden-control focus sweep was run in this audit.
- **Expected:** Inactive tab content and hidden HUD controls cannot acquire focus; visible active controls retain their documented default.
- **Observed / evidence:** MainTabView makes inactive tab content transparent, disabled, non-hit-testable and accessibility-hidden. The custom playback hierarchy structurally includes HUD only while visible; focus APIs retain a progress-first default. Runtime did not probe every hidden/inactive control.
- **References:** [MainTabView inactive content](<../../Shared/Coordinators/Tabs/MainTabView.swift:210>), [HUD focus presentation](<../../Screen tvOS/Views/VideoPlayer/PlaybackControls/PlaybackControls.swift:140>), [focus contract](../design-docs/focus-navigation-contract.md#hidden-player-controls-and-visible-hud), lines 359-384.
- **Dependencies / blocker:** Runtime focus debugger exposes hosting responders rather than all SwiftUI candidates; physical hardware was excluded.
- **Next action:** On simulator, exercise hidden HUD, dropdown, Episodes, and inactive retained tabs for accidental focus acquisition; use hardware for final focus proof.

## Unverified cases

### B08 — Home vertical shelf focus regression matrix

- **Subsystem / severity / status:** Home vertical focus; P1; **UNVERIFIED**.
- **Reproduction:** This pass focused the first Continue tile (The Secret Lives of Mormon Wives S3:E11), moved Down to Circle in Recently Added Movies, then Up; it also entered the Home sidebar and returned with Right.
- **Expected:** Never skip an adjacent shelf; choose nearest visible horizontal position; choose deterministic fallback for short shelves; immediate reverse restores exact origin; scrolled offsets and Details return remain correct; one press means one transition.
- **Observed / evidence:** Down selected Circle in the aligned first column; Up restored the exact S3:E11 tile. Left entered the sidebar and Right restored that same tile. Short-shelf fallback, horizontally scrolled row offset, Details return from a scrolled shelf, and all Home shelf boundaries were not exercised in this pass. Prior implementation work passed the focused vertical scenario, but the full matrix remains unverified.
- **References:** [FocusCoordinator Home routing](<../../Shared/Objects/FocusCoordinator.swift:63>), [focus contract Home](../design-docs/focus-navigation-contract.md#home-and-shelves), [2026-10-08 runtime evidence](../design-docs/state-management.md).
- **Dependencies / blocker:** Requires deliberately short and horizontally scrolled shelves; no blocker to future simulator coverage.
- **Next action:** Run the missing shelf/boundary matrix and keep Left/Right, membership, sidebar, and exact Details return as regressions.

### D02 — Search request-error focus and recovery

- **Subsystem / severity / status:** Search loading/error focus; P2; **UNVERIFIED**.
- **Reproduction:** Search was opened and its app-owned field/keyboard appeared, but no controlled failed request was injected; session authentication and shared server connectivity were not disrupted.
- **Expected:** A query failure does not steal focus; field and keyboard remain usable, no delayed jump occurs, and recovery returns to results correctly.
- **Observed / evidence:** SearchView keeps app-owned field/key focus and the SearchViewModel refreshes nested content groups. Nested content-group request/error presentation is separate from SearchViewModel's own state; the error-focus/recovery path has not been runtime-proven. This is a risk to test, not a confirmed bug.
- **References:** [SearchViewModel request path](<../../Shared/ViewModels/SearchViewModel.swift:81>), [Search focus and content](<../../Shared/Views/SearchView.swift:86>), [state-management Search scope](../design-docs/state-management.md#migration-coverage-and-remaining-scope), lines 318-326.
- **Dependencies / blocker:** A safe deterministic single-request failure injection/test endpoint is not configured. No broad connectivity or authentication disruption was attempted.
- **Next action:** Use a controlled one-request failure, preserve the active session, assert focus/input/recovery, and restore connectivity without changing user data.

### E01 — EPG font geometry across System, Rounded, and Serif

- **Subsystem / severity / status:** EPG typography/layout; P3; **BLOCKED**.
- **Reproduction:** Media was opened to check for an EPG route; only Favorites, Movies, and Shows were available. Home exposed no guide/EPG route in this signed simulator session.
- **Expected:** Program text, row height, ruler alignment, and clipping remain correct for System, Rounded, and Serif.
- **Observed / evidence:** No EPG surface or guide data could be opened in this app session, so row height, time-ruler alignment, clipping, focus boundaries, and font geometry were not runtime-tested. Source computes EPG row/ruler dimensions from preferred UIKit text metrics with minimum heights; program and ruler text use fixed semantic styles and one-line truncation, which is not runtime proof.
- **References:** [App Font environment](<../../Screen tvOS/App/ScreenApp.swift:34>), [EPGLayout](<../../Shared/Objects/EPG/EPGLayout.swift:18>), [program cell](<../../Shared/Components/EPG/Body/Components/EPGProgramCell.swift:73>), [time ruler](<../../Shared/Components/EPG/Body/EPGTimeRuler.swift:43>).
- **Dependencies / blocker:** The installed app session exposed no EPG/guide route and no loaded guide data. Runtime verification requires an accessible Live TV/EPG surface; Rounded remains the observed App Font preference.
- **Next action:** Revisit when a guide route and data are available; capture the same EPG rows/ruler in System, Rounded, and Serif, then restore the original font.

### F04 — Playback overlay layering matrix

- **Subsystem / severity / status:** Player-local overlay stack; P1; **UNVERIFIED** as a full matrix.
- **Reproduction:** Current audit opened Up Episodes and Back returned to the HUD. Existing 2026-09-28 simulator evidence covered nested Audio, Subtitles, and Quality picker Back, then dropdown, HUD, and Details. Intro/Credits are separately reproduced as A01/A02.
- **Expected:** One Back dismisses only the top active surface in order: nested picker, dropdown, Episodes/segment surface, transient HUD, player. Focus returns to the correct underlying target.
- **Observed / evidence:** In this pass, Episodes Back returned to the HUD, a separate Back hid the HUD, and another Back returned to the prior Details route. During playback an Intro prompt was briefly visible while Episodes was open; after one Back Episodes closed and the HUD returned, but the prompt had also naturally left its segment window during the observed playback interval, so this does not establish duplicate dismissal. Earlier post-fix A01/A02 acceptance remains recorded above. Existing 2026-09-28 nested Audio, Subtitles, and Quality picker results predate the latest checkpoint and were not repeated here. The full matrix remains incomplete; no new reproducible defect was established.
- **References:** [focus contract player stack](../design-docs/focus-navigation-contract.md#player-dismissal-and-return-focus), lines 525-539; [tech-debt segment cases](tech-debt.md#deferred-findings-and-review-needs); [dropdown evidence](../design-docs/focus-navigation-contract.md#down-playback-dropdown).
- **Dependencies / blocker:** A fresh full matrix still needs an available Credits countdown sample plus repeatable nested picker content. A01/A02 fixes have separate prior simulator acceptance.
- **Next action:** Retest dropdown and nested picker Back, then use an active Intro and Credits countdown to verify one-layer dismissal and focus return across the complete stack.

### F05 — First/last focus boundaries and deterministic fallback

- **Subsystem / severity / status:** Cross-screen focus boundaries; P1; **UNVERIFIED**.
- **Reproduction:** Current audit checked Home first TV Shows tile Left to sidebar, Home shelves Down/Up, Search first key Left, and Search no-results Down. Existing Episodes checks exercised several selector/shelf edges, but no single full boundary matrix was run.
- **Expected:** Representative first/last targets, section transitions, empty regions, and missing-target fallbacks retain focus or choose the documented deterministic destination with one press.
- **Observed / evidence:** B01 sidebar return restored the first Continue tile in this pass. Episodes current-item restoration, cross-season fallback to S1:E1, Left at the first episode, and Episodes → HUD → hidden HUD → Details were checked. Earlier F06 evidence covers last-card/last-season clamping. Search first-key no-results and D01/D03 behavior remain covered by their prior entries. Libraries, Settings, Details shelves, empty episode collections, and disappearing-item fallback were not all exercised.
- **References:** [focus contract known deviations](../design-docs/focus-navigation-contract.md#known-deviations-and-required-confirmation), lines 543-554; [Home fallback](<../../Shared/Objects/FocusCoordinator.swift:326>); [Search fallback](<../../Shared/Views/SearchView.swift:99>).
- **Dependencies / blocker:** Some focus regions use native tvOS spatial movement; device confirmation remains outstanding.
- **Next action:** Maintain a compact per-region first/last/empty-target checklist and rerun only affected paths with navigation changes.

## Blocked verification

E01 is **BLOCKED** because this simulator session exposed no EPG/guide route. D02 remains **UNVERIFIED**: a safe deterministic failure injection is not configured, but can be provided later without disrupting global connectivity. B03-B07 remain source-verified with runtime coverage incomplete because the available Jellyfin data did not include a disposable, fully restorable test fixture.

## Newly discovered issues

No newly reproducible defect was established in this final verification. F06 was discovered during A03 testing and is PASS after the playback-surface press owner was made explicit; the original wrap and final boundary acceptance evidence are recorded above. B01 reproduced on the pre-fix baseline and passed after the focused correction; it was not a new issue. During this pass an Intro prompt briefly coexisted visually with Episodes, but its disappearance coincided with the segment ending while the tested Back closed Episodes; this was inconclusive and is not classified as a defect. The Search keyboard capture mismatch (`aaaaa` rather than the typed synthetic query) remains attributed to Device Hub input handling, not the app.

### X01 — Play Next product acceptance and native-player coverage

- **Subsystem / severity / status:** Playback product acceptance/backend scope; provisional P2; **UNVERIFIED**, not a confirmed bug.
- **Reproduction / inspection:** Source inspection of custom `ScreenPlaybackSegmentOverlay` and `NativeVideoPlayer`; no native-player Play Next runtime sample was run.
- **Expected:** Product acceptance and native-player parity have not been decided by this audit; treat the existing product direction separately from custom-player behavior.
- **Observed / evidence:** The custom player attaches the four-part segment overlay; the native AVPlayer path does not. Existing tech debt calls for review of the custom transition and clarification of native-player coverage. This is an implementation-scope decision, not a runtime defect without a confirmed parity requirement.
- **References:** [existing tech-debt entry](tech-debt.md#deferred-findings-and-review-needs), [Play Next product spec](../product-specs/play-next.md), [focus contract](../design-docs/focus-navigation-contract.md#intro-credits-and-play-next), lines 497-514.
- **Dependencies / blocker:** Product decision on native-player parity and acceptance of the custom overlay.
- **Next action:** Jamie reviews product acceptance separately; do not mix a parity decision into A01/A02 Back ownership fixes.

## Recommended repair order

1. Retain A03 cross-season current-episode restoration and F06 directional boundary ownership in focused playback regression checks.
2. Close the high-impact verification gaps with reversible test data: B03-B07 membership/progress/watched propagation, then D02 Search failure/recovery and D03 watched-specific assertion if desired.
3. Complete B08 and F05 focus boundaries, F02 hidden controls, E01 EPG geometry, and any remaining F04 overlay matrix.
4. Resolve X01 as a product/acceptance decision. Do not treat it as a confirmed bug or broaden playback architecture before that decision.

There are two useful shared investigations: (a) A01/A02 exposed the same outer player Back-delivery failure and now pass after one UIKit container owner was restored; their Intro-dismissal and countdown-then-choice transitions remain distinct, as does F04's separate segment surface; (b) B02-B07 share typed ItemState publication and targeted collection invalidation, but presentation-only updates must stay distinct from membership/order refresh. B01 and A03 both involve focus timing, yet they have different owners (Home sidebar candidate acquisition vs episode-card candidate readiness) and should not be patched by a shared delay.

## Regression checklist

- [x] A01: Intro Back dismisses only prompt; same player continues without a seek; HUD returns.
- [x] A02: first Back cancels countdown, second dismisses choice to the HUD; neither press exits the player.
- [x] A03: same-season and cross-season Up Episodes reopens focused the current episode; unavailable-in-season fallback selected the first eligible card; Back returned Episodes → HUD → hidden HUD → Details.
- [ ] A04: Details-origin playback returns to same Details, then Home exact origin only after Home is visible.
- [ ] A05: Play returns to Play, Replay/Play From Beginning returns to its exact action, unavailable Replay falls back to Play.
- [x] B01: sidebar Right and Select restored the remembered tile from the TV Shows row, Movies row, and a horizontally scrolled Movies shelf; Home Up/Down reverse and Details return preserved the exact target. Initial launch still focused the first Home candidate. (Apple TV 4K 3rd gen, 1080p, tvOS 27.0 simulator.)
- [ ] B02-B07: focused tile updates, Continue membership add/remove, completion/Next Up ordering, descendant unwatch reconciliation, unrelated shelves, and deterministic focus.
- [ ] B08: adjacent shelf, nearest visible tile, short-row fallback, immediate reverse, scrolled offset, Details return, one press.
- [ ] C01-C02: native menu and App Font Back/selection return to invoking row; immediate reopen; no delayed jump.
- [ ] D01-D03: no-results input focus, controlled request failure/recovery, exact result return and accepted user-state presentation.
- [ ] E01-E03: System/Rounded/Serif EPG geometry; subtitle font independence; episode title/locator/series/fallback and Movie HUD.
- [ ] F01-F05: exact route restoration, hidden/inactive focus eligibility, one-press transitions, full overlay stack, and first/last/empty target fallback.
- [x] F06: Episodes selector/shelf directional movement is one step; first/last season and episode boundaries retain focus. (Apple TV 4K 3rd gen, 1080p, tvOS 27.0 simulator.)

## Known-bug-free exit criteria

The bug-burn-down phase is complete only when every confirmed bug is fixed and its original reproduction passes on the Apple TV 4K (3rd generation) 1080p simulator, with affected contract regressions passing; no source-only claim closes a confirmed bug. All currently unverified items are either runtime-verified or explicitly accepted as non-defects/product decisions with evidence. No unexpected focus target, duplicate transition, delayed jump, playback exit, watched/progress mutation, or unrelated Home membership change remains in the affected paths. Physical Apple TV behavior remains a separate evidence tier where hardware-specific focus/playback proof is required.

## Original audit changes and side effects
In the initial register audit, only this register was created. The pre-existing modified files `docs/design-docs/focus-navigation-contract.md`, `docs/design-docs/navigation-stack.md`, and `docs/product-specs/navigation.md` were not edited, staged, reverted, or overwritten. No source code, existing normative document, commit, or push was changed in that audit.

Runtime used the already installed signed simulator app (version 1.4.1). The existing Mormon Wives S3:E10 session was resumed/paused and returned normally; no watched/favorite/completion control was changed. “Wuthering Heights” was already marked Watched; two brief playback samples reached about 0:03 and returned to its Details screen with Watched still shown. Start/stop reports may have updated its resume position; server-side ticks were not queried and that possible small progress update was not restored. The temporary App Font change was restored from Serif to Rounded. Search query input was local and the simulator session was left without any auth/connectivity changes. No build/install was run because only a documentation artifact changed.

## A01/A02 implementation follow-up (2026-10-10)

The remediation changes are limited to `Shared/Views/VideoPlayer/VideoPlayer.swift` and `Shared/Views/VideoPlayer/VideoPlayerContainerView/VideoPlayerContainerView.swift`. The overlay is hosted as a child of the UIKit player container; its controller receives Menu at `pressesBegan`, calls the shared handler once, and consumes the paired `pressesEnded` phase. `handleMenuEnded()` gives segment state first ownership and returns after coordinator consumption. Intro Back clears only the prompt; countdown Back cancels and retains the choice; a later Back clears the Play Next presentation. No relevant SwiftUI `onExitCommand` handler exists in this path. The presentation subscriber now derives dismissal eligibility from the emitted `presentation` value instead of rereading the `@Published` property during `willSet`.

Focused runtime checks on the requested Apple TV 4K (3rd generation), 1080p, tvOS 27.0 simulator passed: Intro Back; countdown cancellation followed by separate overlay dismissal; HUD Back; Down dropdown Back; nested quality-picker Back; Up Episodes Back; regular player exit and return to the same Details route; Skip Intro activation; Play Next advancing one episode; and Keep Watching retaining the current episode. `The World Is Hot Enough` rendered on the episode HUD with `S10:E2` and `Futurama`, fitting on one line without overlap with the progress bar or timestamps. Movie playback still showed only `10 Cloverfield Lane` with the ordinary progress controls. One initial dropdown observation after Down was not reproducible on the immediate retrial and is not classified as a new bug.

The signed simulator build/install completed successfully before these documentation-only updates; lint reported 17 existing violations and 0 serious findings. The temporary Credits / Outro test preference was restored to Show Next Episode; its saved countdown duration was restored to 10 seconds. Test seeking and Play Next exercised the existing progress/completion paths and may have changed Futurama episode resume/watched state on Jellyfin; server-side state was not queried or restored. No commit or push was made. The three pre-existing dirty navigation documents remain untouched.

## 2026-10-11 tvOS Home episode route migration follow-up

### R01 — Home episode route initially focuses the first episode

- **Subsystem / severity / status:** Home episode entry initial focus; P1; **IMPLEMENTED — ACCEPTANCE INCOMPLETE**. Keep R01 open until the required regression matrix is green; do not mark PASS from the episode-target checks alone.
- **Reproduction:** On Apple TV 4K (3rd generation), 1080p, tvOS 27.0 simulator, select Futurama S10:E7 from Home Continue Watching.
- **Expected:** Show Details opens with the route season selected and the originating playable episode's artwork initially focused. The route target stays pending while content loads; no Play, season-selector, first-episode, or delayed corrective focus is allowed.
- **Source change:** The virtualized `CollectionHStack` now retains the route's target ID/index and artwork focus ID as state, reveals the target through its existing proxy as episode cells register, retries positioning on subsequent cell-appearance events while layout extent is still growing, and issues one focus request only after the target artwork action appears. Other initial controls/cards remain unavailable while that request is pending. Ordinary Details entry keeps its existing Play target. The authoritative focus/navigation contract was not edited.
- **Runtime matrix — Apple TV 4K (3rd generation), 1080p, tvOS 27.0 simulator only:**

  | Scenario | Result | Evidence |
  | --- | --- | --- |
  | A. Futurama S10:E7 from Continue Watching | **PASS** | Season 10 was selected; Episode 7 artwork acquired initial focus without an Episode 1 focus event. |
  | B. NCIS S1:E10 from Continue Watching | **PASS** | During loading, focus stayed pending; the target was revealed at its loaded index and Episode 10 artwork acquired focus. |
  | C. Select focused artwork once | **PASS** | Player identified NCIS S1:E10, “Left for Dead.” |
  | D. Route season differs from default | **PASS** | Futurama opened to Season 10 rather than its default Season 1. |
  | E. Ordinary Show Details initial Play focus | **UNVERIFIED** | Not exercised in this run. |
  | F. Episode shelf Left/Right after route focus | **FAIL** | From focused NCIS Episode 10, one Right press landed on Episode 14; one Left returned to Episode 10. No wrap was observed, but sequential-next focus did not match the contract. |
  | G. Home/sidebar, Movie Details, and player Back paths | **FAIL / PARTIAL** | Player Back returned to the same NCIS Details instance with Episode 10 focused; the next Back returned Home. Right from the Home sidebar acquired Futurama. In the Home vertical reversal check, Down from Futurama selected Frozen II, but Up landed on Dancing with the Stars instead of Futurama. Movie Details focus was unverified. |
  | H. Focus while content loads | **PASS** | Loading placeholders and early episode-cell appearances kept the target pending; only the registered route artwork target received the single initial request. |

- **Acceptance status:** The R01 target-focus behavior passed for both exact routes, playback, cross-season selection, and loading. The complete runtime matrix did not pass because F failed and G exposed a Home vertical-reversal failure; E and Movie Details focus remain unverified. Do not mark R01 PASS until these acceptance results are resolved or explicitly re-scoped.
- **Scope / evidence boundary:** No source tests were added or run. The signed in-place simulator build/install is requested separately as implementation verification; it does not change the matrix above. No physical Apple TV was used.
- **Next action:** Continue with the authorized 2026-10-16 focused follow-up below. Keep R01 open while the Home reversal result remains inconsistent and until the remaining focus-eligibility check is verified.

### 2026-10-16 authorized directional follow-up

- **Verified episode-shelf root cause:** Route entry temporarily disabled every episode card other than the requested target while its focus request was pending. In the virtualized `CollectionHStack`, this changed the eligible candidate set during initial focus acquisition. Simulator A/B reproduced the effect: with the gate, focused NCIS S1:E10 followed by one Right landed on E14 while E11–E13 were visible; without the gate, Right landed on E11. The collection's semantic target ID was correct at entry, and the ordinary Show Details shelf moved one episode per press.
- **Correction:** Removed the route-only `.disabled` gate, keeping all loaded episode cards focusable throughout. The collection now gives default focus to the semantic route target; non-target episode cards on that route do not nominate their artwork as a default-focus candidate. The target artwork retains its own default and explicit readiness-driven focus request. This keeps normal spatial navigation and CollectionHStack virtualization intact without corrective presses or timers.
- **Home regression diagnosis:** The previously recorded Futurama Down/Up failure was not reproduced on the current same-origin rerun: after returning from Futurama S10:E7, Down selected the nearest visible movie tile (Practical Magic 2) and Up restored Futurama. A separate Neagley → Resident Evil → Neagley Down/Up path also passed. The earlier failure remains valid evidence and is not reclassified as PASS. The Home vertical recognizer/decision implementation is unchanged in the working-tree diff; the migration's FocusCoordinator change adds pending initial route focus state. No localized causal link to the route migration is confirmed. The compared Home runs had different visible shelf offsets/membership, so the original failing geometry still needs an exact repeat.
- **Runtime matrix — Apple TV 4K (3rd generation), 1080p, tvOS 27.0 simulator only:**

  | Scenario | Result | Evidence |
  | --- | --- | --- |
  | 1. NCIS S1:E10 initial focus | **PASS** | Season 1 selected; Episode 10 “Left for Dead” artwork focused on the settled route frame. |
  | 2. NCIS E10 Right → E11 | **PASS** | One Right selected Episode 11 “Eye Spy.” |
  | 3. NCIS E11 Left → E10 | **PASS** | One Left returned to Episode 10. |
  | 4. Repeated horizontal navigation | **PASS** | E10 → E11 → E12 and reverse to E11/E10, with no skipped card. E10 → Left reached E9. |
  | 5. First/last episode boundaries | **PASS** | At E1, Left retained E1. Advancing through the season reached E23; Right retained E23. No wrap observed. |
  | 6. Futurama S10:E7 initial focus | **PASS** | Season 10 selected and Episode 7 “Murderoni” artwork focused. |
  | 7. Futurama adjacent-card navigation | **PASS** | E7 Right → E8 “Crab Splatter”; Left returned to E7. |
  | 8. Ordinary Show Details initial focus | **PASS** | The Secret Lives of Mormon Wives opened with Play as the initial focus; this path has no episode route intent. |
  | 9. Home Down/Up exact restoration | **UNVERIFIED** | Current Futurama same-origin and separate Neagley reversal paths passed, but the earlier Futurama → Frozen II → Dancing with the Stars failure was not reproduced with matching row offset/membership. Keep that failure open. |
  | 10. Movie Details initial focus | **PASS** | Practical Magic 2 opened with Play focused. |
  | 11. Artwork Select starts intended episode | **PASS** | NCIS S1:E10 artwork Select opened playback showing S1:E10, “Left for Dead.” |
  | 12. No delayed focus jump / hidden-control focus | **UNVERIFIED** | Captured loading frames showed no wrong episode artwork acquiring visible focus before E10; the hidden/inactive-control focus sweep was not run. |

- **Player Back layering:** From playback, the first Back hid the HUD; the next Back returned to NCIS Details with Episode 10 focused. This matches the existing layer order.
- **Contract compliance:** The authoritative focus/navigation contract remains read-only and unchanged by this follow-up. Sequential Left/Right and non-wrapping episode boundaries passed on the requested simulator. Home exact reversal remains unresolved; no contract behavior was weakened.
- **Build and hygiene:** `Scripts/build-install-tvos-simulator.sh` completed with signed in-place install and exit code 0. Lint reported 17 existing violations and 0 serious findings. `git diff --check` passed after the final documentation edit.
- **Acceptance status:** R01 and Pass 1 remain open. The NCIS directional regression is corrected and the route/Futurama checks pass. Home reversal remains an inconsistent runtime result, and hidden/inactive focus eligibility remains unverified. Re-run the original Home failure with the same shelf membership/offset before claiming completion.

### 2026-10-18 Pass 1 final acceptance

This final simulator run supersedes the open R01 status recorded above. R01 is **PASS**; the earlier Home Down/Up report remains a separate **UNVERIFIED** case because its original membership and offsets could not be recreated.

- **Runtime device:** Apple TV 4K (3rd generation), 1080p, tvOS 27.0 simulator. No physical Apple TV was used.
- **Episode-route matrix:**

  | Scenario | Result | Evidence |
  | --- | --- | --- |
  | NCIS S1:E10 initial focus and season | **PASS** | Season 1 was selected; E10 “Left for Dead” artwork held the visible focus outline after the route settled. |
  | NCIS Right → E11, Left → E10 | **PASS** | Each single press moved exactly one card and returned to E10. |
  | Futurama S10:E7 initial focus and season | **PASS** | Season 10 was selected; E7 “Murderoni” artwork held the visible focus outline after the route settled. |
  | Futurama Right → E8, Left → E7 | **PASS** | Each single press moved exactly one card and returned to E7. |
  | Artwork Select playback | **PASS** | NCIS artwork opened S1:E10 “Left for Dead”; Futurama artwork opened S10:E7 “Murderoni.” |
  | Player Back to originating Details episode | **PASS** | Back first hid the player HUD; the next Back returned to the same Details route with the originating E10 or E7 artwork focused. |
  | Sequential movement and episode bounds | **PASS** | Current adjacent-card checks passed. The 2026-10-16 targeted run also advanced NCIS E10→E11→E12 and back, and verified Left at E1 and Right at E23 retained the boundary card. |
  | Ordinary Show Details initial focus | **PASS** | The Secret Lives of Mormon Wives opened through its ordinary Home tile with Play as the initial target. |
  | Movie Details initial focus | **PASS** | The Love Hypothesis opened with Play as the initial target. |
  | One press, one movement; no corrective jump | **PASS** | The NCIS and Futurama directional presses produced one adjacent-card transition each. Route focus appeared on the registered target; no other card focus outline or subsequent correction was observed. |

- **Route-entry lifecycle audit:** `ItemView` seeds the route artwork target as pending. While that request is pending, Play and the other action-row controls are non-focusable. The episode collection defaults to the episode section; non-target route cards do not nominate artwork as a default target. It reveals the requested index through `CollectionHStackProxy`, then requests focus only after the target card and artwork action register. A virtualized card that has not registered is not in the mounted focus candidate set and cannot receive the route request. The route-only `.disabled` gate on neighboring cards remains removed, so eligible neighboring episodes stay focusable. The visible loading frame showed placeholders without another episode focus outline; the settled frame showed only the requested artwork. No timer, synthetic remote press, or corrective second focus request is used. This verifies the route-entry focus lifecycle and neighboring-card eligibility without changing normal Details behavior.
- **Home Down/Up investigation:** The original `Futurama → Frozen II → Dancing with the Stars` result was **not reproduced**. On this run, the available Continue row contained NCIS, Haunted Hotel, A Dog’s Purpose, Insidious, Dancing with the Stars, Practical Magic 2, The Secret Lives of Mormon Wives, Marshals, and Futurama. Futurama was at the right edge (approximate visible center x=1285 px); in Recently Added Movies, Frozen II was at approx. x=1150 px and Circle at x=1280 px. Down therefore selected Circle, the nearest visible center, and Up restored Futurama. The historical row membership/offset that made Frozen II the Down target was unavailable, so the original case remains **UNVERIFIED**. No Home focus code changed and no causal relationship to R01 was established. Separate return checks restored NCIS and The Secret Lives of Mormon Wives to their originating Home tiles after Details dismissal.
- **Contract compliance:** The authoritative `focus-navigation-contract.md` remains unchanged in this task. Exact route artwork focus, eligible neighbors, one-step directional movement, bounded episode edges, one-layer player Back, ordinary Show Details Play focus, Movie Details Play focus, and Home origin restoration all retain the documented behavior. The independent historical Home geometry case remains open outside R01.
- **Build and hygiene:** No source changed in this task, so no build/install was run. The existing signed simulator app from the focused implementation pass was used. `git diff --check` passed after this documentation update. No commit or push was made.
- **Acceptance status:** **R01 PASS. Pass 1 PASS.** The un-reproduced Home Down/Up geometry case remains tracked separately as **UNVERIFIED** and does not keep R01 open.

### 2026-10-23 Pass 2A player return and Home origin restoration

- **Runtime target:** Apple TV 4K (3rd generation), 1080p, tvOS 27.0 simulator. No physical Apple TV was used.
- **Confirmed Home offset cause and correction:** Before this follow-up, returning from Movie Player through Details moved an already-visible Home origin within its row and changed the vertical Home position. `FocusCoordinator` centered the collection item whenever it resolved the return target, and `ContentGroupView` centered the containing row on every target change. The correction only scrolls when the item/row is offscreen. After the signed build, the Frozen II Player → Details → Home path retained the visible row position; one Right moved from Frozen II to Circle. The target identity and focus were restored.
- **Futurama lifecycle — PASS:** Home Futurama S10:E7 opened Details with Season 10 and E7 “Murderoni” artwork focused. Select played S10:E7. Back hid the HUD, then returned to the same Details route with E7 focused; Right → E8 and Left → E7. Details Back restored the Futurama Home tile. Playback refresh reordered Futurama before NCIS in Continue; focus followed the same Futurama item while the shelf remained at its existing leading offset.
- **NCIS lifecycle and mutable playback episode — PASS:** Home NCIS S1:E10 opened Details with Season 1 and E10 “Left for Dead” focused; Select played E10. Up Episodes showed E10 as Now Playing. Right to E11 and Select played “Eye Spy”; reopening Episodes showed E11 as Now Playing. Back closed Episodes, the next Back hid the HUD, and the next returned to the original Details route with E10 focused. Right → E11 and Left → E10. Details Back restored the NCIS Home tile after Continue refreshed.
- **Scrolled Home shelf — PASS:** From the advanced Continue row, Dancing with the Stars S35:E3 opened Details with Season 35 and E3 “Viral Hits Night” focused. Back restored Dancing with the Stars focus while the shelf remained horizontally advanced; it did not return to the first card.
- **Regression samples — PASS:** Ordinary Death of the Pastor’s Wife Show Details opened with Play initial focus. Frozen II Movie Details opened with Play initial focus; Replay started the Movie Player, Back returned to the same Details route, and Back restored Frozen II on Home. From Crystal Lake in Recently Added TV Shows, Left opened the sidebar and Right restored Crystal Lake. Down to Clown Panic and Up restored Crystal Lake.
- **Hidden/inactive controls — SOURCE REVIEWED; full runtime sweep UNVERIFIED:** This pass changed only Home restoration scrolling. The existing episode route keeps the request pending until its artwork is registered and prevents the pending action row from competing for focus; a dedicated hidden/inactive-control runtime sweep was not repeated.
- **Missing-origin fallback — SOURCE REVIEWED; runtime UNVERIFIED:** `resolveHomeReturn` prefers the exact item ID in its original group, then the same nonempty series in Continue, then the closest original-group index (lower index wins a tie), then the first ordered Home tile. A missing-origin fixture was not created because it would require changing server membership/history.
- **Historical Home Down/Up geometry — UNVERIFIED:** The earlier Futurama → Frozen II → Dancing with the Stars failure was not recreated with its original membership and offsets. The Crystal Lake/Clown Panic reversal above is a separate passing sample and does not change that classification.
- **Contract and build:** The authoritative focus/navigation contract was not edited. Exact parent-route restoration, one-layer Back, visible-target retention, and the sampled sequential episode navigation passed. `Scripts/build-install-tvos-simulator.sh` completed with signed in-place install; lint reported 17 existing violations and 0 serious findings. `git diff --check` passed. No commit or push was made.
- **Pass 2A status:** **PASS for the reproduced lifecycle and restoration paths.** The historical Home geometry case and runtime missing-origin fallback remain separately **UNVERIFIED**; no reproducible in-scope navigation or focus regression remains.

### 2026-10-23 Pass 2B Search and library episode routing

- **Scope:** Extend the Pass 2A tvOS episode route to Search and library selections. No physical Apple TV was used.
- **Source review:** Search and library episode selections with resolvable series ownership use the existing `EpisodeRouteIntent` and Show Details route. Search carries query, result-group ID, and item ID; it restores the exact result and falls back to the Search field when the saved query, group, or item is no longer valid. Library origin carries tab ID, library ID, item ID, and collection index; `PagingLibraryView` restores the exact item, then the nearest valid same-library index (lower index on a tie), then the first displayed item. A visible target does not recenter; an offscreen target uses the existing grid scroll coordinator. Playback keeps Details as its parent, and origin restoration waits until Details is dismissed.
- **Home route and navigation regressions — PASS:** The signed simulator build succeeded. Home episode route, player/Details Back layering, exact Home return, episode-shelf movement, and the sampled Home/navigation paths passed as recorded above.
- **Search episode route — PASS (Jamie manual verification):** Jamie confirmed Search → NCIS S1:E10 → Show Details → Player → Details → original Search result. The Search query remained available, and the original NCIS result regained exact focus.
- **Exact Search result restoration — PASS:** Jamie's end-to-end run returned to the same Search result with retained query and exact result focus after dismissing Player and Details.
- **Missing-result fallback — runtime UNVERIFIED:** Source falls back to the Search field when the saved query, result group, or item is unavailable. No runtime missing-result fixture was exercised.
- **Library-origin episode route — UNVERIFIED:** No episode-containing library origin was exercised. Search and Home episode paths do not establish library-origin routing or return focus.
- **B09 sidebar handoff — PASS:** Right/Select entered TV Shows, Movies, and Search content as recorded below; Search query/results survived a sidebar preview and re-entry. No physical Apple TV was used.
- **Contract and acceptance:** The navigation contract records Search and library episode routing, Search result restoration, library fallback, and retained Search/sidebar behavior. Pass 2B is **PASS for the accepted Home/navigation, sidebar handoff, and Jamie-verified Search paths**. Library-origin episode routing and missing-result fallback remain **UNVERIFIED**.

### B09 — Sidebar activation leaves focus in the rail

- **Subsystem / severity / status:** tvOS tab focus handoff; P1; **PASS — RESOLVED AFTER RUNTIME ACCEPTANCE**.
- **User report and runtime reproduction:** Jamie reported being unable to enter Search from the sidebar and described a prior difficulty entering TV Shows. On the Apple TV 4K (3rd generation), 1080p, tvOS 27.0 simulator, Home → sidebar → TV Shows preview followed by Right and Select left the rail expanded with TV Shows highlighted and no poster focus visible. Repeating with Movies left the rail expanded. Search preview displayed the field and key strip; Right and Select left Search highlighted in the rail without visible Search focus.
- **Root cause:** `MainTabView` cleared its sidebar `FocusState` but left the selected sidebar button eligible and preferred while tab content requested focus. The Search preview was mounted before activation, and `SearchView.onAppear` assigned the field target while its parent content was disabled; activation then repeated that same target. This created a competing sidebar/content handoff and a stale Search focus request. Pass 2B episode-route changes did not introduce the sidebar activation path; the issue was in the existing root-tab handoff.
- **Correction:** Serialize the root handoff by disabling sidebar focus preference until Search or library content reports focus acquisition. Do not assign Search focus while it is only a sidebar preview. Keep the tvOS Search view mounted so query/results survive tab previews. Home's exact restoration continues to use its existing completion signal.
- **Runtime acceptance — PASS:** The signed simulator build was installed in place on the specified Apple TV 4K (3rd generation), 1080p, tvOS 27.0 simulator. One Right entered TV Shows and focused its first poster; one Select entered Movies and focused “Wuthering Heights”; one Right entered Search and outlined the Search field. Down focused the first Search key and Select entered `a`. Search → Left/Back → sidebar → Right re-entry retained `a` and the result groups; Down focused the first result poster. Sidebar → Home → Right restored the exact NCIS Continue tile. Home Down focused Coraline and Up restored NCIS. Each sampled press produced one visible transition; no delayed corrective jump or trapped focus remained. No physical Apple TV was used.
- **Remaining separate Pass 2B gaps:** Library-origin episode routing and runtime missing-result fallback remain **UNVERIFIED**; they do not change the Search route or sidebar-handoff PASS results.

### 2026-10-23 Pass 3 ID-only and context-menu episode routes

- **Scope:** tvOS ID-only item routes (including deep links and socket `displayContent`), poster context-menu Go to Item / Go to Series, and the Episode Details parent button. No physical Apple TV was used.
- **Resolution contract:** Fetch the requested ID and verify the returned ID. Non-episode items retain ordinary Details. For episodes, require a nonempty series ID, fetch the owner, and verify its ID and series type before creating the existing `EpisodeRouteIntent`. The intent carries the originating episode ID and season ID; its registered artwork remains the initial focus target. Ownership failure keeps the ID route on Episode Details or the existing error presentation for strict parent/Go to Series paths. Deep links and socket routes without a parent do not invent a Home or Search target. Opening Show Details does not start playback. iOS continues using the existing ID route; the intentional episode metadata action remains unchanged.
- **Search episode route — PASS (Jamie manual verification):** Jamie confirmed Search → NCIS S1:E10 → Show Details → Player → Details → original Search result, with the query retained and exact result focus restored. Exact Search result restoration is **PASS**.
- **ID-only Search Go to Item — PASS:** On the specified Apple TV 4K (3rd generation), 1080p, tvOS 27.0 simulator, Search Go to Item fetched the NCIS S1:E10 episode and verified its owning NCIS series. It opened Season 1 with E10 artwork focused and no playback; Select started `S1:E10 NCIS Left for Dead`. Player Back returned to the same Show Details route with E10 focused; Details Back retained `left for dead` and restored the exact Search result. This exercised the shared tvOS `.item(id:)` resolver, not the separate deep-link or socket trigger.
- **Context-menu Go to Series — PASS:** Search Go to Series opened NCIS Show Details at Season 1 with E10 artwork focused and did not start playback; Details Back returned to the Search result. Home Go to Item and Go to Series also opened the intended NCIS Show Details / Season 1 / E10 target without playback, preserving the Home origin.
- **Episode Details parent button — runtime UNVERIFIED (simulator interaction inconclusive):** The intentional metadata action opened Episode Details for NCIS S1:E10, “Left for Dead.” The NCIS parent capsule was visible. Source trace: Episode Details owns an ordinary ItemView focus coordinator whose initial request targets Play; the parent is a native Button with .focusable(true) in this fallback state, is not registered with FocusCoordinator, and uses the nested route's @Router to call .resolvedEpisode(item:origin:). D-pad Up, Down, Left, and Right produced no visibly attributable focus change on the parent. The blue Play tint is not sufficient evidence of focus because the same tint remains visible while episode artwork has confirmed focus. Select was not sent because the active target could not be identified safely; activation, destination, season selection, and parent-origin restoration remain unverified. One Back returned to Show Details and restored the E10 metadata card; the next Back returned to Search with left for dead retained and the exact NCIS result focused. The simulator run does not distinguish failed native focus acquisition from a missing visible focus cue, so no source defect is confirmed.
- **Deep link / socket triggers — runtime UNVERIFIED:** DeepLink and socket `displayContent` were not independently dispatched in this simulator run. Both resolve through the shared `.item(id:)` path that passed via Search Go to Item; source inspection is not trigger-specific runtime evidence.
- **Focused regressions — PASS:** Home episode → Show Details → Player → original Details → Home, Search → Details → Player → exact Search result, sidebar → Search / Movies / TV Shows / Home, Movie Details, and ordinary Show Details returned to their expected originating contexts. Episode-shelf Left/Right moved E10 ↔ E11; Left at the first episode (S1:E1) and Right at the last episode (S1:E23) retained the respective boundary target.
- **Library-origin episode route — runtime UNVERIFIED:** No episode-containing library origin was available for a safe end-to-end fixture. Search and Home paths do not establish library-origin routing or return focus.
- **Missing-result / unresolved-owner fallback — runtime UNVERIFIED:** No disposable test item with a missing or invalid owner was available. No real Jellyfin data was changed to manufacture a failure case.
- **Build and scope:** The signed in-place simulator build/install succeeded on the specified device; no physical Apple TV was used. The iOS `.item(id:)` implementation remains on its prior path by source review; no iOS runtime test was run.

### 2026-10-25 Episode Details focus and parent activation

- **Status:** Source correction implemented; updated Simulator behavior **UNVERIFIED**. Jamie reproduced indistinct focus throughout NCIS S1:E10 Episode Details and an NCIS parent control that enlarged without navigating.
- **Source finding:** The parent, Play, version menu, and action controls added `.focusable(...)` around already focusable native controls. This creates an extra focus target without the underlying Button's activation action. It also separates the focused target from the control styling. Apple explicitly warns against applying this wrapper to intrinsically focusable controls in [Build SwiftUI apps for tvOS](https://developer.apple.com/videos/play/wwdc2020/10042/). This source defect matches the reported symptoms; the installed application's focused item and action dispatch were not captured in a new runtime trace.
- **Dispatch review:** The parent handler already uses its nested `@Router` to push `.resolvedEpisode(item:origin:)`. The existing resolver refetches and verifies the episode and owning series before creating the episode intent. The route does not start playback; unresolved ownership retains the strict error fallback. The route resolver, router, and presentation hierarchy were not changed.
- **Correction:** Native controls now own focus and Select. Pending artwork-entry gates temporarily disable the existing controls instead of adding focusable wrappers. Episode Details Play, version, and action controls use the same native card style as the parent and other Details cards; the trailer control inherits its row's style. Other Details styles and iOS styles remain in place. The parent records its existing coordinator target before presenting Show Details, and registers that target with `coordinatedFocus` for return to the same Episode Details instance.
- **Source verification:** Reviewed the task-only diff against the pre-existing working tree. SwiftFormat lint and syntax-only parsing with tvOS and iOS target conditions succeeded for the five affected Swift files. Syntax parsing is not type checking or a successful app build. No Xcode build, app installation, or updated-app runtime check was performed.
- **Required Simulator checks — UNVERIFIED:** Enter Episode Details through E10's metadata action; verify visible native focus and activation on every available header control and menu. Focus/select NCIS and confirm NCIS Show Details, Season 1, E10 artwork focus, and no autoplay. Back must return to the same Episode Details parent control, then the original Show Details metadata control, then the actual Search/Home origin, one layer per press. Recheck pending episode-artwork entry so Play/actions cannot take initial focus. Exact restoration, native focus appearance, and iOS runtime behavior still require validation.

### 2026-10-25 Episode Details outline presentation follow-up

- **Runtime baseline from Jamie:** Focus now works and the NCIS parent opens Show Details in Simulator. The native card styles introduced focus growth on Play, watched, favorite, and parent controls, plus an oversized white highlight on the compact ellipsis menu. The functional focus/activation correction is retained.
- **Presentation correction:** Reuse `BasicHoverButtonStyle`'s existing Ice Blue outline and restrained glow with interaction scaling disabled only for Episode Details header controls. The Play outline has a small visual outset to separate it from the blue fill without changing layout or hit bounds. Version and Advanced ellipsis labels are constrained to their existing 60 × 75 button bounds so the focus border remains compact. Other callers retain the style's previous defaults; iOS branches, native control eligibility, activation handlers, route dispatch, and focus restoration are unchanged.
- **Source checks:** Reviewed the incremental presentation diff against the existing working tree; focused SwiftFormat and SwiftLint checks succeeded. No redundant `.focusable` modifiers were added. No build or commit was performed.
- **Updated Simulator checks — UNVERIFIED:** Confirm fixed control dimensions, visible colored outlines including contrast on Play, and a compact ellipsis border. Recheck menu Select/Back, NCIS parent activation without autoplay, and one-layer Back restoration. Jamie's functional baseline does not establish these updated visual results or exact return focus.

## Feature regression verification

### 2026-10-25 Screen Themes final Simulator regression

- **Status:** **PASS — user-reported.** Jamie reports that all final Screen Themes Simulator regression tests passed. The scenario-by-scenario matrix and simulator configuration were not included in this checkpoint request, so this entry records the reported result without expanding its scope.
- **Completed phases:** Palette model and contrast-aware resolver; per-user curated/custom preference with legacy accent migration; Settings selection/custom-color editor and app-wide semantic palette propagation; theme integration across shared controls, posters, Details/Search/library surfaces, and playback; regression verification. The implementation checkpoint and phase summary are in [the completed Screen Themes plan](completed/screen-themes.md).
- **Checkpoint scope:** This is a feature-verification record, not a claim that the whole worktree was theme-only. At this checkpoint, navigation/focus follow-ups and local signing edits remained separate. The latest navigation/playback status is recorded in the 2026-10-28 checkpoint below. No build or additional Simulator run was performed during this checkpoint review.

### 2026-10-28 episode playback and Back regression checkpoint

- **Status:** **PASS — user-reported Simulator verification, 5/5 scenarios.** This checkpoint records Jamie's latest Apple TV Simulator report; detailed build/device logs were not attached to this commit request.
- **Episode artwork playback — PASS:** Episode artwork launched playback reliably for 15 consecutive cycles while remaining in Show Details. Identity-scoped fullscreen presentation cleanup released each completed player route, and the next artwork activation launched a fresh player directly from Show Details.
- **Episodes Back — PASS:** SwiftUI `onExitCommand` dismissed the Episodes surface without exiting playback.
- **Return navigation — PASS:** Normal player Back returned to the same Show Details route. Show Details → Home restored the expected Home focus.
- **Outstanding regression coverage:** Quality, Audio, Subtitles, and nested picker Back handling still need a dedicated regression check. These cases are not included in the 5/5 result above.
- **Open playback issues:** The Next Episode countdown presentation and focus follow-ups are recorded below with their combined Simulator result.
- **Scope / evidence boundary:** These results do not close other previously unverified route, focus, playback, or iOS cases in this register. No physical Apple TV result is claimed.
- **Implementation and verification detail:** See [the 2026-10-28 playback/navigation plan](completed/episode-playback-navigation-2026-10-28.md). The 15-cycle run was user-reported; it was not repeated during commit preparation.

### 2026-10-28 Combined playback UI verification

- **Status: 5/5 PASS — Jamie-reported Apple TV Simulator verification.** Episodes Left/Right advances one tile per press. Repeated movement, shelf boundaries, selection, and Back work. After countdown cancellation, Next Episode focus moves without snapping back. Play Next, Keep Watching, and Down to the content shelf work. Playback, fullscreen cleanup, Episodes Back, and countdown ring remain functional. No physical Apple TV result is claimed.
- **Countdown ring completion:** The ring animates to 100% at the original countdown deadline, before the zero tick starts autoplay. Configured durations remain 5, 10, 15, and 30 seconds.
- **Focus after countdown cancellation:** The Next Episode subtree no longer reassigns Play Next focus on countdown presentation changes. Initial focus remains owned by the overlay presentation lifecycle; native directional focus between Play Next and Keep Watching is preserved.
- **Episodes horizontal navigation root cause and correction:** The UIKit press handler queued a manual `focusedTarget` move for Left/Right while episode cards were native focusable Buttons in a horizontal `ScrollView`. The queued move reads the current target when handled, allowing a native focus advance to be followed by another custom advance; visible scrolling follows that focus. Left/Right now fall through to tvOS native focus navigation. App-owned Up/Down routing between the season selector and episode shelf remains.
- **Combined Simulator acceptance:** (1) One Left/Right press advances exactly one episode and focus/scroll stay synchronized. (2) Repeated movement, both boundaries, selection, and Episodes Back work. (3) Cancel countdown with Back, then move Up/Down repeatedly between Play Next and Keep Watching without focus snapping back. (4) Both buttons activate. (5) Down from Play Next reaches the content shelf. (6) Fullscreen cleanup, playback, countdown ring, and Episodes Back remain functional. Jamie reports all five scenario groups passed.
- **Evidence boundary:** Simulator results were user-reported; no build or runtime session was performed during this checkpoint. At this checkpoint, English audio preference remained unresolved; its later verification is recorded below. Other previously recorded playback and navigation gaps remain separately scoped.

### 2026-10-28 English audio preference verification

- **Status: 5/5 PASS — Jamie-reported Simulator verification.** English was selected on initial playback and remained selected across three consecutive autoplay transitions. Explicit manual track selection was respected. When English was unavailable, playback used the configured fallback. “Play Default Track” correctly took precedence over the preferred language.
- **Correction:** `MediaPlayerItem.build` now resolves the requested audio stream from the explicit selection, the user's Play Default Track setting, the normalized preferred language, then Jellyfin's default/first available audio stream. The resolved index is sent in playback info and initializes the player item, so initial launches and every episode transition use the same preference path.
- **Metadata:** Language identifiers are normalized through Foundation locale parsing before matching, including ISO alpha-2/alpha-3 and locale-tag forms such as `en-US`.
- **Preserved behavior:** Explicit stream indexes remain authoritative. Subtitle selection, playback lifecycle, fullscreen cleanup, Next Episode UI, and navigation behavior are unchanged.
- **Evidence boundary:** All five runtime scenarios were reported by Jamie on Simulator. No build was run during this checkpoint; no physical Apple TV result is claimed.

### 2026-10-28 physical Apple TV sidebar Instruments checkpoint

- **Status:** **INCOMPLETE — measurable median improvement, sidebar focus remains sluggish.** Jamie reported only minimal physical-remote improvement after the latest correction. Selecting a tab enters its content; selection latency was not quantified in this trace.
- **Capture:** DEBUG build 1.4.1 (70) on the connected Apple TV 4K (3rd generation), tvOS 27.0. The 45.9-second Instruments trace included Jamie's rapid Home → TV Shows → Movies focus sequence and one Select. Animation Hitches, Time Profiler, and Points of Interest were captured. `SidebarFocusToPreview` and `SidebarFocusToLayout` appeared in the corrected `PointsOfInterest` category (110 events each). No `SidebarSelection*` events appeared, so selection-to-layout timing remains unavailable even though the content selection worked.
- **Hitch comparison:** Baseline: 51 hitches, 43 over 100 ms, median 183.5 ms, maximum 283.6 ms. Post-correction: 51 hitches, 31 over 100 ms, median 116.78 ms, maximum 383.71 ms. The median and count of >100 ms hitches improved; total count was unchanged and the worst hitch increased. The capture durations were comparable (45 seconds baseline; 45.9 seconds post-correction); do not treat the maximum hitch as improved.
- **Focus/layout timing:** In the post-correction trace, median focus-to-layout was Home 306 ms, TV Shows 202 ms, Movies 83 ms. Overall focus-to-preview median was 29.97 ms; focus-to-layout median was 99.23 ms and p95 317.42 ms. The focus markers span 19.37 seconds, with 50 hitches during that interval, 30 over 100 ms.
- **Thread evidence / diagnosis:** Main-thread samples account for about 10.5 CPU seconds during the 19.37-second focus interval (about 54% of one core). Samples continue to include poster-overlay and item-model copies plus SwiftUI graph/update work. This implicates SwiftUI layout/update costs, but does not isolate one causal view or state mutation. **Root cause remains unresolved; no further performance correction is authorized by this evidence.**
- **Preserved traces:** Baseline and post-correction `.trace` bundles are preserved outside the repository at `/Users/snow/Documents/ScreenProfiling/ScreenSidebar-20261028.trace` and `/Users/snow/Documents/ScreenProfiling/ScreenSidebar-20261028-postfix.trace`. The original `/tmp` copies are also retained. Do not add these large binary bundles to Git.
- **Next action:** Profile the specific slow Home and TV Shows layout/update intervals in Instruments, correlate main-thread stacks with the focus signposts, and obtain a trace that records the `SidebarSelection*` events before changing performance code. Repeat rapid physical navigation after any evidence-backed fix; retain the physical-remote result separately from Simulator evidence.

### 2026-10-28 horizontal playback scrubbing follow-up

- **Status:** **INCOMPLETE — unresolved.** Current working-tree playback changes add DEBUG touch, gesture-arbitration, scrub, commit, and cancel diagnostics and adjust slider handling. No completed physical Apple TV acceptance is recorded for horizontal touch scrubbing, seek commit/cancel, or the resulting playback position.
- **Evidence boundary:** The presence of diagnostics and successful compilation do not prove that the Siri Remote touch surface reaches the horizontal pan recognizer or that the resulting seek is applied correctly. Preserve the diagnostics until a physical capture resolves the event path.
- **Next action:** On the physical Apple TV, capture the DEBUG diagnostics while scrubbing in each direction; verify gesture begin/change/end, commit/cancel, player time, and visible progress. Keep this work separate from the verified remote-navigation checkpoint until that acceptance is complete.
