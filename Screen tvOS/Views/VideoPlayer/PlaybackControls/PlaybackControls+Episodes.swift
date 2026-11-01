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

extension VideoPlayer.PlaybackControls {

    enum EpisodesFocusTarget: Hashable {
        case season(String)
        case episode(String)
    }

    struct EpisodesSurface: View {

        @EnvironmentObject
        private var containerState: VideoPlayerContainerState
        @EnvironmentObject
        private var manager: MediaPlayerManager

        @Environment(\.screenTheme)
        private var screenTheme

        @ObservedObject
        private var seasonsViewModel: PagingLibraryViewModel<SeasonViewModelLibrary>

        @FocusState
        private var focusedTarget: EpisodesFocusTarget?

        @State
        private var selectedSeasonID: String?

        @State
        private var pendingEpisodeFocusSeasonID: String?

        @State
        private var requestedEpisodeFocusID: String?

        @State
        private var pendingSeasonFocusID: String?

        @State
        private var isRestoringCurrentEpisodeFocus = true

        init(queue: EpisodeMediaPlayerQueue) {
            self._seasonsViewModel = ObservedObject(wrappedValue: queue.seasonsViewModel)
        }

        private var selectedSeason: PagingLibraryViewModel<EpisodeLibrary>? {
            guard let selectedSeasonID else { return nil }
            return seasonsViewModel.elements[id: selectedSeasonID]
        }

        private var seriesTitle: String {
            manager.item.seriesName ?? manager.item.parentTitle ?? manager.item.displayTitle
        }

        var body: some View {
            GeometryReader { geometry in
                ZStack(alignment: .bottom) {
                    Color.black.opacity(0.22)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)

                    VStack(alignment: .leading, spacing: 24) {
                        HStack(alignment: .firstTextBaseline, spacing: 24) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(L10n.episodes)
                                    .font(.title2.weight(.semibold))

                                Text(seriesTitle)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer(minLength: 0)

                            if let seasonEpisodeLabel = manager.item.seasonEpisodeLabel {
                                Text(seasonEpisodeLabel)
                                    .font(.callout.weight(.medium))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        seasonSelector

                        episodesContent
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                    .padding(.horizontal, 72)
                    .padding(.top, 36)
                    .padding(.bottom, 44)
                    .frame(
                        width: geometry.size.width,
                        height: min(geometry.size.height * 0.72, 760),
                        alignment: .topLeading
                    )
                    .background {
                        Rectangle()
                            .fill(.ultraThinMaterial)
                            .overlay {
                                Rectangle()
                                    .fill(screenTheme.surfaces.canvas.swiftUIColor.opacity(0.88))
                            }
                    }
                    .overlay {
                        Rectangle()
                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.42), radius: 30, x: 0, y: 16)
                }
            }
            .focusSection()
            .defaultFocus(
                $focusedTarget,
                .episode(manager.item.id ?? manager.item.displayTitle),
                priority: .userInitiated
            )
            .onAppear {
                #if DEBUG
                EpisodePlaybackDiagnostics.logEpisodesBack(
                    manager.episodePlaybackDiagnosticID,
                    event: "episodes-surface-appear isPresentingPlaybackEpisodes=\(containerState.isPresentingPlaybackEpisodes)"
                )
                #endif
                isRestoringCurrentEpisodeFocus = true
                restoreCurrentSeason()
            }
            .onDisappear {
                #if DEBUG
                EpisodePlaybackDiagnostics.logEpisodesBack(
                    manager.episodePlaybackDiagnosticID,
                    event: "episodes-surface-disappear isPresentingPlaybackEpisodes=\(containerState.isPresentingPlaybackEpisodes)"
                )
                #endif
            }
            .onReceive(seasonsViewModel.$elements) { _ in
                if selectedSeasonID == nil {
                    restoreCurrentSeason()
                }
            }
            .onChange(of: manager.item.seasonID) {
                restoreCurrentSeason()
            }
            .onChange(of: manager.item.parentIndexNumber) {
                restoreCurrentSeason()
            }
            .onChange(of: containerState.playbackEpisodesMoveRequest) { _, request in
                guard let request else { return }
                handleMoveCommand(request.direction)
            }
        }

