//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import CollectionHStack
import JellyfinAPI
import Nuke
import SwiftUI

enum PosterHStackMetrics {

    static let itemSpacing: CGFloat = {
        #if os(tvOS)
        40
        #else
        EdgeInsets.edgePadding / 2
        #endif
    }()

    #if os(tvOS)
    // Shared with the tvOS library grid so poster sizing follows Home's reference.
    static let landscapeColumns: CGFloat = 4
    static let portraitColumns: CGFloat = 5.75
    static let libraryLandscapeColumns = 4
    static let libraryPortraitColumns = 6
    static let libraryItemSpacing: CGFloat = 30
    #endif
}

#if os(tvOS)
final class PosterHStackFocusController {

    private weak var collectionView: UICollectionView?

    func register(from view: UIView) {
        var ancestor = view.superview
        while let current = ancestor {
            if let collection = current as? UICollectionView {
                register(collection)
                return
            }
            ancestor = current.superview
        }
    }

    func scrollFocusedPoster(at index: Int, forceLayout: Bool) {
        collectionView?.scrollFocusedPoster(at: index, forceLayout: forceLayout)
    }

    private func register(_ collection: UICollectionView) {
        guard collectionView !== collection else { return }
        collectionView = collection
        collection.configurePosterHStackFocusScrolling()
    }

    private func collectionView(in view: UIView) -> UICollectionView? {
        var ancestor: UIView? = view

        while let current = ancestor {
            let probeFrame = view.convert(view.bounds, to: current)
            if let collection = collectionViews(in: current).first(where: { collection in
                collection.convert(collection.bounds, to: current).intersects(probeFrame)
            }) {
                return collection
            }
            ancestor = current.superview
        }

        return nil
    }

    private func collectionViews(in view: UIView) -> [UICollectionView] {
        if let collection = view as? UICollectionView {
            return [collection]
        }

        return view.subviews.flatMap { subview in
            collectionViews(in: subview)
        }
    }
}
#endif

struct PosterHStack<
    Data: Collection
