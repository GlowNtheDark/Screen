# State and data boundaries

## Session and persistence

[`UserSessionManager`](../../Shared/Services/UserSession/UserSessionManager.swift)
owns authentication/current session through FactoryKit registration.
[`UserSession`](../../Shared/Services/UserSession/UserSession.swift) owns the Jellyfin
client and starts/stops connection/socket services. The shared
[`ViewModel`](../../Shared/ViewModels/ViewModel.swift) supplies authenticated requests,
logging, and Combine subscriptions. Action/state models use StatefulMacros; views
use ObservableObject, StateObject, and local SwiftUI state for presentation.

[`ScreenStore`](../../Shared/ScreenStore/ScreenStore.swift) manages versioned
CoreStore/SQLite persistence and local ServerState/UserState models.
StoredValue/Defaults hold preferences; Keychain owns credential storage. UI state
is not an alternative source of server media truth.

## Items and propagation

Jellyfin `BaseItemDto.userData` carries `isPlayed`, `playbackPositionTicks`, and
`lastPlayedDate`. [`ItemContentGroupProvider`](../../Shared/Views/ItemContentGroupView/ItemContentGroupProvider.swift)
fetches the full item and resolves a playback provider. On tvOS, Movie and top-level
series Details overlay session-scoped `ItemState` on their local metadata snapshot;
accepted watched/favorite responses update that state through
[`Notifications`](../../Shared/Services/Notifications.swift). The iOS Details path keeps
its existing snapshot and optimistic action behavior.
[`PagingLibraryViewModel`](../../Shared/Objects/PagingLibrary/PagingLibraryViewModel.swift)
updates matching item IDs and calls each library's user-data hook.

[`BaseItemDto` extensions](../../Shared/Extensions/JellyfinAPI/BaseItemDto/BaseItemDto.swift)
derive progress labels/percentages. [`PosterIndicatorsOverlay`](../../Shared/Components/PosterIndicators/PosterIndicatorsOverlay.swift)
uses `isPlayed` for completed styling. Never promote high progress into watched state.
[EpisodeCard](../../Shared/Objects/ContentGroup/SeriesEpisodeContentGroup/SeriesEpisodeContentGroup+EpisodeCard.swift)
has a separate indicator path; check it too when a change affects episode-card styling.
For disagreements, correlate the same ID in fresh server data and local mappings;
UI appearance alone cannot identify the cause. If Jellyfin itself returns contradictory
state, report that evidence rather than changing local semantics to hide it.

## Continue Watching and refresh

[`ResumeItemsLibrary`](../../Shared/Objects/Libraries/ResumeItemsLibrary.swift) starts
from Jellyfin resume items. TV video requests also fetch Next Up and recently played
episodes. It chooses partial episodes ahead of Next Up for each series, uses a 14-day
completed-series activity window, deduplicates by series ID (name fallback), preserves
non-episode resume entries, then sorts the combined result by last-played activity.
The iOS branch returns the resume response directly.

[`CinematicSelectionContentGroup`](<../../Screen tvOS/Objects/CinematicSelectionContentGroup.swift>)
performs display deduplication and passes updates to the Top Shelf snapshot writer.
The custom Play Next overlay has its own resume-library view model, so those surfaces
share derivation logic rather than a single in-memory list.
[`ContentGroupViewModel`](../../Shared/ViewModels/ContentGroupViewModel/ContentGroupViewModel.swift)
coalesces broad Home refreshes and honors focus coordinator deferral. Typed item updates
now requery only Home collections whose membership or ordering can change; accepted
stop reports no longer refresh every shelf. [Focus readiness](focus-system.md) remains
a separate gate.

Queries are bounded by page limits; this is not an exhaustive local watch-history
index. Missing IDs/dates can affect deduplication and ordering. Inspect actual payloads
before diagnosing a report. The [product contract](../product-specs/continue-watching.md)
describes the intended result; these query details describe the current mechanism.

## TV Shows and Movies session loading

The retained tvOS TV Shows and Movies tabs opt into `PagingLibraryViewModel`
automatic refresh. Their first active-scene appearance starts the existing model's
initial load, without requiring tab selection. A successful response, including an
empty one, marks initial loading complete. Subsequent refreshes replace the collection
in the background; existing content stays visible during requests and failures.

