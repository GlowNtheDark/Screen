//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import Defaults
import JellyfinAPI
import SwiftUI

@MainActor
struct ItemLibrary: PagingLibrary, SearchablePagingLibrary, WithRandomElementLibrary {

    struct Environment: WithDefaultValue {
        var grouping: BaseItemDto.Grouping?
        var filters: ItemFilterCollection

        static let `default`: Self = .init(
            grouping: nil,
            filters: .default
        )
    }

    let environment: Environment?
    let filterViewModel: FilterViewModel
    let parent: BaseItemDto

    var loadsEntireCollection: Bool {
        #if os(tvOS)
        true
        #else
        false
        #endif
    }

    #if os(tvOS)
    var prefersInitialGridFocus: Bool {
        guard parent.id == nil, let filters = environment?.filters else { return false }
        return filters.itemTypes == [.movie] || filters.itemTypes == [.series]
    }
    #endif

    init(
        parent: BaseItemDto,
        filters: ItemFilterCollection? = nil
    ) {
        var environment = Environment(
            grouping: parent.groupings?.defaultSelection,
            filters: filters ?? .default
        )

        if let id = parent.id, Defaults[.Customization.Library.rememberSort] {
            let storedFilters = StoredValues[.User.libraryFilters(parentID: id)]

            environment.filters.sortBy = storedFilters.sortBy
            environment.filters.sortOrder = storedFilters.sortOrder
        }

        self.environment = environment
        self.filterViewModel = .init(
            parent: parent,
            currentFilters: environment.filters
        )
        self.parent = parent
    }

    func makeMenuContent(environment: Binding<Environment>) -> AnyView {
        Group {
            if let groupings = parent.groupings, groupings.elements.isNotEmpty {
                Picker(
                    selection: environment.map(
                        getter: { $0.grouping },
                        setter: { .init(grouping: $0, filters: environment.wrappedValue.filters) }
                    )
                ) {
                    ForEach(groupings.elements) { grouping in
                        Text(grouping.displayTitle)
                            .tag(grouping as BaseItemDto.Grouping?)
                    }
                } label: {
                    Text(L10n.grouping)

                    if let grouping = environment.wrappedValue.grouping {
                        Text(grouping.displayTitle)
                    }
                }
                .pickerStyle(.menu)
            }
        }
        .eraseToAnyView()
    }

    func makeLibraryBody(
        viewModel: PagingLibraryViewModel<Self>,
        @ViewBuilder content: @escaping () -> some View
    ) -> AnyView {
        ItemLibraryBody(
            filterViewModel: filterViewModel,
            viewModel: viewModel,
            content: content
        )
        .eraseToAnyView()
    }

    func shouldRefreshCollection(
        after update: ItemUpdate,
        environment: Environment
    ) -> Bool {
        let filters = environment.filters
        let watchedTraitIsActive = filters.traits.contains(.isPlayed) ||
            filters.traits.contains(.isUnplayed)
        let favoriteTraitIsActive = filters.traits.contains(.isFavorite) ||
            filters.traits.contains(.likes)
        let playedSortIsActive = filters.sortBy.contains(.isPlayed) ||
            filters.sortBy.contains(.isUnplayed)
        let favoriteSortIsActive = filters.sortBy.contains(.isFavoriteOrLiked)
        let playCountSortIsActive = filters.sortBy.contains(.playCount)
        let playedDateSortIsActive = filters.sortBy.contains(.datePlayed) ||
            filters.sortBy.contains(.seriesDatePlayed)

        switch update.change {
        case let .userData(userData):
            return (userData.isPlayed != nil && (watchedTraitIsActive || playedSortIsActive)) ||
                ((userData.isFavorite != nil || userData.isLikes != nil) &&
                    (favoriteTraitIsActive || favoriteSortIsActive)) ||
                (userData.playCount != nil && playCountSortIsActive) ||
                (userData.lastPlayedDate != nil && playedDateSortIsActive)
        case .playbackPositionTicks:
            return false
        case .playbackStopped:
            return watchedTraitIsActive ||
                playedSortIsActive ||
                playCountSortIsActive ||
                playedDateSortIsActive
        }
    }

    func shouldRefreshSearchCollection(
        after update: ItemUpdate,
        environment: Environment
    ) -> Bool {
        // Search results can gain a new matching item even when its ID is not
        // present in the loaded page. Evaluate only the active user-data filters
        // and sorts; presentation-only updates remain query-free otherwise.
        shouldRefreshCollection(after: update, environment: environment)
    }

