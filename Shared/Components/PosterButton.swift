//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import JellyfinAPI
import SwiftUI

struct PosterButton<Item: Poster>: View {

    @Environment(\.episodeRouteOrigin)
    private var inheritedEpisodeRouteOrigin

    @Environment(\.posterConfiguration)
    private var posterConfiguration

    @Environment(\.viewContext)
    private var viewContext

    @Default(.accentColor)
    private var accentColor

    @Namespace
    private var namespace

    #if os(tvOS)
    @FocusState
    private var isFocused: Bool
    @Environment(\.launchFocusFirstPoster)
    private var launchFocusFirstPoster
    @Environment(\.initialTabCandidateReady)
    private var initialTabCandidateReady
    @Environment(\.initialTabCandidateFocused)
    private var initialTabCandidateFocused
    @Environment(\.homeTileCoordinator)
    private var homeTileCoordinator
    @Environment(\.screenTheme)
    private var screenTheme
    @Environment(\.homeFocusGroup)
    private var homeFocusGroup
    @Environment(\.posterHStackFocusController)
    private var posterHStackFocusController
    @Environment(\.posterHStackFocusIndex)
    private var posterHStackFocusIndex
    @Environment(\.homeFocusTile)
    private var homeFocusTile
    #endif

    @State
    private var posterSize: CGSize = .zero

    let item: Item
    let displayType: PosterDisplayType
    let size: PosterDisplayType.Size
    let routeFocusCoordinator: FocusCoordinator?
    let routeFocusTargetID: String?
    let routeEpisodeOrigin: EpisodeRouteIntent.Origin?
    let action: (Namespace.ID) -> Void

    init(
        item: Item,
        displayType: PosterDisplayType,
        size: PosterDisplayType.Size = .small,
        routeFocusCoordinator: FocusCoordinator? = nil,
        routeFocusTargetID: String? = nil,
        routeEpisodeOrigin: EpisodeRouteIntent.Origin? = nil,
        action: @escaping (Namespace.ID) -> Void
    ) {
        self.item = item
        self.displayType = displayType
        self.size = size
        self.routeFocusCoordinator = routeFocusCoordinator
        self.routeFocusTargetID = routeFocusTargetID
        self.routeEpisodeOrigin = routeEpisodeOrigin
        self.action = action
    }

    @ViewBuilder
    private var contextMenuPreview: some View {
        buttonLabel()
            .frame(width: posterSize.width)
            .padding(20)
            .backport
            .glassEffect(in: .rect)
    }

    #if os(tvOS)
    private var removesRecentlyAddedMoviesShadows: Bool {
        homeFocusGroup == "recently-added-movies"
    }

    private var usesSemanticPosterTheme: Bool {
        viewContext.contains(.isMovieDetails) ||
            viewContext.contains(.isSearchResults) ||
            viewContext.contains(.isMoviesTVLibrary) ||
            viewContext.contains(.isPlaybackOverlay) ||
            homeFocusTile != nil
    }

    private var focusOutlineColor: Color {
        usesSemanticPosterTheme ? screenTheme.focus.keylineOnSurface.swiftUIColor : accentColor
    }

    private var focusGlowColor: Color {
        usesSemanticPosterTheme ? screenTheme.focus.glow.swiftUIColor : accentColor
    }

    private var focusOutlineOpacity: Double {
        usesSemanticPosterTheme ? 1 : 0.95
    }

    private var focusedPosterScale: CGFloat {
        guard isFocused else { return 1 }
        if posterHStackFocusController != nil {
            return 1.06
        }
        if homeTileCoordinator == nil {
            return 1.035
        }
        return homeFocusGroup == "recently-added-movies" ? 1.06 : 1
    }

    #endif

