//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import SwiftUI

extension VideoPlayer {

    struct PlaybackControls: View {

        @Default(.VideoPlayer.jumpBackwardInterval)
        var jumpBackwardInterval
        @Default(.VideoPlayer.jumpForwardInterval)
        var jumpForwardInterval
        @Default(.accentColor)
        private var accentColor

        @EnvironmentObject
        var containerState: VideoPlayerContainerState
        @EnvironmentObject
        var manager: MediaPlayerManager

        @Toaster
        var toaster: ToastProxy

        @FocusState
        private var isPlaybackProgressFocused: Bool

        @State
        var speedBoostTimer: Timer?
        @State
        var isSpeedBoosting: Bool = false
        @State
        var pendingJumpWork: DispatchWorkItem?

        private var isOverlaySurfacePresented: Bool {
            containerState.isPresentingPlaybackDropdown ||
                containerState.isPresentingPlaybackEpisodes ||
                containerState.isPresentingSegmentOverlay
        }

        private var shouldShowPlaybackHUD: Bool {
            (containerState.isPresentingOverlay || containerState.isScrubbing) &&
                !containerState.isPresentingSupplement &&
                !isOverlaySurfacePresented
        }

        var body: some View {
            ZStack {
                Color.black
                    .opacity(0.12)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .isVisible(shouldShowPlaybackHUD)

                if shouldShowPlaybackHUD {
                    playbackHUD
                        .transition(.opacity)
                }

                if containerState.isPresentingPlaybackDropdown {
                    Dropdown()
                        .environmentObject(containerState)
                        .environmentObject(manager)
                        .transition(.opacity)
                }

                if containerState.isPresentingPlaybackEpisodes,
                   let queue = manager.queue?.episodeQueue
                {
                    EpisodesSurface(queue: queue)
                        .environmentObject(containerState)
                        .environmentObject(manager)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .focusSection()
            .animation(.easeInOut(duration: 0.25), value: containerState.isPresentingSupplement)
            .animation(.easeInOut(duration: 0.25), value: containerState.isPresentingOverlay)
            .animation(.easeInOut(duration: 0.2), value: containerState.isPresentingPlaybackDropdown)
            .animation(.easeInOut(duration: 0.24), value: containerState.isPresentingPlaybackEpisodes)
            .animation(.linear(duration: 0.1), value: containerState.isScrubbing)
            .alert(L10n.closePlayer, isPresented: $containerState.isPresentingCloseConfirmation) {
                Button(L10n.cancel, role: .cancel) {}

                Button(L10n.ok, role: .destructive) {
                    manager.stop()
                }
            } message: {
                Text(L10n.closePlayerWarning)
            }
            .onChange(of: isPlaybackProgressFocused) { _, isFocused in
                if isFocused {
                    containerState.timer.poke()
                }
            }
            .onChange(of: manager.playbackRequestStatus) {
                showHUDWhenPaused()
            }
            .onChange(of: containerState.isPresentingSegmentOverlay) { _, isPresenting in
                guard !isPresenting,
                      containerState.isPresentingOverlay,
                      !containerState.isPresentingSupplement,
                      !containerState.isPresentingPlaybackDropdown,
                      !containerState.isPresentingPlaybackEpisodes
                else { return }

                isPlaybackProgressFocused = true
            }
            .onReceive(containerState.containerView?.onPressEvent ?? .init()) { press in
                handlePressEvent(press)
            }
            .onReceive(manager.screenSegmentCoordinator.$presentation) { presentation in
                if presentation != nil {
                    containerState.isPresentingPlaybackDropdown = false
                    containerState.isPresentingPlaybackEpisodes = false
                }
            }
            .onChange(of: containerState.isProgressBarFocused) {
                if !containerState.isProgressBarFocused {
                    containerState.cancelScrub()

                    if isSpeedBoosting {
                        stopSpeedBoost()
                    }
                }
            }
        }

        private var playbackHUD: some View {
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 0)

                VStack(alignment: .leading, spacing: 22) {
                    if !containerState.isScrubbing {
                        HUDMetadata()
                    }

                    HStack(alignment: .top, spacing: 12) {
                        playPauseIndicator

                        PlaybackProgress(focused: $isPlaybackProgressFocused)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity)
                            .disabled(isOverlaySurfacePresented)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .focusSection()
                    .defaultFocus(
                        $isPlaybackProgressFocused,
                        true,
                        priority: .userInitiated
                    )
                }
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .edgePadding(.horizontal)
                .background(alignment: .bottom) {
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: Color.black.opacity(0.18), location: 0.38),
                            .init(color: Color.black.opacity(0.68), location: 1),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 470)
                    .allowsHitTesting(false)
                }
            }
            .focusSection()
            .accessibilityHidden(isOverlaySurfacePresented)
        }

        func presentEpisodesSurface() {
            guard containerState.isPresentingOverlay,
                  !containerState.isPresentingSupplement,
                  !containerState.isPresentingPlaybackDropdown,
                  !containerState.isPresentingPlaybackEpisodes,
                  !containerState.isPresentingSegmentOverlay,
                  manager.queue?.episodeQueue != nil
            else { return }

            if containerState.isScrubbing {
                containerState.cancelScrub()
            }

            containerState.isPresentingPlaybackEpisodes = true
        }

        private func showHUDWhenPaused() {
            guard manager.playbackRequestStatus == .paused,
                  !containerState.isPresentingOverlay
            else { return }

            containerState.isPresentingOverlay = true
        }

        private var playPauseIndicator: some View {
            Image(systemName: manager.playbackRequestStatus == .paused ? "play.fill" : "pause.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(accentColor)
                .frame(width: 24, height: 20)
                .focusable(false)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}