>: View where Data.Element: Poster, Data.Index == Int {

    @Environment(\.self)
    private var environment

    @State
    private var imagePrefetcher = ImagePrefetcher(
        pipeline: .Screen.posters,
        destination: .memoryCache,
        maxConcurrentRequestCount: UIDevice.isTV ? 3 : 2
    )

    #if os(tvOS)
    @State
    private var focusController = PosterHStackFocusController()
    #endif

    let elements: Data
    let displayType: PosterDisplayType
    let size: PosterDisplayType.Size
    let episodeRouteOriginContext: EpisodeRouteOriginContext?
    let routeFocusGroupID: String?
    let action: (Data.Element, Namespace.ID) -> Void

    init(
        elements: Data,
        displayType: PosterDisplayType,
        size: PosterDisplayType.Size,
        episodeRouteOriginContext: EpisodeRouteOriginContext? = nil,
        routeFocusGroupID: String? = nil,
        action: @escaping (Data.Element, Namespace.ID) -> Void
    ) {
        self.elements = elements
        self.displayType = displayType
        self.size = size
        self.episodeRouteOriginContext = episodeRouteOriginContext
        self.routeFocusGroupID = routeFocusGroupID
        self.action = action
    }

    #if os(tvOS)
    private var homeTiles: [FocusCoordinator.HomeTile] {
        guard environment.homeTileCoordinator != nil, let groupID = environment.homeFocusGroup else { return [] }
        var seen = Set<String>()
        return elements.enumerated().compactMap { index, item in
            guard let tile = FocusCoordinator.HomeTile.make(poster: item, groupID: groupID, index: index),
                  seen.insert(tile.itemID).inserted else { return nil }
            return tile
        }
    }
    #endif

    private var layout: CollectionHStackLayout {
        #if os(tvOS)
        .grid(
            columns: displayType == .landscape
                ? PosterHStackMetrics.landscapeColumns
                : PosterHStackMetrics.portraitColumns,
            rows: 1,
            columnTrailingInset: 0
        )
        #else
        if UIDevice.isPad {
            let minWidth: CGFloat = {
                switch (displayType, size) {
                case (.landscape, .small):
                    220
                case (.landscape, .medium):
                    300
                case (_, .small):
                    140
//                case (_, .medium):
                default:
                    200
                }
            }()

            return .minimumWidth(
                columnWidth: minWidth,
                rows: 1
            )
        } else {
            let columnCount: CGFloat = {
                switch (displayType, size) {
                case (.landscape, .small):
                    2
                case (.landscape, .medium):
                    1.5
                case (_, .small):
                    3
//                case (_, .medium):
                default:
                    2
                }
            }()

            return .grid(
                columns: columnCount,
                rows: 1,
                columnTrailingInset: 0
            )
        }
        #endif
    }

    private var horizontalInset: CGFloat {
        #if os(tvOS)
        60
        #else
        EdgeInsets.edgePadding
        #endif
    }

    private var posterScrollBehavior: CollectionHStackScrollBehavior {
        #if os(tvOS)
        .continuous
        #else
        .continuousLeadingEdge
        #endif
    }

    private func prefetchRequests(for elements: [Data.Element]) -> [ImageRequest] {
        elements.compactMap { element -> ImageRequest? in
            var resolvedEnvironment = element.resolveEnvironment(environment)

            if var viewContextEnvironment = resolvedEnvironment as? WithViewContext {
                viewContextEnvironment.viewContext.insert(.isThumb)
                resolvedEnvironment = viewContextEnvironment as! Data.Element.Environment
            }

            let url = element.imageSources(
                for: displayType,
                size: size,
                environment: resolvedEnvironment
            )
            .first?
            .url

            guard let url else { return nil }
            return ImageRequest(url: url)
        }
    }

    @ViewBuilder
    private func posterButton(for item: Data.Element) -> some View {
        let baseItem = item as? BaseItemDto
        let focusTargetID: String? = {
            guard let episodeRouteOriginContext,
                  let routeFocusGroupID,
                  let itemID = (item as? BaseItemDto)?.id
            else { return nil }

            return episodeRouteOriginContext.origin(
                groupID: routeFocusGroupID,
                itemID: itemID
            ).searchFocusTargetID
        }()
        #if os(tvOS)
        let episodeRouteOrigin: EpisodeRouteIntent.Origin? = {
            guard let baseItem, baseItem.type == .episode, let itemID = baseItem.id else { return nil }

            if let episodeRouteOriginContext, let routeFocusGroupID {
                return episodeRouteOriginContext.origin(groupID: routeFocusGroupID, itemID: itemID)
            }

            if let homeFocusTile = environment.homeFocusTile {
                return EpisodeRouteIntent.Origin(
                    source: .home(groupID: homeFocusTile.groupID),
                    itemID: itemID
                )
            }

            return nil
        }()
        #else
        let episodeRouteOrigin: EpisodeRouteIntent.Origin? = nil
        #endif

        #if os(tvOS)
        if let baseItem,
           let itemState = environment.itemStateStore?.state(for: baseItem)
        {
            ItemStatePoster(
                itemState: itemState,
                item: baseItem,
                displayType: displayType,
                size: size,
                routeFocusCoordinator: episodeRouteOriginContext?.focusCoordinator,
                routeFocusTargetID: focusTargetID,
                routeEpisodeOrigin: episodeRouteOrigin
            ) { updatedItem, namespace in
                action((updatedItem as? Data.Element) ?? item, namespace)
            }
        } else {
            standardPosterButton(
                for: item,
                focusTargetID: focusTargetID,
                episodeRouteOrigin: episodeRouteOrigin
            )
        }
        #else
        standardPosterButton(
            for: item,
            focusTargetID: focusTargetID,
            episodeRouteOrigin: episodeRouteOrigin
        )
        #endif
    }

    private func standardPosterButton(
        for item: Data.Element,
        focusTargetID: String?,
        episodeRouteOrigin: EpisodeRouteIntent.Origin?
    ) -> some View {
        PosterButton(
            item: item,
            displayType: displayType,
            size: size,
            routeFocusCoordinator: episodeRouteOriginContext?.focusCoordinator,
            routeFocusTargetID: focusTargetID,
            routeEpisodeOrigin: episodeRouteOrigin
        ) { namespace in
            action(item, namespace)
        }
    }

    var body: some View {
        CollectionHStack(
            uniqueElements: elements,
            layout: layout
        ) { item in
            posterButton(for: item)
                #if os(tvOS)
                    .environment(\.homeFocusTile, homeTiles.first { tile in
                        FocusCoordinator.HomeTile.make(poster: item, groupID: tile.groupID, index: tile.index)?.itemID == tile.itemID
                    })
                    .environment(\.posterHStackFocusController, focusController)
                    .environment(\.posterHStackFocusIndex, elements.firstIndex(of: item))
                #endif
        }
        .clipsToBounds(false)
        #if os(tvOS)
        .allowBouncing(false)
        #endif
        .insets(horizontal: horizontalInset)
        .itemSpacing(PosterHStackMetrics.itemSpacing)
        .onPrefetchingElements { elements in
            imagePrefetcher.startPrefetching(
                with: prefetchRequests(for: elements)
            )
        }
        .onCancelPrefetchingElements { elements in
            imagePrefetcher.stopPrefetching(
                with: prefetchRequests(for: elements)
            )
        }
        .scrollBehavior(posterScrollBehavior)
        .withViewContext(.isThumb)
        #if os(tvOS)
        .preference(key: HomeFocusRowsKey.self, value: environment.homeTileCoordinator == nil ? [] : [
            HomeFocusRow(
                groupID: environment.homeFocusGroup ?? "",
                order: environment.homeFocusRowOrder,
                revision: environment.homeFocusRevision,
                tiles: homeTiles
            ),
        ])
        #endif
    }
}