A 60-second timer checks a five-minute freshness window while the scene is active.
Scene activation and tab entry also check freshness. Typed item updates patch matching
DTOs immediately and advance the collection generation so an older in-flight snapshot
cannot overwrite them. `ItemLibrary` requests a replacement only when its active
user-data filter or sort can change membership/order; playback-position-only updates
do not trigger a Movies/TV Shows query. Metadata, delete, global-refresh, and
connection-change signals still invalidate the collection. A single worker batches
requested refreshes for 350 ms and drains one pending refresh at a time; signals during
a request require a follow-up. Filter/sort changes use that same worker. Search keeps
its own paging state and rejects results from an obsolete filter/sort environment.

This adds no item database/cache or separate preloader. The tradeoff is retaining
one full TV series collection and one full Movies collection with their grids, plus
moving both initial item/filter requests into signed-in startup. In-flight work may
finish when the scene becomes inactive; new automatic requests wait until activation.
Initial failures remain retryable by the freshness checks. Home and iOS do not enable
this policy.

## App-wide live item state audit

Audited on 2026-10-08 before the Phase 1 implementation below. The ownership findings
and migration direction remain useful; the implementation section records the current
source behavior. The focus contract remains unchanged.

### Current ownership and identity

Screen already uses MVVM and Combine/SwiftUI observation. Shared `ViewModel` subclasses are
`ObservableObject`; view models publish state with `@Published`; views own models with
`@StateObject` and observe child models with `@ObservedObject`. StatefulMacros provide action/state
machinery. This is enough infrastructure for live updates; the gap is that media state
is usually a DTO snapshot owned by each screen or collection, not one observable entity
shared by those owners.

`BaseItemDto` values are copied into independent owners: each
`PagingLibraryViewModel` holds its own `elements` and `searchElements`; each Home `PosterGroup` has its
own paging model; the tvOS Continue row and Play Next overlay each have a resume-library
model; Search suggestions are a separate array; Details keeps metadata and derived
playback/group selection in `ItemContentGroupProvider`, while Movie and top-level series
user data comes from `ItemState`; Show Details creates a season model whose elements are
further episode paging models. The observable arrays notify SwiftUI when their own
copies change, but changing one copy does not change another unless that owner observes
the shared state or handles the update event.

Jellyfin item `id` is the useful canonical identity within a signed-in
`UserSession`. `BaseItemDto.id`, `UserItemDataDto.itemID`, search/library rows, Details, and
episode rows all use that server item ID. The shared store is scoped to the current
session and keyed by item ID; a process-wide store would need a composite
server/user/item key because user data is user-specific and IDs are server-local.
Continue's `continue-watching` paging-library ID and the visual Home group ID
`cinematic-selection` identify collections/focus contexts, not Jellyfin items.
Series/episode membership and collection positions are separate identities too.

Keep four kinds of state separate:

- **Item metadata:** server-backed title, overview, image tags, people, genres, and
  other `BaseItemDto` fields.
- **User data:** `UserItemDataDto` fields including Played, PlaybackPositionTicks,
  Favorite, PlayCount, and LastPlayedDate.
- **Collection state:** server/query-derived membership and ordering for Continue,
  Recently Added, Latest, Next Up, filters, and search results.
- **Navigation and focus:** route/coordinator state and semantic group/item focus IDs.

An item update should not recreate a route or change a tile's identity. Membership or
ordering changes may remove or move a tile and need the existing focus restoration rules.

### Existing propagation and current stale-state paths

- `Notifications` is a typed wrapper over `NotificationCenter` with Combine publishers.
  `itemUserDataDidChange` now carries an `ItemUpdate` with user-session ID, item ID,
  request-start revision, and user-data or playback-position change. A matching
  `PagingLibraryViewModel` patches both published arrays, field-merges user data, then
  calls the library's `onItemUserDataChanged` hook. tvOS poster/card presentation reads
  the session's shared `ItemState`; the DTO patch remains for iOS and paging-library
  consumers that still own their snapshots.