        @ViewBuilder
        private var seasonSelector: some View {
            if seasonsViewModel.elements.count > 1 {
                ScrollViewReader { scrollProxy in
                    ScrollView(.horizontal) {
                        HStack(spacing: 12) {
                            ForEach(seasonsViewModel.elements) { season in
                                seasonOption(season)
                                    .id(season.id)
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                    .scrollClipDisabled()
                    .focusSection()
                    .onChange(of: focusedTarget) { _, target in
                        guard case let .season(seasonID) = target else { return }
                        if pendingSeasonFocusID == seasonID {
                            pendingSeasonFocusID = nil
                        }
                        if selectedSeasonID != seasonID,
                           let season = seasonsViewModel.elements[id: seasonID]
                        {
                            select(season: season)
                        }
                        withAnimation(.easeInOut(duration: 0.18)) {
                            scrollProxy.scrollTo(seasonID, anchor: .center)
                        }
                    }
                }
            }
        }

        @ViewBuilder
        private func seasonOption(_ season: PagingLibraryViewModel<EpisodeLibrary>) -> some View {
            let isSelected = selectedSeasonID == season.id
            let shouldRenderButton = !isRestoringCurrentEpisodeFocus &&
                (pendingSeasonFocusID == nil || pendingSeasonFocusID == season.id)

            if shouldRenderButton {
                Button {
                    select(season: season)
                } label: {
                    Text(season.library.parent.displayTitle)
                        .font(.callout.weight(.semibold))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                }
                .buttonStyle(EpisodesButtonStyle(isSelected: isSelected))
                .focused($focusedTarget, equals: .season(season.id))
            } else {
                Text(season.library.parent.displayTitle)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                    .background {
                        Rectangle()
                            .fill(.ultraThinMaterial)
                            .overlay {
                                Rectangle()
                                    .fill(screenTheme.surfaces.canvas.swiftUIColor.opacity(isSelected ? 0.42 : 0.7))
                            }
                    }
                    .overlay {
                        Rectangle()
                            .stroke(
                                isSelected
                                    ? screenTheme.selection.indicator.swiftUIColor
                                    : screenTheme.actions.secondaryBoundary.swiftUIColor,
                                lineWidth: isSelected ? 2 : 1
                            )
                    }
                    .accessibilityHidden(true)
            }
        }

        @ViewBuilder
        private var episodesContent: some View {
            if seasonsViewModel.elements.isEmpty {
                ProgressView()
                    .tint(screenTheme.actions.primaryFill.swiftUIColor)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let selectedSeason {
                EpisodesShelf(
                    season: selectedSeason,
                    currentEpisodeID: manager.item.id,
                    focusedTarget: $focusedTarget,
                    pendingEpisodeFocusSeasonID: $pendingEpisodeFocusSeasonID,
                    requestedEpisodeFocusID: $requestedEpisodeFocusID,
                    isRestoringCurrentEpisodeFocus: $isRestoringCurrentEpisodeFocus,
                    onSelect: select(episode:)
                )
            }
        }

        private func handleMoveCommand(_ direction: PlaybackEpisodesMoveRequest.Direction) {
            switch direction {
            case .up:
                guard seasonsViewModel.elements.count > 1,
                      case .episode = focusedTarget,
                      let selectedSeason
                else { return }

                pendingSeasonFocusID = selectedSeason.id
                focusedTarget = .season(selectedSeason.id)

            case .down:
                guard case .season = focusedTarget,
                      let season = selectedSeason
                else { return }

                focusEpisode(in: season)
            }
        }

        private func focusEpisode(in season: PagingLibraryViewModel<EpisodeLibrary>) {
            // The shelf owns the episode focus candidates. Leave this request pending
            // until its content publisher can target the registered card; setting the
            // parent FocusState here can be ignored while the shelf is being inserted.
            isRestoringCurrentEpisodeFocus = true
            pendingEpisodeFocusSeasonID = season.id
            requestedEpisodeFocusID = season.elements.first {
                $0.id == manager.item.id
            }?.id ?? season.elements.first?.id
        }

        private func restoreCurrentSeason() {
            guard !seasonsViewModel.elements.isEmpty else { return }

            isRestoringCurrentEpisodeFocus = true
            let season = seasonsViewModel.elements.first {
                $0.library.parent.id == manager.item.seasonID
            } ?? seasonsViewModel.elements.first {
                $0.library.parent.indexNumber == manager.item.parentIndexNumber
            } ?? seasonsViewModel.elements.first

            if let season {
                select(season: season)
                focusEpisode(in: season)
            }
        }

        private func select(season: PagingLibraryViewModel<EpisodeLibrary>) {
            selectedSeasonID = season.id

            switch season.state {
            case .initial:
                season.refresh()
            case .error where season.elements.isEmpty:
                season.refresh()
            default:
                break
            }
        }

        private func select(episode: BaseItemDto) {
            EpisodeMediaPlayerQueue.select(episode: episode, using: manager)
            containerState.isPresentingPlaybackEpisodes = false
        }
    }

    private struct EpisodesShelf: View {

        private enum CardMetrics {
            static let width: CGFloat = 340
            static let height: CGFloat = 316
            static let artworkWidth: CGFloat = 330
            static let artworkHeight: CGFloat = 186
            static let metadataSpacing: CGFloat = 10
            static let seasonLabelHeight: CGFloat = 18
            static let titleHeight: CGFloat = 64
            static let runtimeHeight: CGFloat = 18
        }

        @EnvironmentObject
        private var manager: MediaPlayerManager

        @Environment(\.screenTheme)
        private var screenTheme

        @ObservedObject
        var season: PagingLibraryViewModel<EpisodeLibrary>

        let currentEpisodeID: String?
        let focusedTarget: FocusState<EpisodesFocusTarget?>.Binding
        @Binding
        var pendingEpisodeFocusSeasonID: String?
        @Binding
        var requestedEpisodeFocusID: String?
        @Binding
        var isRestoringCurrentEpisodeFocus: Bool
        let onSelect: (BaseItemDto) -> Void

        @State
        private var registeredEpisodeIDs: Set<String> = []

        @State
        private var pendingFocusTargetID: String?

        @State
        private var hasIssuedFocusRequest = false

        var body: some View {
            switch season.state {
            case .initial, .refreshing:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

            case .error:
                Button(L10n.retry) {
                    season.refresh()
                }
                .buttonStyle(EpisodesButtonStyle(isSelected: false))

            case .content:
                if season.elements.isEmpty {
                    Text(L10n.noItems)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .onAppear {
                            isRestoringCurrentEpisodeFocus = false
                            pendingEpisodeFocusSeasonID = nil
                        }
                } else {
                    ScrollViewReader { scrollProxy in
                        ScrollView(.horizontal) {
                            LazyHStack(alignment: .top, spacing: 22) {
                                ForEach(season.elements, id: \.id) { episode in
                                    episodeButton(episode)
                                }
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 8)
                        }
                        .scrollIndicators(.hidden)
                        .focusSection()
                        .onReceive(season.$elements) { elements in
                            let initialEpisode = elements.first(where: { $0.id == currentEpisodeID }) ?? elements.first
                            guard let initialEpisode else { return }

                            let itemID = initialEpisode.id ?? initialEpisode.displayTitle

                            if pendingEpisodeFocusSeasonID == season.id || isRestoringCurrentEpisodeFocus {
                                requestedEpisodeFocusID = itemID
                                requestFocus(initialEpisode, using: scrollProxy)
                            } else {
                                scrollProxy.scrollTo(itemID, anchor: .center)
                            }
                        }
                        .onChange(of: pendingEpisodeFocusSeasonID) { _, seasonID in
                            guard seasonID == season.id,
                                  let episode = season.elements.first(where: { $0.id == currentEpisodeID }) ?? season.elements.first
                            else { return }

                            requestFocus(episode, using: scrollProxy)
                        }
                        .onChange(of: focusedTarget.wrappedValue) { _, target in
                            guard case let .episode(itemID) = target else { return }

                            if isRestoringCurrentEpisodeFocus {
                                guard finishFocusRequest(on: itemID) else { return }
                            }

                            withAnimation(.easeInOut(duration: 0.18)) {
                                scrollProxy.scrollTo(itemID, anchor: .center)
                            }
                        }
                    }
                }
            }
        }

        private func requestFocus(_ episode: BaseItemDto, using scrollProxy: ScrollViewProxy) {
            let itemID = episode.id ?? episode.displayTitle
            if pendingFocusTargetID != itemID {
                pendingFocusTargetID = itemID
                hasIssuedFocusRequest = false
            }
            scrollProxy.scrollTo(itemID, anchor: .center)

            guard registeredEpisodeIDs.contains(itemID) else { return }
            if focusedTarget.wrappedValue == .episode(itemID) {
                _ = finishFocusRequest(on: itemID)
            } else {
                acquireFocus(on: itemID)
            }
        }

        private func registerEpisode(_ itemID: String) {
            registeredEpisodeIDs.insert(itemID)
            guard pendingFocusTargetID == itemID else { return }

            if focusedTarget.wrappedValue == .episode(itemID) {
                _ = finishFocusRequest(on: itemID)
            } else {
                acquireFocus(on: itemID)
            }
        }

        @discardableResult
        private func finishFocusRequest(on itemID: String) -> Bool {
            guard pendingFocusTargetID == itemID else { return false }
            pendingFocusTargetID = nil
            hasIssuedFocusRequest = false
            isRestoringCurrentEpisodeFocus = false
            pendingEpisodeFocusSeasonID = nil
            requestedEpisodeFocusID = nil
            return true
        }

        private func acquireFocus(on itemID: String) {
            guard pendingFocusTargetID == itemID, !hasIssuedFocusRequest else { return }
            hasIssuedFocusRequest = true
            focusedTarget.wrappedValue = .episode(itemID)
        }

        @ViewBuilder
        private func episodeButton(_ episode: BaseItemDto) -> some View {
            let itemID = episode.id ?? episode.displayTitle
            let isCurrent = episode.id == currentEpisodeID

            Group {
                if isRestoringCurrentEpisodeFocus, requestedEpisodeFocusID != itemID {
                    episodeCardContent(episode, isCurrent: isCurrent)
                        .accessibilityHidden(true)
                } else {
                    Button {
                        onSelect(episode)
                    } label: {
                        episodeCardContent(episode, isCurrent: isCurrent)
                    }
                    .buttonStyle(EpisodesButtonStyle(isSelected: isCurrent))
                    .focused(focusedTarget, equals: .episode(itemID))
                    // swiftlint:disable:next hard_coded_display_string
                    .accessibilityLabel(
                        isCurrent ? "\(episode.displayTitle), Now Playing" : episode.displayTitle
                    )
                    .onAppear {
                        registerEpisode(itemID)
                    }
                    .onDisappear {
                        registeredEpisodeIDs.remove(itemID)
                    }
                }
            }
            .id(itemID)
        }

        private func episodeCardContent(_ episode: BaseItemDto, isCurrent: Bool) -> some View {
            VStack(alignment: .leading, spacing: CardMetrics.metadataSpacing) {
                ZStack(alignment: .topLeading) {
                    ImageView(
                        episode.imageSource(
                            .primary,
                            environment: ImageSourceOptions(maxWidth: 480)
                        )
                    )
                    .failure {
                        SystemImageContentView(systemName: episode.systemImage)
                    }
                    .aspectRatio(16 / 9, contentMode: .fill)
                    .frame(width: CardMetrics.artworkWidth, height: CardMetrics.artworkHeight)
                    .background(screenTheme.surfaces.canvas.swiftUIColor)
                    .clipped()

                    if isCurrent {
                        Label {
                            // swiftlint:disable:next hard_coded_display_string
                            Text("Now Playing")
                        } icon: {
                            Image(systemName: "play.fill")
                        }
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(screenTheme.actions.primaryForeground.swiftUIColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Rectangle().fill(screenTheme.selection.indicator.swiftUIColor))
                    }
                }
                .frame(width: CardMetrics.artworkWidth, height: CardMetrics.artworkHeight)
                .overlay {
                    Rectangle()
                        .stroke(
                            isCurrent
                                ? screenTheme.selection.indicator.swiftUIColor
                                : screenTheme.actions.secondaryBoundary.swiftUIColor,
                            lineWidth: isCurrent ? 3 : 1
                        )
                }

                Text(episode.seasonEpisodeLabel ?? " ")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: CardMetrics.seasonLabelHeight, alignment: .topLeading)
                    .opacity(episode.seasonEpisodeLabel == nil ? 0 : 1)
                    .accessibilityHidden(episode.seasonEpisodeLabel == nil)

                Text(episode.displayTitle)
                    .font(.headline)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .frame(height: CardMetrics.titleHeight, alignment: .topLeading)
                    .clipped()

                Text(episode.runTimeLabel ?? " ")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: CardMetrics.runtimeHeight, alignment: .topLeading)
                    .opacity(episode.runTimeLabel == nil ? 0 : 1)
                    .accessibilityHidden(episode.runTimeLabel == nil)
            }
            .frame(width: CardMetrics.width, height: CardMetrics.height, alignment: .topLeading)
            .contentShape(Rectangle())
        }
    }

    private struct EpisodesButtonStyle: ButtonStyle {

        @Environment(\.isFocused)
        private var isFocused
        @Environment(\.screenTheme)
        private var screenTheme

        let isSelected: Bool

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .foregroundStyle(.white)
                .background {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .overlay {
                            Rectangle()
                                .fill(screenTheme.surfaces.canvas.swiftUIColor.opacity(isSelected ? 0.42 : 0.7))
                        }
                }
                .overlay {
                    Rectangle()
                        .stroke(
                            isFocused
                                ? screenTheme.focus.keylineOnSurface.swiftUIColor
                                : isSelected
                                ? screenTheme.selection.indicator.swiftUIColor
                                : screenTheme.actions.secondaryBoundary.swiftUIColor,
                            lineWidth: isFocused ? 3 : isSelected ? 2 : 1
                        )
                }
                .shadow(
                    color: isFocused
                        ? screenTheme.focus.glow.swiftUIColor.opacity(screenTheme.focus.glowOpacity * 0.85)
                        : .clear,
                    radius: isFocused ? min(screenTheme.focus.glowRadius, 14) : 0
                )
                .scaleEffect(configuration.isPressed ? 0.98 : isFocused ? 1.035 : 1)
                .animation(.easeOut(duration: 0.14), value: isFocused)
                .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
        }
    }
}
