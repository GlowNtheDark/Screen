//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import JellyfinAPI
import SwiftUI

#if DEBUG
import OSLog

private let topShelfDiagnosticsLogger = Logger(
    subsystem: "com.snowfin.tvos",
    category: "TopShelf"
)
#endif

struct CinematicSelectionContentGroup: ContentGroup, HomeCollectionInvalidatableContentGroup {

    static let homeGroupID = "cinematic-selection"

    let id = Self.homeGroupID
    let viewModel: CinematicSelectionContentGroupViewModel

    var _shouldBeResolved: Bool {
        viewModel.hasResumeItems
    }

    func shouldRefreshHomeCollection(after update: ItemUpdate) -> Bool {
        viewModel.resumeViewModel.shouldRefreshCollection(after: update)
    }

    func shouldRefreshHomeCollection(afterDeletingItemID itemID: String) -> Bool {
        viewModel.resumeViewModel.shouldRefreshCollection(afterDeletingItemID: itemID)
    }

    func refreshHomeCollection() async {
        await viewModel.resumeViewModel.refreshCollectionForHomeChange()
    }

    init(resumeLibrary: ResumeItemsLibrary) {
        self.viewModel = CinematicSelectionContentGroupViewModel(
            resumeLibrary: resumeLibrary
        )
    }

    func body(with viewModel: CinematicSelectionContentGroupViewModel) -> some View {
        SelectionView(viewModel: viewModel)
    }

    private struct SelectionView: View {

        @ObservedObject
        var viewModel: CinematicSelectionContentGroupViewModel

        @Router
        private var router

        var body: some View {
            ContentGroupSection {
                CinematicItemSelector(
                    items: viewModel.continueItems
                ) { item in
                    router.route(to: .episode(
                        item: item,
                        origin: item.id.map {
                            EpisodeRouteIntent.Origin(
                                source: .home(groupID: CinematicSelectionContentGroup.homeGroupID),
                                itemID: $0
                            )
                        }
                    ))
                }
                .padding(.top, -16)
            } header: {
                Text(viewModel.resumeViewModel.library.parent.displayTitle)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .edgePadding(.horizontal)
                    .accessibilityAddTraits(.isHeader)
            }
        }
    }
}

final class CinematicSelectionContentGroupViewModel: ViewModel, WithRefresh {

    typealias Background = CinematicSelectionContentGroupViewModel

    let resumeViewModel: PagingLibraryViewModel<ResumeItemsLibrary>

    var background: CinematicSelectionContentGroupViewModel {
        get { self }
        set {}
    }

    var hasResumeItems: Bool {
        continueItems.isNotEmpty
    }

    var continueItems: [BaseItemDto] {
        Self.deduplicatedContinueItems(Array(resumeViewModel.elements))
    }

    init(resumeLibrary: ResumeItemsLibrary) {
        self.resumeViewModel = PagingLibraryViewModel(
            library: resumeLibrary,
            pageSize: 20,
            refreshesForItemStateChanges: true
        )

        super.init()

        resumeViewModel.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        let topShelfPublisher = resumeViewModel.$elements
            .dropFirst()
            .sink { elements in
                let items = Self.deduplicatedContinueItems(Array(elements))
                #if DEBUG
                topShelfDiagnosticsLogger.debug(
                    "[SCREEN_TOP_SHELF] Home Continue Watching publisher emitted elements=\(elements.count, privacy: .public) items=\(items.count, privacy: .public)"
                )
                #endif
                ScreenTopShelfSnapshotWriter.update(
                    items: items
                )
            }
        topShelfPublisher.store(in: &cancellables)
        #if DEBUG
        topShelfDiagnosticsLogger.debug(
            "[SCREEN_TOP_SHELF] Home Continue Watching publisher subscription established currentElements=\(self.resumeViewModel.elements.count, privacy: .public)"
        )
        #endif
    }

    func refresh() {
        Task {
            await refresh()
        }
    }

    func refresh() async {
        if resumeViewModel.elements.isEmpty {
            await resumeViewModel.refresh()
        } else {
            // Keep the current row until the replacement result is ready.
            // Foreground refresh clears its cells before fetching.
            await resumeViewModel.background.refresh()
        }
    }

    private static func deduplicatedContinueItems(_ items: [BaseItemDto]) -> [BaseItemDto] {
        var seenSeries = Set<String>()

        return items.filter { item in
            guard item.type == .episode else { return true }

            let seriesKey: String? = if let seriesID = item.seriesID, seriesID.isNotEmpty {
                "id:\(seriesID)"
            } else if let seriesName = item.seriesName?.trimmingCharacters(in: .whitespacesAndNewlines),
                      seriesName.isNotEmpty
            {
                "name:\(seriesName.lowercased())"
            } else {
                nil
            }

            guard let seriesKey else { return true }
            return seenSeries.insert(seriesKey).inserted
        }
    }
}
