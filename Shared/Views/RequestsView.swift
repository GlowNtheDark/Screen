//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

struct RequestsView: View {
    private enum Shelf: String, CaseIterable, Hashable {
        case trendingMovies
        case trendingShows
        case popularMovies
        case popularShows
        case upcomingMovies

        var title: String {
            switch self {
            case .trendingMovies: L10n.seerrMovieTrending
            case .trendingShows: L10n.seerrShowTrending
            case .popularMovies: L10n.seerrMoviePopular
            case .popularShows: L10n.seerrShowPopular
            case .upcomingMovies: L10n.seerrMovieUpcoming
            }
        }

        var mediaType: String {
            self == .trendingShows || self == .popularShows ? "tv" : "movie"
        }

        var isShow: Bool {
            mediaType == "tv"
        }

        var sortBy: String? {
            self == .popularMovies || self == .popularShows ? "popularity.desc" : nil
        }

        var isUpcoming: Bool {
            self == .upcomingMovies
        }
    }

    private struct ShelfState: Equatable {
        var titles: [SeerrTitle] = []
        var nextPage = 1
        var totalPages = 1
        var isLoading = false
        var error: String?
    }

    private struct RequestMediaKey: Hashable {
        let mediaType: String
        let mediaID: Int
    }

    private struct RequestAccountKey: Equatable {
        let serverURL: String
        let userID: Int
    }

    private enum FocusTarget: Hashable {
        case title(Shelf, Int)
        case status
    }

    @Environment(\.isTabContentFocusable)
    private var isTabContentFocusable

    @Environment(\.isTabContentActive)
    private var isTabContentActive

    @Environment(\.scenePhase)
    private var scenePhase

    @Environment(\.episodeRouteTabID)
    private var episodeRouteTabID

    @EnvironmentObject
    private var tabContentFocusHandoff: TabContentFocusHandoff

    @EnvironmentObject
    private var navigationCoordinator: NavigationCoordinator

    @Router
    private var router

    @Namespace
    private var detailsTransitionNamespace

    @Environment(\.screenTheme)
    private var screenTheme

    @FocusState
    private var focusedTarget: FocusTarget?

    @TabItemSelected
    private var tabItemSelected

    @State
    private var shelves = Dictionary(uniqueKeysWithValues: Shelf.allCases.map { ($0, ShelfState()) })
    @State
    private var error: String?
    @State
    private var hasLoaded = false
    @State
    private var isEntryFocusPending = false
    @State
    private var movieRequestStatuses: [SeerrRequestKey: SeerrPresentationStatus] = [:]
    @State
    private var activeRefresh: Task<Void, Never>?
    @State
    private var activeRefreshID: UUID?
    @State
    private var pendingPageLoads: [Shelf] = []
    @State
    private var isLoadingPage = false
    @State
    private var loadedAccount: RequestAccountKey?
    private var initialFocusTarget: FocusTarget? {
        for shelf in Shelf.allCases {
            if let title = shelves[shelf]?.titles.first {
                return .title(shelf, title.id)
            }
        }
        return nil
    }

    private var serverURL: String {
        UserDefaults.currentUserSuite.string(forKey: "seerr.serverURL") ?? ""
    }

    private var session: SeerrSession? {
        SeerrKeychain.session
    }

    private var isRequestsVisible: Bool {
        scenePhase == .active && isTabContentActive && navigationCoordinator.path.isEmpty &&
            navigationCoordinator.presentedSheet == nil && navigationCoordinator.presentedFullScreen == nil
    }