    private var contextMenuEpisodeOrigin: EpisodeRouteIntent.Origin? {
        guard let baseItem = item as? BaseItemDto,
              baseItem.type == .episode,
              let itemID = baseItem.id
        else { return nil }

        if let routeEpisodeOrigin, routeEpisodeOrigin.itemID == itemID {
            return routeEpisodeOrigin
        }

        if let inheritedEpisodeRouteOrigin,
           inheritedEpisodeRouteOrigin.itemID == itemID
        {
            return inheritedEpisodeRouteOrigin
        }

        #if os(tvOS)
        if let homeFocusTile {
            return EpisodeRouteIntent.Origin(
                source: .home(groupID: homeFocusTile.groupID),
                itemID: itemID
            )
        }
        #endif

        return nil
    }

    @ViewBuilder
    private func posterImage(overlay: some View) -> some View {
        PosterImage(
            item: item,
            type: displayType,
            size: size
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #if os(tvOS)
        .overlay {
            if homeTileCoordinator != nil {
                Rectangle()
                    .fill(Color.black.opacity(isFocused ? 0 : 0.08))
                    .animation(.easeOut(duration: 0.1), value: isFocused)
                    .allowsHitTesting(false)
            }
        }
        #endif
        .overlay { overlay.posterStyle(displayType) }
        .contentShape(.contextMenuPreview, Rectangle())
        .matchedTransitionSource(id: "item", in: namespace)
        #if os(tvOS)
        .if(!removesRecentlyAddedMoviesShadows) { $0.subtleShadow() }
        #else
        .subtleShadow()
        #endif
        #if os(tvOS)
        .overlay {
            Rectangle()
                .stroke(
                    focusOutlineColor.opacity(isFocused ? focusOutlineOpacity : 0),
                    lineWidth: 3
                )
        }
        // Horizontal poster shelves keep artwork stable while they scroll.
        .scaleEffect(focusedPosterScale)
        .if(!removesRecentlyAddedMoviesShadows) {
            $0.shadow(
                color: isFocused ? focusGlowColor.opacity(homeTileCoordinator == nil ? 0.28 : 0.10) : .clear,
                radius: isFocused ? 16 : 0
            )
        }
        .animation(.easeOut(duration: 0.16), value: isFocused)
        #else
        .hoverEffect(.highlight)
        #endif
    }

    @ViewBuilder
    private func buttonLabel(overlay: some View = EmptyView()) -> some View {
        VStack(alignment: .leading) {
            posterImage(overlay: overlay)

            if posterConfiguration.showLabels {
                item.posterLabel
                    .allowsHitTesting(false)
            }
        }
    }

    var body: some View {
        Button {
            #if os(tvOS)
            if let homeFocusTile {
                homeTileCoordinator?.selectHomeTile(homeFocusTile)
            }
            #endif
            action(namespace)
        } label: {
            // Layout required for tvOS focused offset label behavior
            #if os(tvOS)
            VStack(alignment: .leading, spacing: 12) {
                posterImage(overlay: item.posterOverlay(for: displayType))

                if posterConfiguration.showLabels {
                    item.posterLabel
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            #else
            buttonLabel(overlay: item.posterOverlay(for: displayType))
                .trackingSize($posterSize)
            #endif
        }
        .environment(\.posterDisplayType, displayType)
        .foregroundStyle(.primary, .secondary)
        #if os(tvOS)
        .buttonStyle(ScreenPosterButtonStyle())
        .buttonBorderShape(.roundedRectangle(radius: 0))
        .focused($isFocused)
        .modifier(CoordinatedPosterFocusModifier(
            coordinator: routeFocusCoordinator,
            targetID: routeFocusTargetID,
            focused: $isFocused
        ))
        .focusedValue(\.focusedPoster, AnyPoster(item))
        .onChange(of: isFocused) { _, focused in
            guard focused, launchFocusFirstPoster == AnyPoster(item) else { return }
            initialTabCandidateFocused?()
        }
        .onChange(of: isFocused) { _, focused in
            guard focused else { return }
            let preservesHomeVerticalOffset = homeFocusTile.map {
                homeTileCoordinator?.consumeHomeVerticalScrollSuppression(for: $0) ?? false
            } ?? false
            DispatchQueue.main.async {
                guard isFocused, let index = posterHStackFocusIndex else { return }
                guard !preservesHomeVerticalOffset else { return }
                posterHStackFocusController?.scrollFocusedPoster(
                    at: index,
                    forceLayout: homeTileCoordinator == nil
                )
            }
        }
        .modifier(HomeTileFocusRegistration(
            coordinator: homeTileCoordinator,
            tile: homeFocusTile,
            focused: $isFocused
        ))
        .background {
            if launchFocusFirstPoster == AnyPoster(item) {
                LaunchFocusCandidateProbe(
                    onReady: {
                        initialTabCandidateReady?()
                        if isFocused {
                            initialTabCandidateFocused?()
                        }
                    }
                )
                .allowsHitTesting(false)
            }
        }
        .background {
            if let posterHStackFocusController,
               posterHStackFocusIndex == 0
            {
                LaunchFocusCandidateProbe(
                    onReady: {},
                    onLayout: { posterHStackFocusController.register(from: $0) }
                )
                .allowsHitTesting(false)
            }
        }
        #else
        .buttonStyle(.borderless)
        #endif
        #if os(tvOS)
        .environment(\.homeTileCoordinator, homeTileCoordinator)
        .environment(\.homeFocusTile, homeFocusTile)
        #endif
        .posterContextMenu(for: item, episodeRouteOrigin: contextMenuEpisodeOrigin) {
            contextMenuPreview
                .withViewContext(viewContext)
        }
    }
}

#if os(tvOS)
private struct CoordinatedPosterFocusModifier: ViewModifier {

    let coordinator: FocusCoordinator?
    let targetID: String?
    let focused: FocusState<Bool>.Binding

    private func apply(_ request: String?) {
        guard let coordinator,
              let targetID,
              request == targetID
        else { return }

        focused.wrappedValue = true
        coordinator.clearRequest()
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if let coordinator, let targetID {
            content
                .onAppear {
                    apply(coordinator.request)
                }
                .onReceive(coordinator.$request) { request in
                    apply(request)
                }
        } else {
            content
        }
    }
}
#endif

#if os(tvOS)
/// Uses the poster's existing Boolean focus binding only for explicit restoration.
private struct HomeTileFocusRegistration: ViewModifier {
    let coordinator: FocusCoordinator?
    let tile: FocusCoordinator.HomeTile?
    let focused: FocusState<Bool>.Binding

    func body(content: Content) -> some View {
        if let coordinator, let tile {
            content.modifier(RegisteredHomeTile(coordinator: coordinator, tile: tile, focused: focused))
        } else {
            content
        }
    }
}

private struct RegisteredHomeTile: ViewModifier {
    @ObservedObject
    var coordinator: FocusCoordinator
    let tile: FocusCoordinator.HomeTile
    let focused: FocusState<Bool>.Binding

    func body(content: Content) -> some View {
        content
            .id(tile.target)
            .onReceive(coordinator.$request) { target in
                if target == tile.target {
                    if coordinator.isRestoringSidebarHomeFocus {
                        guard coordinator.request == tile.target,
                              coordinator.shouldRestoreHomeFocus(to: tile)
                        else { return }
                        focused.wrappedValue = true
                        return
                    }

                    // Apply FocusState outside the published coordinator update,
                    // then revalidate that this visible registration is current.
                    DispatchQueue.main.async {
                        guard coordinator.request == tile.target,
                              coordinator.shouldRestoreHomeFocus(to: tile)
                        else { return }
                        focused.wrappedValue = true
                    }
                }
            }
            .onChange(of: focused.wrappedValue) { _, isFocused in
                coordinator.recordHomeTileFocus(tile, isFocused: isFocused)
                if isFocused {
                    // Let SwiftUI commit the real focus change and its normal
                    // poster styling before clearing the restoration request.
                    DispatchQueue.main.async {
                        guard focused.wrappedValue else { return }
                        coordinator.homeTileAcquired(tile)
                    }
                }
            }
            .background {
                LaunchFocusCandidateProbe(
                    onReady: { coordinator.homeTileReady(tile) },
                    readinessID: coordinator.requestedHomeFocusTarget,
                    homeTile: tile,
                    onRequestFocus: { focused.wrappedValue = true },
                    onLayout: {
                        coordinator.registerHomeFocusTile(tile, from: $0)
                        coordinator.registerHomeRowScroller(groupID: tile.groupID, from: $0)
                    }
                )
                .allowsHitTesting(false)
            }
    }
}

private struct ScreenPosterButtonStyle: ButtonStyle {

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
#endif

#if os(tvOS)
extension EnvironmentValues {
    @Entry
    var launchFocusFirstPoster: AnyPoster? = nil
}

/// Signals once when the first Home tile is visible enough to accept focus.
struct LaunchFocusCandidateProbe: UIViewRepresentable {
    let onReady: (() -> Void)?
    var readinessID: String? = nil
    var homeTile: FocusCoordinator.HomeTile? = nil
    var onRequestFocus: (() -> Void)? = nil
    var onLayout: ((UIView) -> Void)? = nil

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: ProbeView, context: Context) {
        view.onReady = onReady
        view.onLayout = onLayout
        view.homeTile = homeTile
        view.onRequestFocus = onRequestFocus
        if view.readinessID != readinessID {
            view.readinessID = readinessID
            view.resetReadiness()
        }
        view.signalIfVisible()
    }

    final class ProbeView: UIView {
        var onReady: (() -> Void)?
        var readinessID: String?
        var homeTile: FocusCoordinator.HomeTile?
        var onRequestFocus: (() -> Void)?
        var onLayout: ((UIView) -> Void)?
        private var didSignalReadiness = false
        private var visibilityObservations: [NSKeyValueObservation] = []

        func resetReadiness() {
            didSignalReadiness = false
        }

        override func didMoveToSuperview() {
            super.didMoveToSuperview()
            observeVisibility()
            signalIfVisible()
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            observeVisibility()
            signalIfVisible()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            signalIfVisible()
        }

        private func observeVisibility() {
            visibilityObservations.removeAll()
            var ancestors: [UIView] = []
            var next: UIView? = self
            while let view = next {
                ancestors.append(view)
                next = view.superview
            }
            for view in ancestors {
                if let scrollView = view as? UIScrollView {
                    visibilityObservations.append(
                        scrollView.observe(\.bounds, options: [.new]) { [weak self] _, _ in
                            self?.signalIfVisible()
                        }
                    )
                }
                visibilityObservations.append(
                    view.observe(\.alpha, options: [.initial, .new]) { [weak self] _, _ in
                        self?.signalIfVisible()
                    }
                )
                visibilityObservations.append(
                    view.observe(\.isHidden, options: [.initial, .new]) { [weak self] _, _ in
                        self?.signalIfVisible()
                    }
                )
            }
        }

        func signalIfVisible() {
            onLayout?(self)
            guard !didSignalReadiness,
                  let onReady,
                  isVisibleFocusTarget()
            else { return }

            // UIViewRepresentable.updateUIView can run within a SwiftUI update.
            // Publish the restoration request on the next main-actor turn, then
            // validate again because CollectionHStack may have recycled the cell.
            didSignalReadiness = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard self.isVisibleFocusTarget() else {
                    self.didSignalReadiness = false
                    return
                }
                onReady()
            }
        }

        private func isVisibleFocusTarget() -> Bool {
            guard window != nil, !bounds.isEmpty else { return false }

            var effectiveAlpha: CGFloat = 1
            var next: UIView? = self
            var collectionView: UICollectionView?
            while let view = next {
                guard !view.isHidden else { return false }
                effectiveAlpha *= view.alpha
                if let scrollView = view as? UIScrollView,
                   !scrollView.bounds.intersects(convert(bounds, to: scrollView))
                {
                    return false
                }
                if collectionView == nil, let collection = view as? UICollectionView {
                    collectionView = collection
                }
                next = view.superview
            }

            guard effectiveAlpha > 0.99 else { return false }
            guard readinessID != nil else { return true }
            guard let collectionView else { return false }

            return collectionView.visibleCells.contains { cell in
                self.isDescendant(of: cell)
            }
        }
    }
}
#endif
