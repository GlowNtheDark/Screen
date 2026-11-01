# Focus system

The authoritative app-wide directional, Back-stack, entry-focus, and restoration
contract is [tvOS focus and navigation](focus-navigation-contract.md). This document
describes current focus ownership and mechanisms; it does not override that contract.

Contract: [focus restoration](../product-specs/focus-restoration.md).

[`FocusCoordinator`](../../Shared/Objects/FocusCoordinator.swift) publishes focused IDs
and requests. TV `HomeTile` carries group/item/series/index; its target combines group
and item identity. `selectHomeTile` records the origin. `homePlayerPresented(fromDetails:)`
records the actual player origin. `homePlayerDismissed` releases refresh deferral
but keeps a details-origin Home focus request dormant until `homeDetailsDismissed`.

[`ContentGroupView`](../../Shared/Views/ContentGroupView.swift) owns the Home coordinator,
observes refresh completion, and supplies row manifests/revisions. Content groups and
[`PosterHStack`](../../Shared/Components/PosterHStack.swift) expose rows;
[`PosterButton`](../../Shared/Components/PosterButton.swift) registers selection,
layout readiness, and acquired focus. The coordinator resolves the current fallback
order against refreshed rows, scrolls the underlying virtualized collection to the
target, and requests focus only once that tile is ready. Acquisition clears protection.

The Home coordinator also owns Up/Down between shelves. A recognizer on the vertical
Home scroll view claims these presses, resolves the immediately adjacent nonempty row,
and chooses among its attached visible tiles by live on-screen horizontal center, with
ties going to the earlier tile. It remembers the last source/destination pair while
both row memberships remain unchanged, so an immediate opposite press restores the
exact source. At the top and bottom rows, the press passes through to the existing
region boundary behavior; if the adjacent row has no eligible target, the press is
consumed rather than allowing spatial focus to skip that row. `PosterButton` suppresses
its queued horizontal row reveal for the vertical target, preserving shelf offsets.

[`MainTabView`](../../Shared/Coordinators/Tabs/MainTabView.swift) observes presentation
changes and protects the Home return from sidebar focus. Navigation ownership remains
with the navigation coordinators; focus events must not dismiss intermediate screens.

`ItemView` owns a separate coordinator initially targeting its Play action.
TV Search uses `@FocusState` in [SearchView](../../Shared/Views/SearchView.swift) plus
[`TVSearchFocusCoordinator`](<../../Screen tvOS/Extensions/View/View-tvOS.swift>) to
hand sidebar Right/Select entry to the app-owned field. iOS retains `.searchable`.
Do not assume keyboard/responder readiness proves remote focus has moved.

These are current mechanisms, including uncommitted work present at inspection.
Validate refresh, removed/replaced tiles, offscreen rows, and Back behavior at runtime;
see [QUALITY.md](../QUALITY.md).
