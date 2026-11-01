//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import SwiftUI

// TODO: Add scrollTargetLayout and scrollTargetBehavior to the scroll views.
// TODO: isCompact determination by available width

struct ItemView: View {

    enum Component {
        static let header = "itemView-header"
        static let parent = "itemView-parent"
        static let play = "itemView-play"
        static let playFromBeginning = "itemView-play-from-beginning"
    }

    @Default(.Customization.itemViewType)
    private var itemViewType

    @State
    private var contentSize: CGSize = .zero

    @StateObject
    private var focusCoordinator: FocusCoordinator
    @StateObject
    private var provider: ItemContentGroupProvider
    @StateObject
    private var viewModel: ContentGroupViewModel<ItemContentGroupProvider>

    #if os(tvOS)
    @Environment(\.screenTheme)
    private var screenTheme
    #endif

    init(provider: ItemContentGroupProvider) {
        self._provider = StateObject(wrappedValue: provider)
        self._viewModel = StateObject(wrappedValue: ContentGroupViewModel(provider: provider))
        self._focusCoordinator = StateObject(wrappedValue: FocusCoordinator(
            initial: provider.episodeRouteIntent == nil ? Component.play : nil,
            pendingInitialFocusTarget: provider.episodeRouteIntent?.focusTarget.coordinatorID
        ))
    }

    private var isCompact: Bool {
        contentSize.width < 600
    }

    private var isEnhanced: Bool {
        switch itemViewType {
        case .enhanced:
            guard provider.item.backdropImageTags?.isNotEmpty == true else {
                return false
            }

            if isCompact {
                return provider.item.type == .movie
                    || provider.item.type == .series
                    || provider.item.type == .program
                    || provider.item.type == .liveTvProgram
            }

            return provider.item.type != .person && provider.item.type != .season
        case .simple:
            return false
        }
    }

    private var contentGroups: [any ContentGroup] {
        let header: any ContentGroup = switch (isEnhanced, isCompact) {
        case (true, true):
            CompactEnhancedHeaderContentGroup(provider: provider)
        case (true, false):
            RegularEnhancedHeaderContentGroup(provider: provider)
        case (false, true):
            CompactSimpleHeaderContentGroup(provider: provider)
        case (false, false):
            RegularSimpleHeaderContentGroup(provider: provider)
        }

        return [header] + viewModel.groups
    }

    @ViewBuilder
    private func contentGroupScrollView(
        isEnhanced: Bool = false
    ) -> some View {
        ContentGroupScrollView(
            provider: provider,
            groups: contentGroups,
            isEnhanced: isEnhanced
        )
    }

    @ViewBuilder
    private var blurredNavigationBarScrollView: some View {
        BlurredNavigationBarScrollView(groups: contentGroups)
    }

    @ViewBuilder
    private var content: some View {
        Group {
            switch (isEnhanced, isCompact) {
            case (true, true):
                blurredNavigationBarScrollView
            case (true, false):
                InlinePlatformView {
                    blurredNavigationBarScrollView
                } tvOSView: {
                    contentGroupScrollView(isEnhanced: true)
                }
            default:
                contentGroupScrollView()
            }
        }
        .navigationTitle(provider.item.displayTitle)
    }

    @ViewBuilder
    private var themedContent: some View {
        #if os(tvOS)
        if provider.item.type == .movie {
            content.withViewContext(.isMovieDetails)
        } else {
            content
        }
        #else
        content
        #endif
    }

    var body: some View {
        ZStack {
            #if os(tvOS)
            (provider.item.type == .movie ? screenTheme.surfaces.canvas.swiftUIColor : .screenDeepNavy)
                .ignoresSafeArea()
            #endif

            switch viewModel.state {
            case .content:
                themedContent
            case .error:
                viewModel.error.map(ErrorView.init)
            case .initial, .refreshing:
                ProgressView()
            }
        }
        .trackingSize($contentSize)
        .animation(.linear(duration: 0.2), value: viewModel.state)
        .animation(.linear(duration: 0.2), value: viewModel.background.states)
        .toolbarTitleDisplayMode(.inline)
        .refreshable {
            viewModel.background.refresh()
        }
        .onFirstAppear {
            viewModel.refresh()
        }
        #if os(tvOS)
        .onReceive(Notifications[.didSendStopReport].publisher.receive(on: DispatchQueue.main)) { itemID in
            guard provider.id == itemID else { return }
            Task { try? await provider.refreshItem() }
        }
        #endif
        .environmentObject(focusCoordinator)
        .environment(\.episodeRouteOrigin, provider.episodeRouteOrigin)
        #if os(tvOS)
        .environment(\.itemStateStore, provider.userSession?.itemStateStore)
        .toolbarVisibility(.hidden, for: .navigationBar)
        #else
        .navigationBarMenuButton(
            isLoading: viewModel.background.is(.refreshing),
            isHidden: !provider.item.canEdit
        ) {
            EditItemMenu(item: provider.item)
        }
        #endif
    }
}