- `itemMetadataDidChange` carries a `BaseItemDto`. Home records the signal and refreshes
  its provider groups. Automatically refreshing Movies/TV Shows libraries invalidate
  and re-query. Ordinary paging models do not merge the metadata payload into their
  matching elements, so a metadata notification alone is not an app-wide item update.
- `didSendStopReport` still carries an item ID after Jellyfin accepts a stop report.
  Home uses it for return/focus coordination, and `ItemView` fetches its item only when
  the stopped ID is exactly the Details provider ID. In addition, accepted tvOS progress
  and stop reports publish typed item updates; retained Movies/TV Shows libraries use
  those to update cards and consult active filters/sorts before querying. The unused
  `didSendResumeProgressReport` signal has been removed; acknowledged ticks travel
  through `itemUserDataDidChange`.
- `ItemContentGroupProvider` retains a full-item metadata snapshot and resolves a playback
  provider locally. All tvOS `ItemView` Details routes observe the session's `ItemState`
  for the current item; Show Details also observes the selected play target for
  Play/Resume presentation. Accepted watched/favorite changes publish typed updates,
  and the Details provider relays shared-state changes without rebuilding the route.
  Playback target metadata/source selection, groups, trailers, backdrop, and route/focus
  state remain locally owned. Home, Live TV, and Search result posters use the same
  session store. Search query/results and its title-only suggestion array remain local.
  Episode-card metadata and routing use the local DTO, with user-data presentation
  overlaid from that session's `ItemState`.