    func libraryStyleOptions(environment: Environment) -> LibraryStyleOptions {
        let itemTypes = environment.filters.itemTypes.isEmpty ?
            parent.supportedItemTypes(for: environment.grouping) :
            environment.filters.itemTypes

        return BaseItemKind.libraryStyleOptions(for: itemTypes)
    }

    func retrievePage(
        environment: Environment,
        pageState: LibraryPageState
    ) async throws -> [BaseItemDto] {
        var parameters = attachFilters(
            to: makeBaseItemParameters(environment: environment),
            using: environment.filters,
            isLetterFilterIncluded: !loadsEntireCollection
        )
        if !loadsEntireCollection {
            parameters = attachPage(to: parameters, pageState: pageState)
        }
        parameters.userID = pageState.userSession.user.id

        let request = Paths.getItems(parameters: parameters)
        let response = try await pageState.userSession.client.send(request)

        return normalize(response.value.items ?? [])
    }

    func retrieveRandomElement(
        environment: Environment,
        pageState: LibraryPageState
    ) async throws -> BaseItemDto? {
        var parameters = attachFilters(
            to: makeBaseItemParameters(environment: environment),
            using: environment.filters
        )
        parameters.limit = 1
        parameters.sortBy = [.random]
        parameters.userID = pageState.userSession.user.id

        let request = Paths.getItems(parameters: parameters)
        let response = try await pageState.userSession.client.send(request)

        return response.value.items?.first
    }

    func retrieveSearchPage(
        query: String,
        environment: Environment,
        pageState: LibraryPageState
    ) async throws -> [BaseItemDto] {
        var parameters = attachPage(
            to: attachFilters(
                to: makeBaseItemParameters(environment: environment),
                using: environment.filters,
                isLetterFilterIncluded: false
            ),
            pageState: pageState
        )
        parameters.searchTerm = query
        parameters.userID = pageState.userSession.user.id

        let request = Paths.getItems(parameters: parameters)
        let response = try await pageState.userSession.client.send(request)

        return normalize(response.value.items ?? [])
    }

    private func makeBaseItemParameters(environment: Environment) -> Paths.GetItemsParameters {
        var parameters = Paths.GetItemsParameters()
        parameters.enableUserData = true
        parameters.includeItemTypes = parent.supportedItemTypes(for: environment.grouping)
        parameters.isRecursive = parent.isRecursiveCollection(for: environment.grouping)
        parameters.sortBy = [.name]
        parameters.sortOrder = [.ascending]

        guard let parentID = parent.id else { return parameters }

        switch parent.libraryType {
        case .folder:
            parameters.parentID = parentID
            parameters.isRecursive = nil
        case .person:
            parameters.personIDs = [parentID]
        case .studio:
            parameters.studioIDs = [parentID]
        default:
            parameters.parentID = parentID
        }

        return parameters
    }

    private func normalize(_ items: [BaseItemDto]) -> [BaseItemDto] {
        items
            .filter { item in
                if let collectionType = item.collectionType {
                    return CollectionType.supportedCases.contains(collectionType)
                }

                return true
            }
            .map { item in
                if parent.libraryType == .folder, item.type == .collectionFolder {
                    return item.mutating(\.type, with: .folder)
                }

                return item
            }
    }

    private func attachFilters(
        to parameters: Paths.GetItemsParameters,
        using filters: ItemFilterCollection,
        isLetterFilterIncluded: Bool = true
    ) -> Paths.GetItemsParameters {
        var parameters = parameters
        parameters.audioLanguages = filters.audioLanguages.map(\.value)
        #if os(tvOS)
        let playbackTraits = filters.traits.filter {
            $0 == .isPlayed || $0 == .isUnplayed
        }

        parameters.isPlayed = if playbackTraits.contains(.isPlayed) {
            true
        } else if playbackTraits.contains(.isUnplayed) {
            false
        } else {
            nil
        }
        parameters.filters = filters.traits.filter {
            $0 != .isPlayed && $0 != .isUnplayed
        }
        #else
        parameters.filters = filters.traits
        #endif
        parameters.genres = filters.genres.map(\.value)
        parameters.officialRatings = filters.officialRatings.map(\.value)
        parameters.sortBy = filters.sortBy
        parameters.sortOrder = filters.sortOrder
        parameters.subtitleLanguages = filters.subtitleLanguages.map(\.value)
        parameters.tags = filters.tags.map(\.value)
        parameters.years = filters.years.compactMap { Int($0.value) }

        parameters.isMovie = filters.categories.contains(.movies) ? true : nil
        parameters.isSeries = filters.categories.contains(.series) ? true : nil
        parameters.isNews = filters.categories.contains(.news) ? true : nil
        parameters.isKids = filters.categories.contains(.kids) ? true : nil
        parameters.isSports = filters.categories.contains(.sports) ? true : nil

        if let query = filters.query {
            parameters.searchTerm = query
        }

        if filters.itemTypes.isNotEmpty {
            parameters.includeItemTypes = filters.itemTypes
        }

        guard isLetterFilterIncluded else { return parameters }

        if filters.letter.first?.value == "#" {
            parameters.nameLessThan = "A"
        } else {
            parameters.nameStartsWith = filters.letter
                .map(\.value)
                .filter { $0 != "#" }
                .first
        }

        return parameters
    }

