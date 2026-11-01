//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import FactoryKit
import SwiftUI
import Transmission

struct VideoPlayer: View {

    #if !os(tvOS)
    @Environment(\.presentationCoordinator)
    private var presentationCoordinator
    #endif

    @InjectedObject(\.mediaPlayerManager)
    private var manager: MediaPlayerManager

    @LazyState
    private var proxy: any VideoMediaPlayerProxy

    @Router
    private var router

    #if os(tvOS)
    @Environment(\.isCurrentPresentationDismissible)
    private var isCurrentPresentationDismissible
    #endif

    // TODO: move audio/subtitle offset to container state?
    @State
    private var audioOffset: Duration = .zero
    @State
    private var shouldSuppressStopDismissal = false
    #if os(tvOS)
    #endif

    #if !os(tvOS)
    // TODO: move behavior to `PlaybackProgress`?
    @State
    private var scrubbingStartTime: CFTimeInterval? = nil
    #endif
    @State
    private var subtitleOffset: Duration = .zero

    @StateObject
    private var containerState: VideoPlayerContainerState = .init()

    init() {
        self._proxy = .init(wrappedValue: VLCMediaPlayerProxy())
    }

    var body: some View {
        VideoPlayerContainerView(
            containerState: containerState,
            manager: manager,
            onPresentationWillStopPlayback: {
                shouldSuppressStopDismissal = true
            }
        ) {
            proxy.videoPlayerBody
                .eraseToAnyView()
        } playbackControls: {
            PlaybackControls()
        } segmentOverlay: {
            #if os(tvOS)
            ScreenPlaybackSegmentOverlay(
                coordinator: manager.screenSegmentCoordinator,
                containerState: containerState
            )
            .eraseToAnyView()
            #else
            EmptyView().eraseToAnyView()
            #endif
        }
        .onAppear {
            #if DEBUG
            EpisodePlaybackDiagnostics.log(
                manager.episodePlaybackDiagnosticID,
                event: "player-initialized backend=VLC managerState=\(String(describing: manager.state))"
            )
            #endif
            shouldSuppressStopDismissal = false
            manager.proxy = proxy
            manager.screenSegmentCoordinator.prepare(for: manager.playbackItem)
            #if DEBUG
            EpisodePlaybackDiagnostics.log(
                manager.episodePlaybackDiagnosticID,
                event: "manager-start-requested backend=VLC"
            )
            #endif
            manager.start()
        }
        .onDisappear {
            #if os(tvOS)
            #if DEBUG
            EpisodePlaybackDiagnostics.logEpisodesBack(
                manager.episodePlaybackDiagnosticID,
                event: "player-view-disappear episodes=\(containerState.isPresentingPlaybackEpisodes) dismissible=\(isCurrentPresentationDismissible.wrappedValue) managerState=\(String(describing: manager.state))"
            )
            #endif
            #endif
        }
        #if os(tvOS)
        .onExitCommand {
            #if DEBUG
            EpisodePlaybackDiagnostics.logEpisodesBack(
                manager.episodePlaybackDiagnosticID,
                event: "swiftui-onExitCommand episodes=\(containerState.isPresentingPlaybackEpisodes) dropdown=\(containerState.isPresentingPlaybackDropdown) segment=\(manager.screenSegmentCoordinator.presentation != nil)"
            )
            #endif
            containerState.containerView?.handleMenuEnded()
        }
        .onChange(of: containerState.isPresentingPlaybackDropdown) { _, _ in
            updateCurrentPresentationDismissibility()
        }
        .onChange(of: containerState.isPresentingPlaybackEpisodes) { _, _ in
            #if DEBUG
            EpisodePlaybackDiagnostics.logEpisodesBack(
                manager.episodePlaybackDiagnosticID,
                event: "episodes-state-change isPresentingPlaybackEpisodes=\(containerState.isPresentingPlaybackEpisodes)"
            )
            #endif
            updateCurrentPresentationDismissibility()
        }
        .onChange(of: containerState.isPlaybackOverlayMenuDismissalGuarded) { _, _ in
            updateCurrentPresentationDismissibility()
        }
        .onReceive(manager.screenSegmentCoordinator.$presentation) { presentation in
            updateCurrentPresentationDismissibility(segmentOverlayIsPresented: presentation != nil)
        }
        #endif
        .prefersStatusBarHidden(!containerState.isPresentingOverlay)
        .onChange(of: audioOffset) {
            if let proxy = proxy as? MediaPlayerOffsetConfigurable {
                proxy.setAudioOffset(audioOffset)
            }
        }
        .onChange(of: containerState.isAspectFilled) {
            UIView.animate(withDuration: 0.2) {
                proxy.setAspectFill(containerState.isAspectFilled)
            }
        }
        #if !os(tvOS)
        .onChange(of: containerState.isScrubbing) {
            if containerState.isScrubbing {
                scrubbingStartTime = CACurrentMediaTime()
            }

            guard let scrubbingStartTime else { return }
            let scrubbingDelta = CACurrentMediaTime() - scrubbingStartTime
            let secondsDelta = abs(manager.seconds - containerState.scrubbedSeconds.value)

            guard secondsDelta >= .seconds(1), scrubbingDelta >= 0.1 else { return }

            let scrubbedSeconds = containerState.scrubbedSeconds.value
            manager.seconds = scrubbedSeconds
            proxy.setSeconds(scrubbedSeconds)
        }
        #endif
        .onChange(of: subtitleOffset) {
            if let proxy = proxy as? MediaPlayerOffsetConfigurable {
                proxy.setSubtitleOffset(subtitleOffset)
            }
        }
        .preference(
            key: PresentationControllerShouldDismissPreferenceKey.self,
            value: containerState.presentationControllerShouldDismiss
        )
        #if !os(tvOS)
        .onChange(of: presentationCoordinator.isPresented) {
            guard !presentationCoordinator.isPresented else { return }
            shouldSuppressStopDismissal = true
            manager.stop()
        }
        #endif
        .onReceive(manager.$playbackItem) { newItem in
            containerState.isAspectFilled = false
            audioOffset = .zero
            subtitleOffset = .zero

            // TODO: move to container view
            containerState.scrubbedSeconds.value = newItem?.baseItem.startSeconds ?? .zero
        }
        .onReceive(manager.$state) { newState in
            #if DEBUG
            EpisodePlaybackDiagnostics.log(
                manager.episodePlaybackDiagnosticID,
                event: "manager-state state=\(String(describing: newState))"
            )
            #endif
            guard newState == .stopped else { return }
            #if DEBUG
            EpisodePlaybackDiagnostics.log(
                manager.episodePlaybackDiagnosticID,
                event: "player-stopped observed suppressDismissal=\(shouldSuppressStopDismissal)"
            )
            #endif
            guard !shouldSuppressStopDismissal else { return }
            #if DEBUG
            EpisodePlaybackDiagnostics.log(
                manager.episodePlaybackDiagnosticID,
                event: "player-dismiss-request source=stopped-state"
            )
            EpisodePlaybackDiagnostics.logEpisodesBack(
                manager.episodePlaybackDiagnosticID,
                event: "player-dismiss-request source=stopped-state episodes=\(containerState.isPresentingPlaybackEpisodes)"
            )
            #endif
            router.dismiss()
        }

        .alert(
            L10n.error,
            isPresented: .constant(manager.error != nil)
        ) {
            Button(L10n.close, role: .cancel) {
                #if os(tvOS)
                #if DEBUG
                EpisodePlaybackDiagnostics.logEpisodesBack(
                    manager.episodePlaybackDiagnosticID,
                    event: "player-dismiss-request source=error-alert-close episodes=\(containerState.isPresentingPlaybackEpisodes)"
                )
                #endif
                #endif
                Container.shared.mediaPlayerManager.reset()
                router.dismiss()
            }
        } message: {
            Text(L10n.unableToLoadThisItem)
        }
    }

    #if os(tvOS)
    private func updateCurrentPresentationDismissibility() {
        updateCurrentPresentationDismissibility(
            segmentOverlayIsPresented: manager.screenSegmentCoordinator.presentation != nil
        )
    }

    private func updateCurrentPresentationDismissibility(segmentOverlayIsPresented: Bool) {
        let previousValue = isCurrentPresentationDismissible.wrappedValue
        let newValue = !containerState.isPresentingPlaybackDropdown &&
            !containerState.isPresentingPlaybackEpisodes &&
            !segmentOverlayIsPresented &&
            !containerState.isPlaybackOverlayMenuDismissalGuarded
        isCurrentPresentationDismissible.wrappedValue = newValue
        #if DEBUG
        EpisodePlaybackDiagnostics.logEpisodesBack(
            manager.episodePlaybackDiagnosticID,
            event: "presentation-dismissibility previous=\(previousValue) current=\(newValue) episodes=\(containerState.isPresentingPlaybackEpisodes) dropdown=\(containerState.isPresentingPlaybackDropdown) segment=\(segmentOverlayIsPresented) dismissalGuard=\(containerState.isPlaybackOverlayMenuDismissalGuarded)"
        )
        #endif
    }
    #endif
}