#if os(tvOS)
extension EnvironmentValues {
    @Entry
    var posterHStackFocusController: PosterHStackFocusController? = nil
    @Entry
    var posterHStackFocusIndex: Int? = nil
}

private extension UICollectionView {

    func scrollFocusedPoster(at index: Int, forceLayout: Bool) {
        guard window != nil,
              numberOfSections > 0,
              numberOfItems(inSection: 0) > index else { return }

        if forceLayout {
            layoutIfNeeded()
        }

        guard let layout = collectionViewLayout as? UICollectionViewFlowLayout,
              let attributes = layout.layoutAttributesForItem(at: IndexPath(item: index, section: 0))
        else { return }

        let leadingInset = layout.sectionInset.left
        let trailingInset = layout.sectionInset.right
        let visibleLeadingEdge = contentOffset.x + leadingInset
        let visibleTrailingEdge = contentOffset.x + bounds.width - trailingInset

        let targetOffset: CGFloat
        if attributes.frame.minX < visibleLeadingEdge {
            targetOffset = attributes.frame.minX - leadingInset
        } else if attributes.frame.maxX > visibleTrailingEdge {
            targetOffset = attributes.frame.maxX - (bounds.width - trailingInset)
        } else {
            return
        }

        let maximumOffset = max(0, contentSize.width - bounds.width)
        let clampedOffset = targetOffset.clamped(to: 0 ... maximumOffset)
        guard abs(clampedOffset - contentOffset.x) > 0.5 else { return }

        setContentOffset(contentOffset, animated: false)
        bounces = false
        alwaysBounceHorizontal = false
        UIView.animate(
            withDuration: 0.19,
            delay: 0,
            options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseOut]
        ) {
            self.setContentOffset(
                CGPoint(x: clampedOffset, y: self.contentOffset.y),
                animated: false
            )
        }
    }

    func configurePosterHStackFocusScrolling() {
        bounces = false
        alwaysBounceHorizontal = false
        decelerationRate = .fast
    }
}

#endif