    var body: some View {
        Group {
            if serverURL.isEmpty || session == nil {
                ContentUnavailableView(
                    L10n.seerrNotConfigured,
                    systemImage: "link",
                    description: Text(L10n.seerrNotConfiguredDescription)
                )
                .focusable()
                .focused($focusedTarget, equals: .status)
            } else if let error, !hasLoaded {
                ContentUnavailableView(L10n.seerrTitleUnavailable, systemImage: "wifi.exclamationmark", description: Text(error))
                    .focusable()
                    .focused($focusedTarget, equals: .status)
            } else if !hasLoaded {
                ProgressView(L10n.seerrLoading)
            } else if hasLoaded && Shelf.allCases.allSatisfy({
                shelves[$0]?.titles.isEmpty != false && shelves[$0]?.error == nil
            }) {
                ContentUnavailableView(
                    L10n.seerrEmpty,
                    systemImage: "sparkles",
                    description: Text(L10n.seerrEmptyDescription)
                )
                .focusable()
                .focused($focusedTarget, equals: .status)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 36) {
                        ForEach(Shelf.allCases, id: \.self) { shelf in
                            if let state = shelves[shelf] {
                                titleSection(shelf, state: state) {
                                    Task { await loadNextPage(for: shelf) }
                                }
                            }
                        }
                    }
                    .edgePadding(.vertical)
                }
            }
        }
        .task(id: isRequestsVisible) {
            guard isRequestsVisible else { return }
            while !Task.isCancelled {
                await refresh()
                do {
                    try await Task.sleep(for: .seconds(60))
                } catch {
                    return
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .seerrRequestsChanged)) { notification in
            if let update = notification.object as? SeerrRequestUpdate {
                movieRequestStatuses[update.key] = update.status
                guard update.refreshDiscovery else { return }
            }
            if isRequestsVisible {
                Task { await refresh() }
            }
        }
        .onReceive(tabItemSelected) { event in
            guard event.isRepeat, event.isRoot else { return }
            isEntryFocusPending = true
            focusInitialContentIfReady()
        }
        .onChange(of: shelves) { _, _ in focusInitialContentIfReady() }
        .onChange(of: error) { _, _ in focusInitialContentIfReady() }
        .onChange(of: focusedTarget) { _, target in
            guard target != nil, isTabContentFocusable else { return }
            isEntryFocusPending = false
            tabContentFocusHandoff.complete(tabID: episodeRouteTabID)
        }
        .focusSection()
        .defaultFocus($focusedTarget, initialFocusTarget, priority: .userInitiated)
    }

    private func focusInitialContentIfReady() {
        guard isEntryFocusPending else { return }
        if let initialFocusTarget {
            focusedTarget = initialFocusTarget
        } else if hasLoaded || error != nil || serverURL.isEmpty || session == nil {
            focusedTarget = .status
        }
    }

    @ViewBuilder
    private func titleSection(
        _ shelf: Shelf,
        state: ShelfState,
        loadMore: @escaping () -> Void
    ) -> some View {
        if !state.titles.isEmpty || state.error != nil {
            ContentGroupSection {
                if let error = state.error {
                    HStack(spacing: 16) {
                        Text(error)
                            .foregroundStyle(.secondary)
                        Button(L10n.retry, action: loadMore)
                    }
                }
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: PosterHStackMetrics.itemSpacing) {
                        ForEach(Array(state.titles.enumerated()), id: \.element.id) { index, item in
                            let poster = SeerrPoster(title: item)
                            Button {
                                router.route(
                                    to: .seerrTitleDetails(title: item, isShow: shelf.isShow),
                                    in: detailsTransitionNamespace
                                )
                            } label: {
                                VStack(alignment: .leading, spacing: 12) {
                                    PosterImage(item: poster, type: .portrait, size: .small)
                                        .frame(width: posterWidth, height: posterHeight)
                                        .clipShape(RoundedRectangle(cornerRadius: posterCornerRadius))
                                        .matchedTransitionSource(id: "item", in: detailsTransitionNamespace)
                                        .overlay {
                                            RoundedRectangle(cornerRadius: posterCornerRadius)
                                                .stroke(
                                                    screenTheme.focus.keylineOnSurface.swiftUIColor
                                                        .opacity(isFocused(item, shelf: shelf) ? 1 : 0),
                                                    lineWidth: 3
                                                )
                                        }
                                        .shadow(
                                            color: isFocused(item, shelf: shelf)
                                                ? screenTheme.focus.glow.swiftUIColor.opacity(0.28)
                                                : .clear,
                                            radius: isFocused(item, shelf: shelf) ? 16 : 0
                                        )
                                    Text(item.displayTitle)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                        .lineLimit(2)
                                        .frame(width: posterWidth, alignment: .leading)
                                    if let status = posterStatus(for: item, isShow: shelf.isShow).posterLabel {
                                        Text(status)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                .accessibilityElement(children: .combine)
                            }
                            .buttonStyle(SeerrPosterButtonStyle())
                            .focused($focusedTarget, equals: focusTarget(for: item, shelf: shelf))
                            .onAppear {
                                if index >= state.titles.count - 5 {
                                    loadMore()
                                }
                            }
                        }
                    }
                    .focusSection()
                    .padding(.horizontal, PosterHStackMetrics.tvOSHorizontalInset)
                }
            } header: {
                Text(shelf.title)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .edgePadding(.horizontal)
                    .accessibilityAddTraits(.isHeader)
            }
        }
    }

    private func focusTarget(for item: SeerrTitle, shelf: Shelf) -> FocusTarget {
        .title(shelf, item.id)
    }

    private func posterStatus(for item: SeerrTitle, isShow: Bool) -> SeerrPresentationStatus {
        let status = item.presentationStatus
        guard !isShow, status == .unavailable, item.mediaInfo?.requests == nil,
              let mediaStatus = item.mediaInfo?.status,
              mediaStatus == 2 || mediaStatus == 3, let session
        else { return status }
        return movieRequestStatuses[SeerrRequestKey(session: session, mediaID: item.id)] ?? status
    }

    @MainActor
    private func refresh() async {
        guard isRequestsVisible else { return }
        if let activeRefresh {
            await activeRefresh.value
            guard !Task.isCancelled, isRequestsVisible else { return }
        }
        let refreshID = UUID()
        let task = Task { await loadSnapshot() }
        activeRefresh = task
        activeRefreshID = refreshID
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        if activeRefreshID == refreshID {
            activeRefresh = nil
            activeRefreshID = nil
        }
    }

    @MainActor
    private func loadSnapshot() async {
        guard !serverURL.isEmpty, let session else { return }
        let account = RequestAccountKey(serverURL: session.serverURL, userID: session.user.id)
        if let loadedAccount, loadedAccount != account {
            shelves = Dictionary(uniqueKeysWithValues: Shelf.allCases.map { ($0, ShelfState()) })
            hasLoaded = false
            error = nil
        }
        do {
            let client = try SeerrClient(url: serverURL)
            if hasLoaded {
                guard let requestResults = try? await client.requests(session: session) else { return }
                guard !Task.isCancelled, isRequestsVisible, self.session == session else { return }
                for shelf in Shelf.allCases {
                    guard var state = shelves[shelf] else { continue }
                    applyRequestStatuses(requestResults, to: &state.titles, mediaType: shelf.mediaType)
                    shelves[shelf] = state
                }
                movieRequestStatuses.removeAll()
                error = nil
                return
            }
            for shelf in Shelf.allCases {
                try Task.checkCancellation()
                do {
                    let page = try await discoveryPage(for: shelf, page: 1, client: client, session: session)
                    shelves[shelf]?.titles = appendUnique(page.results, to: [])
                    shelves[shelf]?.nextPage = page.page + 1
                    shelves[shelf]?.totalPages = page.totalPages
                    shelves[shelf]?.error = nil
                } catch {
                    shelves[shelf]?.error = SeerrClientError.requestPresentationDescription(for: error)
                }
            }
            let requestResults = try? await client.requests(session: session)
            guard !Task.isCancelled, isRequestsVisible, self.session == session else { return }
            if let requestResults {
                for shelf in Shelf.allCases {
                    guard var state = shelves[shelf] else { continue }
                    applyRequestStatuses(requestResults, to: &state.titles, mediaType: shelf.mediaType)
                    shelves[shelf] = state
                }
            }
            loadedAccount = account
            hasLoaded = true
            error = nil
        } catch {
            guard !Task.isCancelled, isRequestsVisible else { return }
            self.error = SeerrClientError.requestPresentationDescription(for: error)
        }
    }

    private func discoveryPage(for shelf: Shelf, page: Int, client: SeerrClient, session: SeerrSession) async throws -> SeerrTrendingPage {
        if shelf == .trendingMovies || shelf == .trendingShows {
            return try await client.trending(type: shelf.mediaType, page: page, session: session)
        }
        return try await client.discover(
            type: shelf.mediaType,
            sortBy: shelf.sortBy,
            upcoming: shelf.isUpcoming,
            page: page,
            session: session
        )
    }

    @MainActor
    private func loadNextPage(for shelf: Shelf) async {
        guard isRequestsVisible, hasLoaded, let session else { return }
        guard let state = shelves[shelf], state.nextPage <= state.totalPages else { return }
        if isLoadingPage {
            if !pendingPageLoads.contains(shelf), !state.isLoading {
                pendingPageLoads.append(shelf)
            }
            return
        }
        isLoadingPage = true
        var nextShelf: Shelf? = shelf
        while let currentShelf = nextShelf {
            await loadPage(for: currentShelf, session: session)
            nextShelf = pendingPageLoads.isEmpty ? nil : pendingPageLoads.removeFirst()
        }
        isLoadingPage = false
    }

    @MainActor
    private func loadPage(for shelf: Shelf, session: SeerrSession) async {
        guard isRequestsVisible, let state = shelves[shelf], state.nextPage <= state.totalPages else { return }
        shelves[shelf]?.isLoading = true
        defer { shelves[shelf]?.isLoading = false }
        do {
            let client = try SeerrClient(url: serverURL)
            let page = try await discoveryPage(for: shelf, page: state.nextPage, client: client, session: session)
            guard !Task.isCancelled, isRequestsVisible, self.session == session else { return }
            shelves[shelf]?.titles = appendUnique(page.results, to: shelves[shelf]?.titles ?? [])
            shelves[shelf]?.nextPage = page.page + 1
            shelves[shelf]?.totalPages = page.totalPages
            shelves[shelf]?.error = nil
        } catch {
            shelves[shelf]?.error = SeerrClientError.requestPresentationDescription(for: error)
        }
    }

    private func appendUnique(_ newTitles: [SeerrTitle], to existing: [SeerrTitle]) -> [SeerrTitle] {
        var ids = Set(existing.map(\.id))
        return existing + newTitles.filter { ids.insert($0.id).inserted }
    }

    private func applyRequestStatuses(_ listedRequests: [SeerrListedRequest], to titles: inout [SeerrTitle], mediaType: String) {
        let grouped = Dictionary(grouping: listedRequests.filter { $0.is4k != true }) {
            RequestMediaKey(mediaType: $0.type, mediaID: $0.media.tmdbId)
        }
        titles = mergeStatuses(existing: titles, latest: [], mediaType: mediaType, requests: grouped)
    }

    private func mergeStatuses(
        existing: [SeerrTitle],
        latest: [SeerrTitle],
        mediaType: String,
        requests: [RequestMediaKey: [SeerrListedRequest]]
    ) -> [SeerrTitle] {
        let latestByID = Dictionary(latest.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return existing.map { item in
            let latestItem = latestByID[item.id]
            let matches = requests[RequestMediaKey(mediaType: mediaType, mediaID: item.id)] ?? []
            guard !matches.isEmpty else {
                return item.replacingMediaInfo(.init(status: latestItem?.mediaInfo?.status ?? item.mediaInfo?.status, requests: nil))
            }
            let info = SeerrTitle.MediaInfo(
                status: matches[0].media.status ?? latestItem?.mediaInfo?.status ?? item.mediaInfo?.status,
                requests: matches.map { .init(status: $0.status) }
            )
            return item.replacingMediaInfo(info)
        }
    }
}

