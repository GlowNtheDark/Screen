# tvOS focus and navigation contract

Status: authoritative app-wide focus and remote-navigation reference. This document
combines current source behavior with Screen's intended interaction contract. It is
not evidence that every focus transition has been validated on Apple TV hardware.

For each topic, **Contract** is the behavior future changes must preserve or implement;
**Observed** describes the inspected tvOS source and available runtime evidence;
**Deviation / runtime check** calls out gaps, conflicts, and behavior that cannot be
settled from source alone. Do not silently promote an accidental observed behavior
to a product rule. The user-facing contracts remain in the linked product specs; this
document is their app-wide directional companion.

## Scope and ownership

This contract covers the custom Screen tvOS application. It does not apply the custom
player HUD or overlays to the separate native AVPlayer path. It documents the custom
VLC player, tab/library/details navigation, and app-owned focus coordinators.

The navigation stack owns routes and presentations. SwiftUI/UIKit's tvOS focus engine
owns ordinary spatial focus unless a view explicitly owns focus with `@FocusState`, a
`FocusCoordinator`, `.onMoveCommand`, `.onExitCommand`, or a directional handler. A
remote direction can therefore be native spatial focus movement, app-owned region
navigation, a player gesture/seek command, or a presentation transition. Trace which
owner receives the press before changing behavior.

Relevant implementation entry points:

- [`RootView`](../../Shared/Coordinators/Root/RootView.swift), [`UserSessionRootView`](../../Shared/Coordinators/Root/UserSessionRootView.swift),
  [`MainTabView`](../../Shared/Coordinators/Tabs/MainTabView.swift)
- [`TabCoordinator`](../../Shared/Coordinators/Tabs/TabCoordinator.swift),
  [`NavigationCoordinator`](../../Shared/Coordinators/Navigation/NavigationCoordinator.swift),
  [`NavigationInjectionView`](../../Shared/Coordinators/Navigation/NavigationInjectionView.swift),
  [`Router`](../../Shared/Coordinators/Navigation/Router.swift)
- [`FocusCoordinator`](../../Shared/Objects/FocusCoordinator.swift),
  [`focus system`](focus-system.md), [`navigation stack`](navigation-stack.md)
- Product contracts: [navigation](../product-specs/navigation.md),
  [focus restoration](../product-specs/focus-restoration.md), [Home](../product-specs/home.md),
  [Episode Details](../product-specs/episode-details.md), [playback](../product-specs/playback.md),
  and [Play Next](../product-specs/play-next.md)

## Global invariants

These are normative requirements for future focus/navigation work:

1. **One remote press, one navigation-layer transition.** A direction or Back press may
   dismiss one active child surface or move one navigation level, but must not also
   trigger the parent transition on that same press.
2. **Back dismisses the innermost active surface first.** A nested picker owns Back
   before its dropdown; dropdown, Episodes, intro/credits/Play Next transient state
   before HUD; HUD before player exit; player before its presenting Details/Home
   context.
3. **A consumed Back never propagates.** The parent must know that the child consumed
   the press, or its exit handler must be gated for that press. Dismissing a child and
   exiting playback in one press is invalid.
4. **Parents retain their route and focus context while a child is presented.** Do not
   collapse Details, a tab, or a library route to obtain focus restoration.
5. **Restore the exact prior semantic target when it still exists.** Persist stable
   identity, not only a transient index. If it no longer exists, use a deterministic
   fallback: nearest valid target in the same ordered region, that region's primary
   target, then the containing screen's stable entry target. The Home product contract
   defines a more specific fallback order below.
6. **No corrective second focus jump.** Prepare/reveal the intended target before a
   single focus request. Do not let an unrelated `.defaultFocus` acquire first and
   then move focus again to repair it.
7. **Hidden or inactive controls cannot participate in focus.** This includes controls
   under hidden overlays, inactive retained tabs, dismissed pickers, and background
   routes. Inactive retained Search, TV Shows, and Movies are excluded from input,
   accessibility, hit testing, focus callbacks, and route presentation.
8. **No arbitrary delays or queue hops as focus fixes.** A delay used by content/data
   debouncing is not a focus contract. Focus requests should be tied to target
   registration, visibility, and layout readiness.
9. **Every region boundary is explicit.** Specify what Up/Down/Left/Right does when
   focus reaches a boundary. Use native spatial movement only where the region layout
   and a runtime check establish that it is predictable; otherwise route the movement
   explicitly or document the unresolved boundary.
10. **Player dismissal and Home restoration are separate events.** Restore Home only
    after the route actually returns to Home. Details → Player → Details → Home must
    retain and restore the original Home context.
11. **Direct play is origin-specific.** A player launched directly from Home returns
    to Home; playback launched from Details returns to that same Details route first.
12. **Playback controls do not mutate playback/session/progress state merely by being
    opened or browsed.** Intentional media selection/seek/restart actions use the
    existing player and session APIs; do not parallel those APIs in views.
13. **Separate player states stay separate.** The Down playback dropdown, Up Episodes
    surface, transient HUD, intro segment, credits, and Play Next state have distinct
    ownership and dismissal stacks. Do not merge them into one menu state.

## Navigation and focus resolution model

### Entry, dismissal, and restoration targets