    private func attachPage(
        to parameters: Paths.GetItemsParameters,
        pageState: LibraryPageState
    ) -> Paths.GetItemsParameters {
        var parameters = parameters
        parameters.limit = pageState.pageSize
        parameters.startIndex = pageState.pageOffset
        return parameters
    }
}

private struct ItemLibraryBody<Content: View>: View {

    @Default(.Customization.Library.enabledDrawerFilters)
    private var enabledDrawerFilters

    @Router
    private var router

    #if os(tvOS)
    @EnvironmentObject
    private var tabContentFocusHandoff: TabContentFocusHandoff

    @Environment(\.episodeRouteTabID)
    private var episodeRouteTabID

    @FocusState
    private var isSortControlFocused: Bool
    #endif

    @ObservedObject
    private var viewModel: PagingLibraryViewModel<ItemLibrary>

    private let content: Content
    private let filterViewModel: FilterViewModel

    #if os(tvOS)
    private var isInitialGridFocusPending: Bool {
        guard viewModel.library.prefersInitialGridFocus,
              let episodeRouteTabID,
              tabContentFocusHandoff.pendingTabID == episodeRouteTabID
        else { return false }

        if viewModel.displayedElements.isNotEmpty {
            return true
        }

        switch viewModel.state {
        case .initial, .refreshing:
            return true
        case .content, .error:
            return false
        }
    }
    #endif

    private var isLetterPickerFocusable: Bool {
        #if os(tvOS)
        guard viewModel.library.prefersInitialGridFocus else { return true }
        return !isInitialGridFocusPending && viewModel.displayedElements.isNotEmpty
        #else
        true
        #endif
    }

    init(
        filterViewModel: FilterViewModel,
        viewModel: PagingLibraryViewModel<ItemLibrary>,
        @ViewBuilder content: () -> Content
    ) {
        self.filterViewModel = filterViewModel
        self.viewModel = viewModel
        self.content = content()
    }

    private var libraryContent: some View {
        content
            .letterPickerBar(
                filterViewModel: filterViewModel,
                preferredLetter: viewModel.letterScrollTarget,
                isFocusable: isLetterPickerFocusable
            ) { letter in
                viewModel.letterScrollTarget = letter
            }
            .onFirstAppear {
                Task {
                    await filterViewModel.getQueryFilters()
                }
            }
            .onChange(of: filterViewModel.currentFilters) {
                rememberSort(from: filterViewModel.currentFilters)
            }
            .onReceive(
                filterViewModel.$currentFilters
                    .dropFirst()
                    .removeDuplicates()
                    .debounce(for: 1, scheduler: RunLoop.main)
            ) { filters in
                viewModel.environment.filters = filters
            }
    }

    #if os(tvOS)
    private var sortControl: some View {
        Button {
            router.route(to: .filter(type: .sortBy, viewModel: filterViewModel))
        } label: {
            HStack(spacing: 12) {
                Image(systemName: ItemFilterType.sortBy.systemImage)

                Text(L10n.sort)

                if let sort = filterViewModel.currentFilters.sortBy.first {
                    Text(sort.displayTitle)
                }
            }
            .font(.headline)
            .padding(.horizontal, 22)
            .frame(minHeight: 60)
            .contentShape(Rectangle())
        }
        .buttonStyle(ScreenLibraryToolbarButtonStyle())
        .focused($isSortControlFocused)
        .disabled(isInitialGridFocusPending)
        .onChange(of: isSortControlFocused) { _, isFocused in
            #if DEBUG && os(tvOS)
            LibraryFocusDiagnostics.record(
                "filter-focusstate-observed",
                tabID: episodeRouteTabID,
                detail: "focused=\(isFocused); SwiftUI focus binding observation"
            )
            #endif
            guard isFocused, viewModel.library.prefersInitialGridFocus else { return }
            tabContentFocusHandoff.complete(tabID: episodeRouteTabID)
        }
        #if DEBUG && os(tvOS)
        .onAppear {
            recordLibraryFocusReadiness("filter-view-appeared")
        }
        .onChange(of: isInitialGridFocusPending) { _, _ in
            recordLibraryFocusReadiness("filter-eligibility-changed")
        }
        .onChange(of: viewModel.displayedElements.count) { _, _ in
            recordLibraryFocusReadiness("library-content-count-changed")
        }
        #endif
    }