struct SeerrPoster: Poster {
    let id: String
    let displayTitle: String
    let posterURL: URL?
    let backdropURL: URL?

    init(title: SeerrTitle) {
        id = "\(title.mediaType ?? "media")-\(title.id)"
        displayTitle = title.displayTitle
        posterURL = title.posterURL
        backdropURL = nil
    }

    init(id: String, displayTitle: String, posterURL: URL?, backdropURL: URL?) {
        self.id = id
        self.displayTitle = displayTitle
        self.posterURL = posterURL
        self.backdropURL = backdropURL
    }

    var preferredPosterDisplayType: PosterDisplayType {
        .portrait
    }

    var systemImage: String {
        "film"
    }

    func portraitImageSources(environment: Empty) -> [ImageSource] {
        [ImageSource(url: posterURL)]
    }

    func landscapeImageSources(environment: Empty) -> [ImageSource] {
        [ImageSource(url: backdropURL)]
    }
}

private struct SeerrPosterButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
    }
}

private extension PosterHStackMetrics {
    static let tvOSHorizontalInset: CGFloat = 60
}

private extension RequestsView {
    var posterWidth: CGFloat {
        PosterDisplayType.Size.small.width(for: .portrait) ?? 240
    }

    var posterHeight: CGFloat {
        posterWidth * 1.5
    }

    var posterCornerRadius: CGFloat {
        posterWidth * 0.0375
    }

    private func isFocused(_ item: SeerrTitle, shelf: Shelf) -> Bool {
        focusedTarget == focusTarget(for: item, shelf: shelf)
    }
}