This matrix makes focus entry and return part of each region's contract. “Native” means
the platform currently chooses among visible eligible controls; it is not a guarantee
of exact semantic restoration. If the target is invalid, use the deterministic fallback
from [global invariants](#global-invariants), with Home's specific fallback taking
precedence. Rows marked unverified require a tvOS runtime check before asserting exact
behavior.

| Region | Entry/default focus | Dismissal | Return target and fallback |
| --- | --- | --- | --- |
| Launch/user selection | First meaningful user/server/loading/error action when available; exact root target is not app-owned | Resolve/cancel the active root or child action; app/root exit policy is unverified | Return to prior root state if still valid; otherwise signed-in tab's stable entry target; validate runtime |
| Sidebar | Currently selected tab button when the rail is entered; exact initial startup rail target is unverified | Left/Right/Select handoff activates or leaves the rail per sidebar state; Back does not skip an active child route | Return to active tab content. Search requests its app-owned field; repeat root-tab entry requests first displayed item. Home should restore its remembered tile or specified fallback |
| Home | Remembered semantic tile when returning; otherwise the ready initial Home candidate/first available row target | Item selection pushes/presents details; player/dismissal returns through actual route; Back at root follows platform/app policy | Exact originating `(groupID,itemID)`; if missing use Continue same nonempty series, nearest tile in original row, then first tile in ordered rows. Sidebar return uses last active Home tile, nearest tile in that row, then first row |
| Home shelf/tile | Existing focus if retained; otherwise parent Home target or native focus candidate | Details route or the tile's explicit action | Same tile if valid; nearest sibling in same row; first valid tile in that row; then Home fallback |
| Movies / TV Shows libraries | Root-tab repeat explicitly scrolls to top and requests first displayed item; ordinary entry/default is native and unverified | Nested folder/filter/detail routes dismiss one child at a time | Show Details dismissal restores the exact originating item in the same tab/library when available; otherwise nearest valid item by saved collection index (lower index wins a tie), then the library's first item. Preserve scroll when visible; reveal only when offscreen |
| Search | Pending sidebar-entry request targets the app-owned Search field; without a pending request native initial focus is unverified | Dismiss result details/presentation before Search; keyboard Back behavior is platform-owned until verified | Show Details dismissal restores the exact result by query, group, and item identity when still valid; otherwise the Search field. Preserve query, result membership, and scroll position |
| Settings | Native first available Form/control; exact default is unverified | Native picker/menu first, then one Settings child route | Invoking row/control if still present, else first meaningful control in the parent form; platform restoration is unverified |
| Movie Details | Shared `ItemView` coordinator targets Play | Dismiss player or nested route first, then this Details route | Preserve the same Details instance and restore the exact originating Play or Play From Beginning action while it remains present and eligible; use Play only if that action no longer exists or is ineligible |
| Show / Episode Details | Shared `ItemView` coordinator targets Play for ordinary entry. A tvOS episode route from Home, Search, or a library targets that episode's artwork after its season and card are ready | Dismiss player or nested route first, then this Details route | Preserve the same Details instance and restore the originally routed episode artwork after Player Back, even if Up Episodes changes the playing item. Dismissing Details restores the actual Home, Search, or library origin |
| Details child shelf / season selector | Preferred/current item or season when available; a tvOS episode route from Home, Search, or a library selects its intended season and targets that episode's artwork | Selecting a card can open another Details route or direct-play from artwork | Same item/season if still present; nearest item in that shelf; shelf's preferred/first item; then Play |
| Library/menu/filter/modal child | Native menu/form default; app-owned child entry where provided | Dismiss only the top menu, picker, sheet, or dialog | Return to the exact presenting control when valid; otherwise nearest same-region control then region primary target. Exactness needs runtime confirmation for native menus/forms |
| Player HUD | Hidden at player presentation; when shown for seekable content, the progress bar is the default focus. The Play/Pause status symbol is never a focus target. Live playback has no focusable transport when it has no seek bar | Back hides transient HUD; a later Back dismisses player | HUD appears with progress focused when seekable. Player exit returns to actual presenting route, not inferred origin |
| Playback dropdown | Info section on open | Picker first, then dropdown; Back must not propagate from picker to player | Closing dropdown restores the HUD with progress as its default focus |
| Dropdown nested picker | Native selected/current option or platform picker default | Back dismisses just the picker | Return to its Quality/Audio/Subtitles card; if gone, Playback Settings section |
| Up Episodes | Current season selected and current episode preferred | Back dismisses Episodes only | Current season/current episode context on reopen; Back returns to the HUD with progress as its default focus. If remembered episode is missing, selected-season first valid episode |
| Skip Intro | Skip Intro action is the segment's default target | Select invokes segment skip; Back dismisses only the prompt without seeking | Return to the player/HUD with progress as its default focus when the prompt is dismissed |
| Credits / Play Next | Primary Play Next action when shown; Keep Watching is reachable with Left/Right; Continue Watching focus is gated until Down | Back cancels a running countdown, then dismisses the remaining segment choice before HUD/player | Play Next begins with primary focus; segment dismissal returns to the HUD with progress as its default focus |
| Custom player dismissal | Actual player origin determines route | Only after all child surfaces/HUD states are closed | Details-origin returns to same Details; direct Home-origin returns Home and restores origin tile if one exists; other origins return to their presenter |
| Native AVPlayer | AVKit-owned | AVKit/presentation-owned | AVKit returns to presenter; custom player targets are not applicable |

### Root and launch

| Current focus/region | Up | Down | Left | Right | Select | Back |
| --- | --- | --- | --- | --- | --- | --- |
| Launch/loading or sign-in selection | No app-wide focus destination is established in the inspected root source; native focus/runtime check | Same | Native focus within available launch controls | Native focus within available launch controls | Activate selected user/server/error action | Dismiss only a presented child; root exit policy is platform/app-owned and needs runtime confirmation |
| Signed-in root / selected tab | Native focus of active tab content | Native focus of active tab content | Enter/expand the sidebar according to tab/sidebar state | Native focus spatially, or explicit tab entry when sidebar owns focus | Activate focused content/control | Dismiss child presentation first; at a tab root, platform/app exit behavior needs runtime confirmation |

**Observed.** `RootView` resolves loading/error/ready content; `UserSessionRoot`
chooses user selection or `MainTabView`. There is no single root focus coordinator.
Home is the normal first tab content; startup focus waits for a Home candidate to be
ready. Exact launch landing focus depends on available content and needs runtime proof.

### Sidebar and tab entry

Focusable elements: tab buttons while the rail owns focus; active tab content when the
rail is collapsed. The focused tab can preview its page before selection. Home, TV
Shows, Movies, Search, Requests, and Settings are the current tvOS tab set.

| Current focus/region | Up | Down | Left | Right | Select | Back |
| --- | --- | --- | --- | --- | --- | --- |
| Sidebar tab button | Native adjacent tab focus; exact wrap/boundary needs runtime confirmation | Native adjacent tab focus; exact wrap/boundary needs runtime confirmation | Native focus within sidebar; edge behavior needs runtime confirmation | Activate/enter the focused tab through the explicit sidebar handler | Activate the focused tab | Back does not itself select another tab; a presented child dismisses first |
| Active tab content | Native or region-specific content movement | Native or region-specific content movement | Explicitly enter the active sidebar tab when the content exit is handled | Native content movement; if sidebar owns focus, explicit tab entry | Activate the focused content; when the active tab is selected from sidebar, enter its content | Dismiss innermost route/surface; at tab root it may return focus to sidebar according to current exit handler |

**Observed.** `MainTabView` previews content on sidebar focus. Right and Select
activate a focused tab, release sidebar focus, and dispatch a root-entry event. Search
has an app-owned `TVSearchFocusCoordinator` handoff to its search field; other tabs
enter their content. Reselecting Home uses its first/top target. `onExitCommand` from
active tab content returns focus toward the sidebar. Exact native boundary movement
between sidebar and each tab must be checked on device/simulator.

**Deviation / runtime check.** `tech-debt.md` records a tvOS simulator race where Right
from the sidebar acquired the first Recently Added Movies tile before the remembered
TV Shows tile, while Select entered Continue Watching. Several focused fixes were
reverted. This violates deterministic one-step remembered-focus restoration and remains
unresolved; do not describe either first target as the intended one.

### Tab lifetime

Home, Search, TV Shows, and Movies remain mounted during a signed-in tvOS session. Home
loads its shelves during startup and preserves their view models and browsing state
across tab previews. Search preserves its query, results, and scroll position; the
library tabs preserve paging, filter, grid, letter, and focus state. Their inactive views are
transparent, disabled, excluded from hit testing/accessibility, and guarded against
focus/route callbacks. Other tabs use selected-only mounting. An inactive retained tab
must never steal focus or receive the current press. See the
[navigation contract](../product-specs/navigation.md#search-tv-shows-and-movies-tab-lifetime).

## Home and shelves

Home rows are dynamic and ordered from configuration/server content. Depending on
available content they include Continue Watching, Recently Added Movies, Recently
Added Shows, Recently Played, Recommended Programs, latest items for configured
libraries. Empty/unavailable groups can be omitted. The heading is a noninteractive
label on tvOS; tile controls are the focus targets.

| Current focus/region | Up | Down | Left | Right | Select | Back |
| --- | --- | --- | --- | --- | --- | --- |
| Home tile | Tile in the adjacent nonempty shelf above whose visible horizontal center is nearest to this tile's current on-screen center; otherwise the existing region boundary | Tile in the adjacent nonempty shelf below whose visible horizontal center is nearest to this tile's current on-screen center; otherwise the existing region boundary | Previous tile in current shelf; first tile uses native boundary behavior | Next tile in current shelf; last tile uses native boundary behavior | Open selected item's details in current route | Route/presentation owner dismisses first; from Home root Back behavior is platform/app-owned |

**Vertical shelf movement.** The target is chosen from the destination shelf's
currently visible tiles by the nearest on-screen horizontal center, so shelves with
different horizontal scroll positions keep the same visual-column intent. If the
destination is shorter or the source lies beyond its visible range, this naturally
selects the nearest endpoint; equal-distance ties choose the earlier tile. Reversing
Up/Down between unchanged adjacent shelves restores the tile from the prior move.
This behavior applies only to vertical movement. Horizontal movement and the existing
first/last-tile behavior remain unchanged.

**Home return contract.** Home focus is restored only after navigation really returns
to Home. Details remains under the player, so player dismissal leaves the Home target
dormant until Details dismisses. Preserve exact tile when available. If removed, use:

1. for a Continue Watching origin, a replacement with the same nonempty series ID in
   that row;
2. nearest remaining tile in the original row;
3. first available tile in ordered Home rows.

Sidebar return restores the last active row/tile when available, then nearest tile in
that row, then first available Home row. Reveal virtualized content before requesting
focus. Direct Home-origin playback has no Details route and returns to Home through its
own origin-aware path. See [focus restoration](../product-specs/focus-restoration.md).

**Deviation / runtime check.** `tech-debt.md` records Right/Select sidebar entry races
and states that exact acquisition is not yet stable on the 1080p tvOS simulator. The
contract above is intended behavior; currently observed first-acquisition behavior is
not accepted as the fallback rule.

## Movies and TV Shows libraries

Focusable content is the visible grid items, filter/sort controls, letter picker, and
empty-state actions. A library item can be a folder/collection or media item; the
route owner decides whether selection opens another library level or item details.

| Current focus/region | Up | Down | Left | Right | Select | Back |
| --- | --- | --- | --- | --- | --- | --- |
| Library grid item | Native spatial move to item above or header/letter region when eligible; exact boundary needs runtime confirmation | Native spatial move to item below or next content region; exact boundary needs runtime confirmation | Previous grid item; first-column boundary is native/runtime-dependent | Next grid item; last-column boundary is native/runtime-dependent | Open folder/library route or item details according to item type; resolvable episodes route to owning Show Details | Dismiss nested route/filter first; after episode Details dismissal restore the exact item in its original tab/library, otherwise nearest valid item by saved collection index (lower index wins a tie), then first item in that library |
| Filter/sort/menu control | Native focus in its menu/form | Native focus in its menu/form | Native focus within current control group | Native focus within current control group | Open/choose filter or sort route/value | Dismiss innermost menu/form and restore originating library control when valid |
| Letter picker | Native movement to content/header; exact edge needs runtime confirmation | Native movement to grid; exact edge needs runtime confirmation | Previous letter; at boundary native exit | Next letter; at boundary native exit | Scroll library to selected letter; it is not itself an item filter | Dismiss/exit picker according to its presentation; exact path needs runtime confirmation |
| Empty state | No content target unless an explicit action is shown | No content target unless an explicit action is shown | Native focus among empty-state actions | Native focus among empty-state actions | Activate visible recovery/action | Dismiss route or return toward sidebar |

**Observed.** Movies and TV Shows use `PagingLibraryView` / `ItemLibrary`, a
`CollectionVGrid`, and native spatial focus; there is no explicit per-arrow grid router
or deterministic initial item default in the inspected path. Reselecting a root tab
scrolls to top then requests the first displayed item. Letter selection scrolls and
reacquires target focus. Filter/sort uses route/sheet ownership; tvOS navigation-bar
close controls can be no-ops while Back dismisses the route. The exact target restored
from a nested filter/sort route is not stored explicitly. Episode selection carries
semantic item identity separately from the original collection index. On Details
dismissal, it restores the exact item when present, keeps the current offset if visible,
and reveals an offscreen target through the existing grid scroll owner.

**Runtime check.** Verify initial grid acquisition, grid-to-header/letter boundaries,
letter-to-grid return, and focus after filter/sort dismissal on Apple TV. Do not infer
exact focus from a scroll target or a SwiftUI responder.

## Search

Focusable elements: app-owned search field, on-screen keyboard keys, and result-group
items. Search on tvOS does not use the iOS `.searchable` focus behavior.

| Current focus/region | Up | Down | Left | Right | Select | Back |
| --- | --- | --- | --- | --- | --- | --- |
| Search field | Native focus within search/keyboard region | If searchable results are visible, explicitly focus the first result group; otherwise focus the first keyboard key | Native focus to key/search controls | Native focus to key/search controls | Begin editing / activate field and keyboard | Navigation owner dismisses one Search child route/presentation; at Search root, return to its parent |
| Keyboard key | Native focus among keys; edge behavior is native | If searchable results are visible, explicitly focus the first result group; otherwise focus the Search field | Previous key; Delete/Clear/Space are explicit keys | Next key; native edge behavior | Insert character, space, delete, or clear | Dismiss Search child route before Search; Search has no separate platform keyboard layer on tvOS |
| Search result item | Native focus in result groups | Native focus in result groups | Previous result; native group boundary | Next result; native group boundary | Open the result's item/details route; resolvable episodes route to owning Show Details | Dismiss result child route before Search; restore an episode route's exact originating result by query, group, and item identity, otherwise the Search field |
| Empty, invalid, loading, error, or no-results content | No content target | No content target; Down from the field or keyboard retains the current input target until results are visible | Search input/key region | Search input/key region | No content activation unless a visible recovery action exists | Dismiss Search child route before Search; root Back returns to the parent |

**Contract.** Search entry from the sidebar explicitly requests the app-owned field.
Down from the field or a keyboard key enters results only when a searchable result
group is present. Otherwise field Down focuses the first keyboard key and keyboard
Down focuses the Search field. Empty, invalid, loading, error, and no-results states
are informational; focus remains in the input region. Returning from an episode Details
child restores the exact originating result when the saved query, group, and item remain
valid, or the Search field as fallback; query, results, and scroll position remain
owned by Search while the child route is presented.
Back dismisses one child route at a time; Search root Back returns to its parent.

**Observed.** `TVSearchFocusCoordinator` carries a pending entry request from sidebar
Right/Select to the app-owned field. Keyboard starts editing at `A`; results are focus
sections. iOS retains `.searchable`.

## Settings

### Settings root and nested settings

Settings uses SwiftUI `Form`, native controls/menus/pickers, and nested settings routes.
Focusable controls depend on the current form and user options.

| Current focus/region | Up | Down | Left | Right | Select | Back |
| --- | --- | --- | --- | --- | --- | --- |
| Settings form row/control | Native previous row/control | Native next row/control | Native within segmented/menu controls; otherwise focus-engine boundary | Native within segmented/menu controls; otherwise focus-engine boundary | Activate the control or open its native picker/menu | Dismiss nested picker/menu or current settings route; restore prior control when valid |
| App Font row/menu (Customize, after Accent Color) | Menu: previous choice; row: Accent Color | Menu: next choice; row: Advanced | Native menu behavior | Native menu behavior | Open the menu; selecting a choice closes it and returns focus to App Font | Dismiss only the menu and return focus to App Font; the next Select opens the menu immediately |
| Nested settings route/form | Native within form | Native within form | Native within form/control | Native within form/control | Activate route/control | Dismiss one route to its parent Settings route |
| Edit Device Profile with unsaved changes | Native confirmation dialog focus | Native confirmation dialog focus | Native dialog focus | Native dialog focus | Resolve Save/Discard/Cancel according to dialog | Exit is intercepted by the unsaved-changes confirmation; do not bypass it |

**Observed.** No Settings-specific focus coordinator, initial `defaultFocus`, or
per-direction navigation router was found. Native Form/menu/picker owns focus and
restoration. The tvOS navigation-bar close button is a no-op in this route; Back owns
dismissal. `EditDeviceProfileView` has the notable unsaved-changes exit interception.

## Details screens and nested shelves

Movie Details, Show Details, and Episode Details share `ItemView`. Its ordinary initial
focus target is Play. The header includes metadata and item-specific actions; child
content groups can include related media, season/episode shelves, and other configured
groups.
Focusable controls include Play, version/source and item actions/menus, parent/season
controls, poster tiles, and episode-card actions.

| Current focus/region | Up | Down | Left | Right | Select | Back |
| --- | --- | --- | --- | --- | --- | --- |
| Details header/action group | Native among header controls or previous content region; exact edge needs runtime confirmation | From Play, the first Down selects Mark as unwatched; from a Show Details action, Down enters the season selector, and from that selector Down enters the episode shelf | Previous action/control; the tvOS Show Details row begins with Mark as unwatched, followed by Played and Favorite when available | Next action/control in the same row order; last control boundary is native | Play, open source/action menu, activate selected action, or perform the full tvOS series unwatch reset in place; after its server-backed refresh, retain focus on Mark as unwatched when it remains available | If player is above this route, dismiss player first; otherwise dismiss this details route to its actual parent |
| Details related-media shelf | Native to previous shelf/header | Native to next shelf | Previous item in shelf; first item boundary native | Next item; last item boundary native | Open selected item's details (or activate its item-specific action) | Dismiss a nested details route first; otherwise return to parent route |
| Show season selector | Native to header/previous shelf; exact boundary runtime-dependent | Native spatial movement toward the episode shelf when available; exact target/boundary needs runtime confirmation | Select previous season in the horizontal selector | Select next season in the horizontal selector | Choose season | Return through current Details route hierarchy |
| Details episode shelf/card | Native to season selector or previous shelf based on geometry | Native to next shelf | Previous episode; artwork button is direct-play focus target and metadata button opens details | Next episode; shelf scrolls horizontally | Artwork starts playback directly; metadata/content action opens Episode Details | Dismiss child Episode Details/player first; otherwise dismiss current Details route |
| Episode Details Play / Play From Beginning | Native among header actions and nearby content | Native into episode/related shelves | Native to adjacent action | Native to adjacent action | Play resumes available progress; Play From Beginning uses zero | If player is above, dismiss player to this same Episode Details instance; next Back returns through its parent hierarchy |

**Observed.** Shared `ItemView` initializes a local coordinator at Play unless a tvOS
Home episode route supplies an artwork target. Movie Details records the originating
playback action for player return; exact nested shelf focus targets are not explicitly
persisted. Without an incoming episode route, the season selector prefers a current/first
season and the episode shelf prefers the current/first episode. Changing the season
selector updates `SeriesEpisodeContentGroup` and debounces content switching. Episode
cards have two actions: artwork can directly play; metadata opens the item's Details
route. Other arrow transitions are native spatial focus/scroll behavior.

**Contract.** Details → Player → Back must reveal the same Details route, with its
meaningful focus context retained. For Movie Details, restore the exact originating Play
or Play From Beginning action while it remains present and eligible; use Play only if
the originating action no longer exists or is ineligible. A later Back returns through the existing
hierarchy. Do not convert Home selection into a direct-player route. Restore the original
Home tile only after Home becomes visible (see
[navigation](../product-specs/navigation.md) and [Episode Details](../product-specs/episode-details.md)).

For a normal tvOS Home episode selection, open the owning Show Details directly without
an intermediate Episode Details route or starting playback. The route's season takes
priority over the show's Next Up/resume season. Keep initial focus pending until the
selected season's episode card is eligible, then focus the originating episode's artwork
action. Do not focus Show Play, the season selector, or episode metadata first. If that
episode is absent from the successfully loaded season, focus the first eligible episode
there. If the requested season is unavailable, use a verified alternate season when
possible, otherwise the first available season. If no playable episodes are available,
use Show Details' stable entry target. This route-specific entry behavior leaves ordinary
Show Details focus and existing player-to-Details/Home restoration requirements intact.

The same episode-intent Show Details entry applies to tvOS ID-only item routes,
including deep links, socket `displayContent`, poster context-menu Go to Item / Go to
Series, and the Episode Details parent button, when the episode and its owning series
are verified. Select the originating episode's artwork after its selected season and
card are eligible; opening Details never starts playback. When an ID-only episode is
verified but its owner cannot be resolved, Go to Item retains the supported Episode
Details fallback, while Go to Series and the parent button retain their existing error
fallback. Do not infer ownership from route shape or add an intermediate screen. A
Search or library origin is retained when supplied by that surface; deep links and
socket routes without a parent do not invent a Home or Search focus target. Episode
metadata actions that intentionally open Episode Details remain unchanged. iOS keeps
its existing item-ID route behavior.

**Deviation / runtime check.** Exact child-shelf focus restoration on Details after a
nested route/player return is not represented by an explicit semantic target in the
inspected `ItemView` path. Native restoration is plausible but not established; test
show/episode variants and virtualized shelves rather than claiming it. The 2026-10-23
simulator run verified Search Go to Item and context-menu Go to Series episode focus,
playback, and return. The Episode Details parent control's focus/activation, deep-link
and socket dispatch triggers, and unresolved-owner/missing-result fallback remain
runtime-unverified; see the [bug burndown](../exec-plans/bug-burndown.md#2026-10-23-pass-3-id-only-and-context-menu-episode-routes).

## Modal, menu, and picker dismissal

Menus, sheets, full-screen child routes, and native pickers keep their presenting route
alive. The active innermost presentation owns Select and Back. On dismissal, restore the
presenting control if still available; if not, use the region fallback order under
[global invariants](#global-invariants).

| Current focus/region | Up | Down | Left | Right | Select | Back |
| --- | --- | --- | --- | --- | --- | --- |
| Native menu/picker row | Native menu focus | Native menu focus | Native option focus | Native option focus | Commit chosen option/action, then dismiss if native control does so | Dismiss only this menu/picker; the same Back must not reach the presenting player/route |
| App sheet/form | Native form focus | Native form focus | Native form focus | Native form focus | Activate the selected control/route | Dismiss this sheet, restore presenter context |
| Confirmation dialog | Native dialog focus | Native dialog focus | Native dialog focus | Native dialog focus | Resolve explicitly selected option | Cancel/dismiss only if allowed by dialog contract |

**Observed.** tvOS navigation routes use presented child coordinators rendered by
`NavigationInjectionView`; `.push` and `.sheet` are child contexts, fullscreen is a
separate child presentation. `Router` delegates dismissal to SwiftUI's environment
`DismissAction`. Thus route ownership does not imply exact focus restoration. Native
Audio/Subtitles/Quality dropdown pickers and library/settings menus own their first
Back when open; playback dropdown root handles the next one (runtime evidence below).

## Custom tvOS playback

The custom player is distinct from native AVPlayer. `VideoPlayerContainerView` hosts
the video and `PlaybackControls`; `VideoPlayerContainerState` and
`MediaPlayerManager` own playback/session/progress lifecycle. Playback controls may
cover the video, but opening a browsing surface must not pause playback or alter
progress/session semantics.

### Hidden player controls and visible HUD

When HUD is visible for seekable content, the progress slider is its only focusable
transport control. A small Play/Pause symbol immediately to the left reflects playback
state and is display-only. There are no Rewind/Forward or episode navigation buttons
in the HUD. Hidden controls are not focus candidates. Live playback has no progress
slider, so its status symbol remains nonfocusable and there is no HUD transport focus
target.

| Current focus/region | Up | Down | Left | Right | Select | Back |
| --- | --- | --- | --- | --- | --- | --- |
| Player with HUD hidden | First Up reveals HUD; Down opens dropdown per playback contract | Open Down dropdown | Player gesture/seek semantics; exact hidden-HUD behavior is source/runtime-specific | Player gesture/seek semantics; exact hidden-HUD behavior is source/runtime-specific | Show/activate player according to existing control semantics | Exit player through its existing return route |
| Progress slider while focused | Open Episodes when available; otherwise region boundary | Open dropdown according to playback handler | Adjust the pending seek position backward; focus stays on the slider | Adjust the pending seek position forward; focus stays on the slider | Toggle playback when idle; commit a pending directional seek | Cancel pending seek before hiding HUD; if no seek, hide HUD |
| Active pan/scrub gesture | Gesture-specific | Gesture-specific | Adjust scrub position | Adjust scrub position | No click required; release commits the seek | Cancel the scrub only; do not also hide HUD/exit on the same press |

**Observed.** Container appears with the HUD hidden and controls overlaid. A root-level
horizontal touch-surface pan begins a seek immediately while the HUD is hidden and no
player surface or presented child owns interaction; this reveals the HUD and updates
the pending timeline position during the gesture. Pan release commits the seek. When
the HUD is already visible, `SliderContainer` handles continuous horizontal scrubbing
and commits on release. Left/Right remote presses adjust a pending seek using the
configured jump intervals; Select commits that directional seek. The parent routes
Up/Down and Left/Right in its press-event handler; it does not install a catch-all
`onMoveCommand` that can swallow horizontal input. Back ordering is controlled in
`VideoPlayerContainerView.handleMenuEnded()` and can cancel a pending seek or segment
before reaching HUD/player dismissal.

**Simulator evidence.** On the Apple TV 4K (3rd generation, 1080p) simulator, the HUD
opened with the progress bar as its sole focus target. Select paused and resumed from
that focus, and the display-only status symbol changed from Pause to Play and back.
Left and Right adjusted the pending seek preview; Select committed backward and
forward seeks, with elapsed, remaining, fill, and playhead values moving together.
The Device Hub mouse drag did not emulate the remote touch-surface pan, so hidden-HUD
scrub initiation, live timeline feedback, and automatic commit remain unverified at
runtime. Up opened Episodes, Down opened the playback dropdown, and Back closed each
surface/HUD before returning to the presenting Details route. Physical Apple TV
validation was excluded.

Opening a player overlay leaves the media running; the HUD has its own transient
visibility state, while dropdown/Episodes browsing suspends its auto-hide behavior.

### Down playback dropdown

The dropdown is a distinct focus scope over the continuing video. Opening it begins at
Info. It contains top-level **Info**, **Playback Settings**, **Technical Details**.
Playback Settings offers **Quality**, **Audio**, and **Subtitles**. It is never the Up
Episodes shelf and is not the HUD itself.

| Current focus/region | Up | Down | Left | Right | Select | Back |
| --- | --- | --- | --- | --- | --- | --- |
| Dropdown top-level section row | Close dropdown and restore HUD target | Enter the selected section's first content target (Info → Restart Episode; Playback Settings → Quality; Technical Details → first diagnostic row, or stay on the section if there are none) | Previous section; wraps according to current implementation | Next section; wraps according to current implementation | Open/select section content | Close dropdown only; no same-press HUD/player exit |
| Info / Restart Episode | Return focus to Info section row | Native movement within Info content; no additional action is defined | Native/action region boundary | Native/action region boundary | Restart current episode at zero through existing playback API; the current simulator run returned to the HUD at `0:00` | At dropdown root close dropdown; if Info action is hosted by another child, child owns first dismissal |
| Playback Settings choices | Return focus to top-level Playback Settings row | Select next setting row | Previous setting; wraps according to current implementation | Next setting; wraps according to current implementation | Open native Quality/Audio/Subtitles picker | If nested picker is open, close picker only; otherwise close dropdown |
| Quality / Audio / Subtitles native picker | Native option movement | Native option movement | Previous option | Next option | Choose source/track; selection uses existing player binding/action | Dismiss picker only and restore its setting card; do not close dropdown on the same press |
| Technical Details section row | Close dropdown and restore HUD target | Enter the first diagnostic row when rows are available; otherwise remain on this row | Previous section | Next section | Keep Technical Details selected | Close dropdown only |
| Technical Details diagnostic row | Previous row; Up from the first row returns to the Technical Details section row | Next row; Down from the final row remains on that row | Move to the closest row in the other column; stay in this region if it has no rows | Move to the closest row in the other column; stay in this region if it has no rows | No action; rows are informational | Return to the dropdown section row only |

**Observed.** Dropdown open resets section/selection and requests Info focus. Top-row
Up closes it; setting-row Up returns to section; arrows switch sections/settings;
Select opens the corresponding native menu. A simulator trace on tvOS 27.0 showed
first Back dismissed each of Audio, Subtitles, and Quality picker without the player
controller receiving that Menu press; root Back then closed dropdown, a later Back hid
the HUD, and a later Back returned to Episode Details. Restart Episode visibly acquired
focus on Down and selected playback showed `0:00` of `53:48`. The same trace showed
UIKit's focus debugger exposed the SwiftUI hosting responder rather than individual
SwiftUI candidates.

The dropdown stays open while it is browsed and the video continues behind it.

Info displays current-media/session information already held by the player. Quality
reflects existing source/bitrate selection, Audio reflects the selected audio track,
and Subtitles reflects the selected subtitle track with None/disabled available when
exposed by the existing selection. Technical Details presents existing diagnostics
such as direct-play/transcode state, source/quality, video resolution/bitrate, and
current audio/video/session/player information where available. These values are
informational and do not add backend requests or session ownership.

**Contract.** Technical Details is a nested focus region. Down from its section row
enters the first available diagnostic row; Up/Down navigate valid rows in visual order.
Down on the final row stays there. Up from the first diagnostic row and Back from any
diagnostic row return to the dropdown's section row. A later Back closes the dropdown.
Informational rows do not activate. Left/Right switches to the closest row in the other
diagnostic column and remains in the region if that column is empty. If diagnostics
have no rows, the section row remains focused.

**Observed.** Before the explicit diagnostic focus region was implemented, the section
router had no Down destination for Technical Details and its displayed `LabeledContent`
rows were not individually focusable. Episode dropdown horizontal wrapping and exact
focus restoration after picker dismissal should be retested on a physical Apple TV; the
cited simulator result is evidence for that run, not a universal hardware guarantee.
See [tech debt](../exec-plans/tech-debt.md).

### Up Episodes surface

Episodes is a separate bottom-sliding surface over continuing video, available from
the visible HUD for episode playback with a queue. It contains a season selector and a
horizontal episode shelf. Current season is selected on open; currently playing episode
is marked. Selection uses the existing `MediaPlayerItemProvider` /
`MediaPlayerManager.playNewItem(provider:)` path. Back closes Episodes and restores the
HUD; reopening returns to current season/current episode context. Down remains owned by
the dropdown path. When a series has only one season, the selector is omitted and the
episode shelf is the only focus region.

| Current focus/region | Up | Down | Left | Right | Select | Back |
| --- | --- | --- | --- | --- | --- | --- |
| Visible HUD / Episodes closed | Open Episodes when available; from hidden HUD, first Up only reveals HUD | Open dropdown | Adjust pending seek backward while progress remains focused | Adjust pending seek forward while progress remains focused | Toggle playback when idle; commit directional seek; pan release commits scrub | Cancel pending seek before hiding HUD; otherwise hide HUD before player exit |
| Episodes season selector | Stay in the selector; no focusable parent target | Move focus to the preferred episode in the selected season: current episode if present, otherwise first eligible episode | Select previous season and keep focus in selector; at first season remain there | Select next season and keep focus in selector; at last season remain there | Retain selected season; shelf reflects it | Close Episodes and restore HUD; do not exit playback |
| Episodes episode shelf/card | Move focus to the selected season button when the selector is present; otherwise stay in the shelf | Stay in the shelf; no focusable child region | Move to previous episode card and scroll it into view; at first card remain there | Move to next episode card and scroll it into view; at last card remain there | Select episode through existing queue/provider play path | Close Episodes and restore HUD; do not exit playback |

**Prior deviation (routing fixed; boundary behavior unverified).** Season selector
changes the shelf in place and selected episodes reuse the queue/provider playback
path. The playing episode is marked when its season is selected. Back restores
the progress slider rather than an arbitrary former focus target. Before this pass, the
root-level direction handler routed Left/Right to `moveSeason()` regardless of whether
an episode card owned focus. `EpisodesSurface` now routes horizontal movement by the
focused season/episode target and explicitly routes valid vertical transitions
between those regions. At unsupported directions and boundaries, the current handler
returns without assigning a new focus target. Source inspection alone does not prove
whether tvOS keeps focus in that region or performs native spatial movement; confirm
boundary containment at runtime before treating that part of the contract as verified.

**Contract / resolved ownership.** On entry, select the playing episode's season and
focus that episode after its card is registered; if it is unavailable in the loaded
season, focus the first eligible episode. While a season button owns focus, Left/Right
changes one season and keeps focus in the selector; at either season boundary, focus
stays on that boundary button. A season change updates the shelf in place without
moving focus out of the selector. While an episode card owns focus, Left/Right moves
one card and scrolls it into view; at either shelf boundary, focus stays on that card
and never changes season. Up from an episode card focuses the selected season button
when multiple seasons make the selector visible; with one season it stays in the shelf.
Down from any season button focuses the current episode when it belongs to that season,
otherwise the first eligible episode. Up at the selector and Down in the shelf are
consumed with focus retained in the current region, preventing escape to hidden/player
controls. Reopening selects the currently playing season and episode. Back closes only
Episodes and restores the HUD with progress as its default focus; the surface does not
auto-hide while browsed.
Episode selection continues through the existing queue/provider playback API. See
[playback](../product-specs/playback.md).

### Intro, credits, and Play Next

Intro/credits segments and Play Next are playback states, not dropdown categories or
Episodes-surface content. Preserve their existing coordinator/state transitions.

| Current focus/region | Up | Down | Left | Right | Select | Back |
| --- | --- | --- | --- | --- | --- | --- |
| Skip Intro action | Retain Skip Intro focus | Retain Skip Intro focus | Native movement among visible overlay targets | Native movement among visible overlay targets | Seek to the intro segment end through the segment coordinator | Dismiss only the intro prompt without seeking; return to the player with progress as the HUD default focus |
| Credits / next-segment overlay | Native focus within overlay; conditional credits state may route automatically | Native focus within overlay; conditional credits state may route automatically | Native overlay focus | Native overlay focus | Activate the focused Play Next or Keep Watching action | During countdown, cancel countdown and retain the choice; a later Back dismisses the segment overlay before HUD/player |
| Play Next action | Retain primary Play Next focus | Enter Continue Watching shelf when eligible; shelf is gated until Down | Focus Keep Watching | Focus Keep Watching | Start the resolved next episode using `playNewItemCompletingCurrent` | Cancel countdown first; a later Back dismisses Play Next and returns to HUD |
| Keep Watching action | Return focus to Play Next | Return focus to Play Next | Return focus to Play Next | Return focus to Play Next | Cancel countdown and dismiss the segment UI while the current item continues | Cancel countdown first; a later Back dismisses Play Next and returns to HUD |
| Continue Watching shelf in Play Next | Return focus to Play Next action | Native focus within shelf; exact lower boundary runtime-dependent | Previous item | Next item | Start the selected item through existing `playNewItem` continuation semantics | Cancel countdown first when active; otherwise dismiss the segment overlay before HUD/player |

**Observed.** Custom `ScreenPlaybackSegmentOverlay` attaches to the custom player,
not native AVPlayer. Intro default focus targets Skip Intro; a seek that crosses the
entire segment without landing inside it does not present a stale prompt. Back dismisses
the intro prompt without seeking. `ScreenPlaybackSegmentCoordinator` supports credits
modes Off, Show Next, Countdown, and immediate autoplay. The visible next-episode
choice begins on Play Next; horizontal movement reaches Keep Watching, and Down from
Play Next enters the gated Continue Watching shelf. Play Next uses
`playNewItemCompletingCurrent`; Keep Watching leaves the current item playing; a shelf
selection uses `playNewItem`. Back first cancels a running countdown, then on a later
press dismisses the remaining segment presentation. Dismissal restores the HUD with
progress as its default focus. Native player does not attach this overlay.

**Deviation / runtime check.** Simulator acceptance passed on Apple TV 4K (3rd
generation), 1080p, tvOS 27.0: Back dismisses the Intro prompt without seeking;
during Credits countdown, the first Back cancels the countdown and a later Back
dismisses Play Next. HUD focus returns after segment dismissal. Physical Apple TV
behavior remains unverified. The current overlay's visual acceptance remains a
separate review item in [tech debt](../exec-plans/tech-debt.md). Credits, natural-end
queue autoplay, and Play Next are separate paths; do not unify their state or
dismissals.

## Player dismissal and return focus

| Current focus/region | Up | Down | Left | Right | Select | Back |
| --- | --- | --- | --- | --- | --- | --- |
| Custom player after all overlays/HUD are closed | Existing player input policy | Existing player input policy | Existing player input policy | Existing player input policy | Existing player input policy | Dismiss player once, returning to its actual presenting route |
| Player launched from Details | Player controls/overlay state | Dropdown when active | Player controls/seek policy | Player controls/seek policy | Current player action | Dismiss to same Details instance; do not also dismiss Details |
| Player launched directly from Home | Player controls/overlay state | Dropdown when active | Player controls/seek policy | Player controls/seek policy | Current player action | Dismiss directly to Home; then resolve origin tile if one exists |
| Native AVPlayer | AVKit-owned focus/navigation | AVKit-owned focus/navigation | AVKit-owned focus/navigation | AVKit-owned focus/navigation | AVKit-owned controls | AVKit/player presentation dismissal; no custom HUD/dropdown/Episodes semantics are implied |

**Contract.** First satisfy the player-local Back stack (nested picker → dropdown →
Episodes/segment/transient HUD state → player). Only when no player surface remains
does Back dismiss player. Then return through the actual navigation stack. Details
must remain visible after Details-origin playback; only a later Back returns to its
parent. Home focus restoration starts after Home becomes visible, not when player
dismisses. `MediaPlayerManager` stop/progress reporting and watched state remain
separate from route/focus restoration.

**Observed.** Custom player distinguishes direct Home routes from Details-origin routes
and reports lifecycle through `VideoPlayerContainerState`/`MediaPlayerManager`.
`NavigationCoordinator` can retain a player under a Details child. Home observes its
direct/details presentation slots and defers the target until Home is actually visible.
Exact focus inside nested Details is not explicitly retained by a stable target in all
paths. Native AVPlayer dismissal and focus are AVKit-owned and are not made equivalent
to custom player behavior by this contract.

## Known deviations and required confirmation

The following are known gaps, not alternate intended behavior:

| Area | Current evidence / discrepancy | Required follow-up |
| --- | --- | --- |
| Sidebar → Home | Simulator trace acquired the first Movies tile before remembered TV Shows target on Right; Select entered Continue. Prior attempted fixes were reverted. | Reproduce exact Right/Select/offscreen/launch and Details return flows; fix only with event-order evidence. See [tech debt](../exec-plans/tech-debt.md). |
| Native focus boundaries | Libraries, Settings, Details shelves, and some overlays rely on tvOS spatial movement without app-defined edge policy. | Runtime-check affected boundaries when layouts/routes change; make deterministic only where product requires it. |
| Exact nested-route restoration | `ItemView`, library routes, and Settings do not all store a semantic prior target. | Verify platform restoration on device; add explicit target ownership only if a reproducible failure warrants it. |
| Search return target | The prior result can disappear after its child route is dismissed. | Restore that result when still valid; otherwise focus the Search field. |
| Episodes shelf horizontal boundary | Season change handler may receive Left/Right while episode card owns focus. | Trace focus owner and press route on simulator/device; assign one owner to each direction. |
| Intro / credits / Play Next runtime evidence | Simulator acceptance passed on Apple TV 4K (3rd generation), 1080p, tvOS 27.0 for Intro dismissal, countdown cancellation, Play Next dismissal, and HUD restoration. Physical Apple TV behavior remains unverified. | No remaining simulator follow-up for A01/A02; keep natural-end queue autoplay and other Play Next paths separate. |
| Launch and Settings entry | Root and SwiftUI Form use native focus without stable app-owned entry IDs. | Validate entry and restoration on supported Apple TV OS versions. |
| Native AVPlayer | AVKit path has no custom overlays and owns its focus/dismissal. | Treat any requested parity as a separate product/architecture decision. |

## Change and validation checklist

For any future tvOS focus or navigation change:

1. Read this contract plus the owning product spec and implementation map.
2. Identify the sole owner of the current remote press and active focus scope.
3. Record current and intended focus before changing code; do not assume a view is a
   focus candidate because it is visible or has a SwiftUI hosting responder.
4. Define all directional region boundaries, Back-stack effects, entry target, return
   target, and missing-target fallback.
5. Validate one press causes one transition, parent target survives, and hidden/inactive
   content cannot acquire focus. Use Apple TV hardware for final focus/playback proof;
   simulator/build/source evidence must be labeled as such.
6. Validate playback behavior separately from route/focus behavior: seek, pause/play,
   session/progress, watched state, direct-play origin, Credits/Play Next, and return.
7. Update this contract when a stable ownership boundary or intended interaction changes;
   update product specs for product intent and tech debt for confirmed unresolved bugs.