    #if DEBUG && os(tvOS)
    private func recordLibraryFocusReadiness(_ event: String) {
        LibraryFocusDiagnostics.record(
            event,
            tabID: episodeRouteTabID,
            detail: "pending=\(isInitialGridFocusPending) filterDisabled=\(isInitialGridFocusPending) " +
                "letterFocusable=\(isLetterPickerFocusable) count=\(viewModel.displayedElements.count) " +
                "state=\(String(describing: viewModel.state))"
        )
    }
    #endif
    #endif

    var body: some View {
        #if os(tvOS)
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                sortControl

                Spacer(minLength: 0)
            }
            .padding(.horizontal, EdgeInsets.edgePadding)
            .padding(.top, 24)
            .padding(.bottom, 18)
            .focusSection()

            libraryContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(alignment: .top) {
            if !router.isRootOfPath {
                FocusedPosterCinematicBackgroundView()
            }
        }
        #else
        libraryContent
            .navigationBarFilterDrawer(
                viewModel: filterViewModel,
                types: enabledDrawerFilters
            )
        #endif
    }

    private func rememberSort(from filters: ItemFilterCollection) {
        guard let id = viewModel.library.parent.id,
              Defaults[.Customization.Library.rememberSort]
        else { return }

        let storedFilters = StoredValues[.User.libraryFilters(parentID: id)]
            .mutating(\.sortBy, with: filters.sortBy)
            .mutating(\.sortOrder, with: filters.sortOrder)

        StoredValues[.User.libraryFilters(parentID: id)] = storedFilters
    }
}

#if os(tvOS)
private struct ScreenLibraryToolbarButtonStyle: ButtonStyle {

    @Environment(\.isFocused)
    private var isFocused

    @Environment(\.isEnabled)
    private var isEnabled

    @Environment(\.screenTheme)
    private var screenTheme

    private func colors(isPressed: Bool) -> (fill: Color, foreground: Color) {
        if !isEnabled {
            return (
                screenTheme.actions.secondaryDisabledFill.swiftUIColor,
                screenTheme.actions.secondaryDisabledForeground.swiftUIColor
            )
        } else if isPressed, isFocused {
            return (
                screenTheme.actions.primaryPressedFill.swiftUIColor,
                screenTheme.actions.primaryPressedForeground.swiftUIColor
            )
        } else if isPressed {
            return (
                screenTheme.actions.secondaryPressedFill.swiftUIColor,
                screenTheme.actions.secondaryForeground.swiftUIColor
            )
        } else if isFocused {
            return (
                screenTheme.actions.primaryFill.swiftUIColor,
                screenTheme.actions.primaryForeground.swiftUIColor
            )
        }

        return (
            screenTheme.actions.secondaryFill.swiftUIColor,
            screenTheme.actions.secondaryForeground.swiftUIColor
        )
    }

    func makeBody(configuration: Configuration) -> some View {
        let colors = colors(isPressed: configuration.isPressed)
        let isVisuallyFocused = isEnabled && isFocused

        configuration.label
            .foregroundStyle(colors.foreground)
            .background {
                Rectangle()
                    .fill(colors.fill)
                    .overlay {
                        Rectangle()
                            .stroke(
                                isVisuallyFocused ? screenTheme.focus.keylineOnPrimaryFill.swiftUIColor : .clear,
                                lineWidth: 2
                            )
                    }
            }
            .shadow(
                color: isVisuallyFocused
                    ? screenTheme.focus.glow.swiftUIColor.opacity(screenTheme.focus.glowOpacity)
                    : .clear,
                radius: isVisuallyFocused ? screenTheme.focus.glowRadius : 0
            )
            .animation(.easeOut(duration: 0.15), value: isFocused)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
#endif