- Show Details episode rows remain nested paging models. A series-level unplayed response
  contains one `UserItemDataDto` for the requested series, not descendant episode DTOs;
  current upstream Jellyfin `MarkUnplayedItem` returns that single item result
  ([controller source](https://github.com/jellyfin/jellyfin/blob/master/Jellyfin.Api/Controllers/PlaystateController.cs#L1515-L1566)).
  The simulator server version and raw response body were not captured. A typed
  reconciliation request therefore queries the IDs already present in selected or
  previously loaded season rows. Only returned child user data is published as typed
  item updates; the season collections are not refetched or recreated. The separate
  itemShouldRefreshMetadata notification and row-revision repair have been removed. The
  season selector itself displays titles only. The separate Seasons poster group displays
  the season DTO's server userData through the existing poster indicators; it does not
  recompute season aggregates from episodes. Loaded season IDs are included in the same
  authoritative reconciliation query.
- `ContentGroupViewModel` listens for Home and Search collection-impacting item updates
  and metadata refresh signals. It targets only affected collection groups for watched
  state, Continue membership, and Search filter/sort results; Home deletion remains
  targeted too. Focus coordination defers Home's targeted queries while Details owns
  the Home return. Home global refresh remains broad. The Continue row and Play Next
  overlay keep separate list models and re-run their own derivation/query paths. The
  player overlay now applies the same targeted membership decision to its independent
  Continue list when an update arrives while that overlay is visible.
- Retained tvOS Movies and TV Shows libraries use `PagingLibraryViewModel` automatic
  refresh for metadata, global-refresh, and connection-change signals. Typed deletion
  and user-data updates invalidate old results; they query again only when deletion or
  an active user-data filter/sort requires it. Matching item presentation updates remain
  immediate. Generic nested `ItemLibrary` routes receive the store and refresh only when
  an active user-data filter or sort can change their collection. Query/order ownership
  remains local.
- `ServerSocketManager` already exposes a Combine event stream and command/subscription
  publishers. The app consumes playback commands and session information; activity and
  task publisher helpers also exist. No consumed Jellyfin socket event currently
  updates item metadata, user data, or collection membership. There is no shared media
  DTO cache/invalidation layer; image caches are separate.

The migration keeps the existing MVVM split between item facts and collection snapshots:
tvOS views observe shared user data while each library still owns its query, metadata,
membership, order, and paging.

### Architecture options

| Approach | Churn and migration | Main benefit | Main cost/risk |
| --- | --- | --- | --- |
| **A. Improve local invalidation** | Lowest initial churn; extend typed notifications and add handlers to each DTO-owning view model. | Fits current code and keeps collection ownership unchanged. | Coverage remains distributed across Home, Details, Search, and nested episode models; each new owner can miss an event, and local copies remain a continuing stale-state risk. |
| **B. Shared store for all item and collection state** | Highest churn; collections and views would need to stop owning DTO snapshots and instead use canonical records. | One obvious source for item state and simple cross-surface propagation after migration. | Collection query/order and item facts become coupled; broad call-site changes, migration risk, and a strong store can retain every visited item. Refetch/diff changes could also disturb focus. |
| **C. Shared item state plus local collection models** | Moderate, incremental churn; keep paging, search, and Home list models, while migrating visible item views to shared observable state. | Centralizes live metadata/user-data while preserving current collection and SwiftUI/MVVM boundaries. Stable collection IDs keep focus independent. | Requires a defined merge/update event and collection-specific invalidation; during migration, unmigrated DTO owners still need the event adapter. |

**Implemented: C.** Add a session-scoped observable item-state service, not a new app-wide
architecture. Keep each library responsible for its query, membership, order, paging,
and filter environment. Keep `PagingLibraryViewModel` and existing
`ContentGroupViewModel` refresh/coalescing behavior as the collection layer while individual
surfaces migrate. This gives visible item views one live state without replacing the
app's MVVM model or rewriting routes and collections.

### Implemented Phase 1 shape and update flow

Use the existing Combine/`ObservableObject` conventions in `Shared`; a new Observation
framework or persistence schema is not required.

Phase 1 adds three concrete types in `Shared`: `ItemState` and `ItemStateStore` in
`Shared/Objects/ItemState.swift`, plus `ItemUpdate` in
`Shared/Services/Notifications.swift`. `ItemState` is a main-actor observable keyed by
Jellyfin item ID. It owns only canonical `UserItemDataDto`; each card keeps using its
library `BaseItemDto` for metadata and routing.

`UserSession` gets a unique UUID and lazily owns its store. `UserSession.willStop()`
resets an already-created store and cancels its notification subscription. Views strongly
hold state only while the poster is alive; the store uses weak state references and
prunes dead entries. It keeps at most 512 latest item updates as bounded replay/revision
history, applying a cached update after a library snapshot seeds a newly materialized
state. The session UUID on each update prevents same-item IDs from another session or
server reaching this store.

Mutation and playback report producers capture a monotonic request-start revision and
the originating session before starting the request. Only an accepted response/report
posts an `ItemUpdate`. When state fields merge, non-nil fields overwrite their matching
user-data fields, including explicit `false` and `0`; nil fields preserve the canonical
value. Item metadata is never merged from a user-data response. Updates with an older
revision are ignored by both `ItemState` and each paging model, whose revision history
is also capped at 512 entries. This prevents late replies from an earlier request from
overwriting newer watched/favorite/progress values.

The `itemUserDataDidChange` payload now supports `.userData`,
`.playbackPositionTicks`, and `.playbackStopped(positionTicks:)`. Existing server-backed
poster and Details toggles, series-unwatch flow, and playback-completion path publish
the returned `UserItemDataDto`. Accepted tvOS playback progress/stop reports publish
the acknowledged ticks. The old `itemShouldRefreshMetadata` user-data repair signal was
removed after episode cards adopted the shared store and series descendants gained an
authoritative ID query. `didSendStopReport`, metadata, and library membership hooks remain
for their other consumers. Home and Search consume same-session typed updates through
shared poster presentation and collection-specific invalidation. Episode-card user data
is session-shared; metadata remains in each episode DTO.

The retained Movies and TV Shows tabs explicitly opt into the shared store. Their grid
poster wrapper observes the item state and feeds a user-data-updated copy of the same
page DTO into the existing `PosterButton`. `CollectionVGrid` still identifies and
focuses cards by the original element ID; no new focus state, route, or focus request is
introduced. The store changes presentation in place while collection/page view models
continue to own membership, order, paging, filters, search, and queries.

`PagingLibraryViewModel` retains its matching-ID DTO patch for loaded main/search arrays
and calls each library's existing membership hook. `ItemLibrary` refreshes only when
an active played/unplayed/favorite/liked trait or status/date/count sort can be affected;
playback-position presentation updates do not query Movie/TV collections. A targeted
membership/order refresh advances the collection generation before starting its query,
so an older in-flight snapshot cannot replace it. Automatic initial loads are rescheduled
when invalidated before completion. Other library types keep their existing refresh policy.

### Migration coverage and remaining scope

1. **Completed: shared poster/tile path in Movies and TV Shows.** The library snapshots
   seed the session-scoped state, and the retained Movies and TV Shows grids observe it.
   Collection ownership and filter-driven invalidation remain local. Home and Search
   result posters use the same shared state.
2. **Completed: Movie and top-level TV Show Details.** The provider keeps full-item
   metadata locally and overlays same-session shared user data for the Details item and
   selected play target. Server-accepted watched/favorite changes publish typed updates;
   the Details view and retained Movies/TV Shows cards observe the same item state. The
   playback-stop full-item fetch remains for authoritative metadata and playback-provider
   refresh. Details action callbacks no longer
   mutate a private user-data copy; successful server responses publish the shared update.
   Full snapshots seed user data only while an item's typed-update revision is still zero;
   later snapshots refresh metadata without overwriting accepted watched/favorite/progress
   state. Superseded fetch generations are discarded. Details routes, groups, and focus
   ownership remain local.
3. **Completed: Show Details episode rows (Phase 3).** On tvOS, loaded episode cards
   observe the session's ItemState while retaining their full server metadata DTO for
   labels, images, routing, and actions. Episode pages seed state from the server only
   before a newer typed update exists; later user-data snapshots are overlaid from the
   canonical state. After a server-accepted series-level unplayed mutation, the Show
   Details owner queries exact IDs in loaded season rows and publishes only the returned
   child user data. Loaded season IDs are queried as well, so the season poster group
   receives server-backed user data without a client-side aggregate. This avoids season
   collection refetches and episode-row identity changes. Session IDs gate both the
   reconciliation trigger and response; request-start revisions let a later progress
   or mutation update win. Runtime checks on the Apple TV 4K (3rd generation) 1080p
   simulator loaded two Arcane seasons. An individual episode Played action appeared on
   the loaded card after returning from Episode Details; a later series Mark Unwatched
   cleared that marker in place while the action stayed focused. Playback stop showed
   acknowledged progress on the same loaded episode card without reopening Show Details;
   after starting playback from the episode artwork, Back restored focus to that exact
   episode's metadata while its progress indicator remained visible.
   An explicit near-end Play Next transition marked the finished episode watched in
   place, advanced Continue to the next episode, and a subsequent series Mark Unwatched
   cleared the completed marker. After that reset, Arcane was absent from the Home
   Continue row through its rightmost focused card. The exact before/after response DTOs
   were not captured, and no clear season-level aggregate indicator was visible at
   runtime; source inspection confirms season indicators use server-provided Season DTO
   user data and do not locally aggregate episode state. No physical Apple TV was tested.
4. **Implemented: Home and Continue (Phase 4; runtime verification incomplete).** The tvOS
   Home poster path observes session-scoped ItemState while retaining each library DTO
   and row identity. Continue, Recently Played, and deleted-item membership changes
   requery only affected Home collections. Focus deferral remains in ContentGroupViewModel.
5. **Completed: Search result cards (Phase 5; simulator validation partial).** Search
   cards observe session-scoped `ItemState`; query text, suggestions, result-group
   membership/order, paging, loading/error state, and focus remain Search-owned. Search
   targets result groups whose active played/favorite traits or user-data sorts can
   change membership/order. Presentation-only updates do not reload Search. Simulator
   checks passed for focus movement and the Details return path; the same Arcane result
   returned focused with its updated favorite badge. Playback progress has no clean
   before/after card result yet, and request-error behavior remains source-reviewed but
   runtime-unverified. Suggestions remain a title-only local DTO array.

The final tvOS audit found three stale-prone paths and migrated them in this pass:
generic nested `ItemLibrary` routes, BaseItem DTO shelves owned by `ContentGroupView`
(including Live TV recordings), and the player Up Next Continue shelf. Poster actions
now receive the updated item snapshot as well as displaying it, so direct Play/Resume
uses the current shared user data. Search invalidation, library ordering, and route/card
identity remain owned by their existing models. No process-wide DTO cache was added.

| Surface | Classification | Current ownership / reason |
| --- | --- | --- |
| Movies and TV Shows tab grids | A | Grid posters observe session `ItemState`; page DTOs still own metadata and collection state. |
| Home, Continue, Recently Added/Played, Latest, and recommendations | A | `ContentGroupView` supplies the session store to poster shelves; only affected membership/order groups query again. |
| Live TV recording and other BaseItem poster shelves | A | `ContentGroupView` now supplies the store to all tvOS content-group providers. Program airing/time indicators remain server schedule data. |
| Search result groups | A | Result posters observe `ItemState`; active user-data filters/sorts refresh affected groups only. |
| Movie, Show, Episode, and other `ItemView` Details routes and related shelves | A | Provider actions and related poster groups observe the same item/play-target state; route and metadata DTOs stay local. |
| Loaded Show Details episode cards and season posters | A | Cards observe the store; episode and season metadata remain in their paging DTOs. |
| Playback episode selector / queue | A | `EpisodeLibrary` seeds from `ItemState`; the active paging model applies typed updates and rejects older item revisions. |
| Direct playback chapter and people poster buttons | C | Chapter controls show seek positions, and people posters show cast metadata; neither renders mutable item user data. |
| Generic nested `ItemLibrary` routes, including Media favorites | A | The route supplies `ItemState`; its existing library refreshes only when an active user-data filter or sort can change membership/order. |
| Player Up Next Continue shelf | A | Poster presentation and actions use current shared state; its separate Resume query refreshes only for membership/order changes. |
| iOS My Media tab's `UserViewLibrary` root | C | The root shows library names and artwork, not mutable user-data presentation. Its nested item routes are classified above. |
| Search suggestions | C | The separate suggestion list shows titles only. |
| Cast/crew and other metadata-only library rows; list-style library rows | C | They show person or server metadata and do not read mutable user data for presentation. |
| Settings poster preview | C | It uses synthetic preview state, not a live user item. |
| Top Shelf | D | Remains an app-group file projection. The writer now resolves each item's progress from shared state before serializing, preventing an older Continue query DTO from overwriting a newer acknowledged progress value. |
| iOS item presentation | E | Existing DTO-backed behavior remains unchanged. A future iOS migration is separate optional work. |

No meaningful category-B tvOS presentation surface remains after this pass.

### tvOS presentation adoption and collection invalidation

`ContentGroupView` supplies the current session's store to all tvOS content-group trees;
`SearchView`, generic nested library routes, Details, and the player Up Next shelf supply
the same session store at their own boundaries. `PosterHStack` and grid posters use the
shared poster wrapper whenever a store is present. It applies canonical user data to the
same `BaseItemDto` metadata snapshot and passes that updated snapshot to the existing
action. Card IDs, row order, route ownership, and focus registrations stay with their
existing views and models.

| Surface | Disposition | Collection responsibility |
| --- | --- | --- |
| Continue / Cinematic Selection | Migrated | `ResumeItemsLibrary` still fetches Resume, Next Up, and recent completion data, deduplicates by series, and sorts by activity. A new positive progress value can add an unloaded item; clearing progress can remove a loaded item; watched state, accepted stop, and server-derived ordering changes target this row. Repeated positive progress refreshes are limited to one query per 30 seconds. |
| Recently Added Movies and Shows | Migrated | `dateCreated` query and ordering stay local; user-data changes patch presentation without a collection query. |
| Recently Played | Migrated | Existing `ItemLibrary` played filter and `datePlayed` ordering decide when watched/stop updates require a targeted query. |
| On Now / Recommended Programs | Migrated | Server airing membership remains local; item user-data updates do not requery the row. |
| Latest in each library | Migrated | Premiere/date-created server ordering remains local; user-data updates do not requery the row. |
| Search result groups | Migrated | Search owns query membership, order, paging, and group identity. Active user-data traits/sorts trigger targeted group refreshes; presentation-only updates use `ItemState` without a query. |
| Search suggestions | Local title DTOs | Suggestions are separate from result cards and display only titles; no user-data-derived presentation is shown. |
| Generic nested `ItemLibrary` grids | Migrated | Route supplies `ItemState`; a targeted query runs only when an active played/favorite trait or user-data sort changes membership/order. |
| Live TV recording shelf | Migrated | Uses the same `ContentGroupView` store; recording membership and metadata stay library-owned. |
| Player Up Next Continue shelf | Migrated | Its separate Resume model refreshes only when Continue membership/order may change. |

`ItemUpdate.CollectionImpact` marks watched/membership mutations separately from
presentation-only favorite and progress patches. Progress updates still pass through
Continue's local membership check: a positive tick value targets the Resume query only
when the item is not loaded, and zero targets it only when the item is loaded. An
accepted stop always targets Continue, allowing the server to remove a completed item
or supply its next episode. Other Home `ItemLibrary` rows retain their own filter/sort
rules. Home deletion targets only rows that still contain the item ID.

Search has a targeted invalidation hook because an item that begins matching an active
Search trait may not already be in a loaded result page. `ItemLibrary` evaluates only the
active played/favorite filters and user-data sorts; each affected result group advances
its collection generation and refreshes independently. The Search check also re-evaluates
a favorite change marked presentation-only when a favorite filter/sort is active.
Playback-position-only updates do not query Search. Query text changes still rebuild
Search groups through the existing Search flow.

| Search refresh/update path | Phase 5 disposition | Reason |
| --- | --- | --- |
| Query or filter change | Required; retained | Search owns query semantics, membership, result order, and paging. |
| User-data update with an active matching trait/sort | Required; targeted to result groups whose active criteria can change | Membership/order may change, including a result not currently loaded. |
| User-data update with no affected trait/sort | No Search query | Visible poster appearance comes from `ItemState`. |
| Matching-ID DTO patch in `PagingLibraryViewModel` | Retained | It keeps the paging snapshot current for iOS Search and other DTO consumers; tvOS Search poster appearance reads `ItemState`. |
| Deleted result ID | Required; retained | The paging model removes the matching element directly. |
| Search suggestions | Retained | First-appearance lookup shows titles only and is separate from result presentation. |

The old Home refresh-all path for every `.userData` update and every accepted playback
stop was removed. The focus coordinator still observes stop reporting, and targeted
collection queries queue while Home refresh deferral is active. Metadata and explicit
global refresh signals remain broad because they can affect metadata or collection
results across multiple rows. A targeted result resolves row visibility through the
existing candidate-group order; no provider rebuild or row reorder is added.

The Home, Search, automatic library, nested-library, and player Continue paths advance
their owning collection generation before a targeted replacement, rejecting older
membership/order snapshots. Presentation-only updates do not start Home, Search, or
library-wide queries. Top Shelf is a separate file projection; its writer overlays the
shared user data before reading progress into the snapshot so a stale page DTO cannot
restore older progress.

The final signed tvOS simulator build/install passed on Apple TV 4K (3rd generation,
1080p), retained the app-group container, and launched the app in place. Device Hub
controls were available for input. Movies poster → Details → Back returned focus to the
originating poster; the same exact-card return passed for TV Shows and a Search result.
Each Details return used one Back press. A presentation-only favorite toggle changed the
focused Details control in place; reversing it and returning to the library restored the
original favorite value and exact originating card focus. A loaded Episode 1 card showed
a progress label and bar after a brief play/pause interaction and return to Show Details.
Home showed the Continue row with its first card focused and progress indicators. Episode
progress semantics beyond that visible update, membership-refresh focus, completion/Next
Up, series-wide Mark Unwatched, and every directional boundary remain runtime
`UNVERIFIED`. No physical Apple TV was used.

### Final legacy mechanism dispositions

| Mechanism | Disposition | Remaining responsibility |
| --- | --- | --- |
| `itemUserDataDidChange` | Retained | Shared-state publication; iOS and paging DTO patches; targeted collection invalidation for Home, Search, nested `ItemLibrary`, and the player Continue list. |
| `itemMetadataDidChange` | Retained | Server-authoritative metadata refresh for Home and automatically refreshing libraries. Metadata payloads are not merged into arbitrary DTOs. |
| `didSendStopReport` | Retained | Home return/focus coordination and exact-ID Details full-item refresh for metadata and playback-provider state. Typed updates own progress/watched presentation. |
| `didSendResumeProgressReport` | Removed | No subscribers remained; acknowledged progress ticks now use the typed item update. |
| `didDeleteItem` | Retained | Remove deleted items or invalidate affected collection snapshots. |
| `seriesDescendantUserDataNeedsReconciliation` | Retained | Query exact loaded season/episode IDs after a server-accepted series-level unwatch. |
| `didRequestGlobalRefresh` | Retained | Explicit and recovery refreshes when targeted authoritative state is unavailable; not used for ordinary presentation-only updates. |
| `itemShouldRefreshMetadata` and episode-row revision repair | Removed in Phase 3 | Replaced by exact-ID descendant user-data reconciliation. |
| Paging model's matching-ID DTO patch | Retained temporarily | iOS presentation and paging consumers that still own DTO snapshots; tvOS poster/card presentation observes `ItemState`. |
| Movie/Show Details stop fetch | Retained | Authoritative metadata and playback-provider refresh, beyond the shared progress value. |

### Architecture health review

- **Session isolation:** each `UserSession` lazily owns a store keyed to its UUID;
  updates with another session ID are ignored. Stopping the session clears the store
  and cancels its subscription.
- **Lifetime and memory:** the store holds weak `ItemState` references and prunes dead
  entries every 64 lookups. Its replay history is capped at 512 item updates and each
  entry keeps only one compact user-data update. Live views are the strong owners.
- **Revision and merge rules:** request-start monotonic revisions reject older accepted
  replies. Non-nil fields merge independently, so `false` and `0` are preserved while
  absent fields keep the current value. No item metadata is copied from user-data updates.
- **Stale fetches:** collection generations protect Home, Search, and opted-in library
  replacement queries. Details snapshot generations and item revisions prevent an older
  fetch from replacing newer user data. The player Continue list now refreshes only for
  its own membership/order changes.
- **Publication and query scope:** no duplicate `ItemUpdate` publication path was found.
  The separate stop signal serves focus/metadata owners. Presentation-only progress
  updates do not cause Home-wide or library-wide queries; Home/Search/nested libraries
  and the player Continue list use their active membership/order rules.
- **Top Shelf projection:** the file-backed projection remains separate by design. A
  concrete stale-progress race existed when a pre-update Continue query completed after
  an acknowledged progress update; the writer now reads progress from shared state before
  serialization.
- **iOS:** no iOS surface was migrated. Its DTO-backed update path remains intact; any
  iOS adoption is separate optional work.

Focus, route, playback-session, and progress ownership stay outside the item store.

### Earlier phase verification history

#### Phase 1

Phase 1 changed source and passed the signed Apple TV 4K (3rd generation) 1080p
simulator build/install. Runtime checks confirmed Movies watched-state presentation
updated on the retained grid and focus returned to the originating card after Details;
TV Shows also returned to its originating card, but its action did not expose a clear
visual state change. Playback progress/stop reporting was exercised through a short
playback session, but the progress delta was too small to verify the card value. Other
sort order was changed to descending and restored to ascending successfully. A
tvOS filter mutation was not exercised; the filter drawer is only attached to the iOS
library body. Other focus boundaries and hidden-control behavior remain unverified, and
no physical Apple TV was tested.

#### Phase 2

Phase 2 changed source and passed the signed Apple TV 4K (3rd generation) 1080p
simulator build/install. Runtime checks on the retained app session confirmed Movie and
Show Details initially focus Play; Movie watched state updates immediately and can be
reversed while its action retains focus; Show favorite state updates immediately and
reverses while its action retains focus; and Back returns to the exact originating
poster with its updated watched/favorite treatment. The Show action-to-season-selector-
to-episode path and one-layer Back behavior passed. A series-wide Mark Unwatched
invocation did not produce a visible state change during this run, so that mutation is
unverified. A brief movie playback produced an acknowledged resume value: after stop,
Details displayed `2h 15m` without reopening the route. The retained Movies poster
remained present, but the progress fraction from this short run was too small to confirm
visually on its compact indicator; retained-poster progress is therefore unverified.
No manual refresh was used, and no physical Apple TV was tested. Build/install does not
establish behavior on physical hardware.
