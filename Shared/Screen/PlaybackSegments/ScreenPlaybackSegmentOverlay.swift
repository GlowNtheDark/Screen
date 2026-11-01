//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import FactoryKit
import JellyfinAPI
import SwiftUI

#if os(tvOS)
struct ScreenPlaybackSegmentOverlay: View {
    private enum FocusedAction: Hashable {
        case intro
        case playNext
        case keepWatching
    }

    @ObservedObject
    var coordinator: ScreenPlaybackSegmentCoordinator

    @ObservedObject
    var containerState: VideoPlayerContainerState

    @Environment(\.screenTheme)
    private var screenTheme

    @FocusState
    private var focusedAction: FocusedAction?

    @Namespace
    private var nextEpisodeFocusScope

    @State
    private var allowsContinueWatchingFocus = false

    @Injected(\.currentUserSession)
    private var currentUserSession: UserSession?

    @StateObject
    private var continueWatchingViewModel = CinematicSelectionContentGroupViewModel(
        resumeLibrary: ResumeItemsLibrary()
    )

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if coordinator.isOverlayPresented, let presentation = coordinator.presentation {
                switch presentation.kind {
                case .intro:
                    Button("Skip Intro") {
                        coordinator.skipIntro()
                        containerState.isPresentingOverlay = true
                    }
                    .focused($focusedAction, equals: .intro)
                    .buttonStyle(.borderedProminent)
                    .tint(screenTheme.actions.primaryFill.swiftUIColor)
                    .foregroundStyle(screenTheme.actions.primaryForeground.swiftUIColor)
                    .controlSize(.large)
                    .shadow(
                        color: screenTheme.focus.glow.swiftUIColor.opacity(screenTheme.focus.glowOpacity),
                        radius: CGFloat(screenTheme.focus.glowRadius)
                    )
                    .padding(80)

                case .nextEpisode, .countdown:
                    nextEpisodeOverlay(presentation)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .focusSection()
        .onChange(of: coordinator.isOverlayPresented) {
            updateFocus(for: coordinator.presentation)
        }
        .onAppear {
            updateFocus(for: coordinator.presentation)
        }
        .animation(.easeInOut(duration: 0.2), value: coordinator.isOverlayPresented)
    }

    private func updateFocus(for presentation: ScreenPlaybackSegmentCoordinator.Presentation?) {
        containerState.isPresentingSegmentOverlay = presentation != nil

        guard let presentation else {
            focusedAction = nil
            return
        }

        Task { @MainActor in
            await Task.yield()
            guard coordinator.isOverlayPresented,
                  coordinator.presentation?.kind == presentation.kind
            else { return }

            switch presentation.kind {
            case .intro:
                focusedAction = .intro
            case .nextEpisode:
                focusedAction = .playNext
            case .countdown:
                focusedAction = .playNext
            }
        }
    }

    @ViewBuilder
    private func nextEpisodeOverlay(_ presentation: ScreenPlaybackSegmentCoordinator.Presentation) -> some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            GeometryReader { geometry in
                let scale = min(geometry.size.width / 1920, geometry.size.height / 1080)
                let contentWidth: CGFloat = 1776
                let currentWidth = (contentWidth - 28) * 0.33
                let nextWidth = contentWidth - currentWidth - 28
                let panelHeight: CGFloat = 440
                // Three independent zones in a 1080p canvas. Text and shelf
                // intrinsic sizes cannot move either of the other zones.
                ZStack(alignment: .topLeading) {
                    Color.clear
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Up Next")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(screenTheme.player.activeControl.swiftUIColor)

                        if let remaining = presentation.remainingSeconds {
                            Text("Next episode in \(remaining)")
                                .font(.system(size: 34, weight: .semibold))
                        } else {
                            Text("Next Episode")
                                .font(.system(size: 34, weight: .semibold))
                        }
                    }
                    .lineLimit(1)
                    .frame(width: contentWidth, height: 100, alignment: .topLeading)
                    .offset(x: 72, y: 48)

                    HStack(spacing: 28) {
                        currentEpisodePanel(
                            item: coordinator.currentItem,
                            width: currentWidth,
                            height: panelHeight
                        )

                        nextEpisodePanel(
                            item: presentation.item,
                            width: nextWidth,
                            height: panelHeight,
                            remaining: presentation.remainingSeconds,
                            countdownProgress: presentation.countdownProgress
                        )
                    }
                    .frame(width: contentWidth, height: panelHeight, alignment: .topLeading)
                    .offset(x: 72, y: 196)

                    if continueWatchingViewModel.hasResumeItems {
                        VStack(alignment: .leading, spacing: 20) {
                            Text("Continue Watching")
                                .font(.title2.weight(.semibold))

                            PosterHStack(
                                elements: continueWatchingViewModel.continueItems,
                                displayType: .landscape,
                                size: .medium
                            ) { item, _ in
                                coordinator.playContinueWatching(item)
                            }
                            .withViewContext(.isPlaybackOverlay)
                            .environment(\.itemStateStore, currentUserSession?.itemStateStore)
                            // Compensate for the reusable shelf's 60pt content
                            // insets so its tiles align with both card edges.
                            .frame(width: contentWidth + 120, height: 252)
                            .offset(x: -60)
                            .disabled(!allowsContinueWatchingFocus)
                            .onMoveCommand { direction in
                                if direction == .up {
                                    allowsContinueWatchingFocus = false
                                    focusedAction = .playNext
                                }
                            }
                        }
                        .frame(width: contentWidth, height: 304, alignment: .topLeading)
                        .offset(x: 72, y: 700)
                    }
                }
                .frame(width: 1920, height: 1080, alignment: .topLeading)
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            }
        }
        .focusScope(nextEpisodeFocusScope)
        .onAppear {
            allowsContinueWatchingFocus = false
            continueWatchingViewModel.refresh()
        }
        .onChange(of: presentation.remainingSeconds != nil) { wasCountingDown, isCountingDown in
            if wasCountingDown && !isCountingDown {
                allowsContinueWatchingFocus = false
                focusedAction = .playNext
            }
        }
        .onReceive(Notifications[.itemUserDataDidChange].publisher.receive(on: DispatchQueue.main)) { update in
            guard coordinator.isOverlayPresented,
                  update.userSessionID == currentUserSession?.id,
                  continueWatchingViewModel.resumeViewModel.shouldRefreshCollection(after: update)
            else { return }

            Task {
                await continueWatchingViewModel.resumeViewModel.refreshCollectionForMembershipChange()
            }
        }
        .transition(.opacity)
    }

    @ViewBuilder
    private func currentEpisodePanel(
        item: BaseItemDto?,
        width: CGFloat,
        height: CGFloat
    ) -> some View {
        ZStack(alignment: .bottomLeading) {
            if let item {
                PosterImage(item: item, type: .landscape)
                    .frame(width: width, height: height)
                    .clipped()

                LinearGradient(
                    colors: [.clear, .black.opacity(0.9)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 7) {
                    Text("Just Finished")
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    Text(item.displayTitle)
                        .font(.title2.weight(.bold))
                        .lineLimit(1)

                    if let locator = item.seasonEpisodeLabel ?? item.episodeLocator {
                        Text(locator)
                            .font(.title3)
                            .foregroundStyle(.primary.opacity(0.8))
                    }
                }
                .lineLimit(1)
                .frame(width: width - 56, alignment: .leading)
                .padding(28)
            }
        }
        .frame(width: width, height: height)
        .overlay {
            Rectangle()
                .stroke(.white.opacity(0.2), lineWidth: 1)
        }
    }

    @ViewBuilder
    private func nextEpisodePanel(
        item: BaseItemDto?,
        width: CGFloat,
        height: CGFloat,
        remaining: Int?,
        countdownProgress: Double?
    ) -> some View {
        ZStack {
            if let item {
                PosterImage(item: item, type: .landscape)
                    .frame(width: width, height: height)
                    .clipped()

                LinearGradient(
                    colors: [.black.opacity(0.95), .black.opacity(0.58), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )

                HStack(alignment: .bottom, spacing: 28) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Next Episode")
                            .font(.headline)
                            .foregroundStyle(.primary.opacity(0.88))

                        if let seriesName = item.seriesName {
                            Text(seriesName)
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(screenTheme.player.activeControl.swiftUIColor)
                                .lineLimit(1)
                        }

                        Text(item.displayTitle)
                            .font(.system(size: 36, weight: .bold))
                            .lineLimit(2)

                        if let locator = item.seasonEpisodeLabel ?? item.episodeLocator {
                            Text(locator)
                                .font(.title3.weight(.medium))
                                .lineLimit(1)
                                .foregroundStyle(.primary.opacity(0.8))
                        }

                        if let overview = item.overview, overview.isNotEmpty {
                            Text(overview)
                                .font(.system(size: 24))
                                .foregroundStyle(.primary.opacity(0.82))
                                .lineLimit(2)
                                .frame(maxWidth: 510, alignment: .leading)
                        }

                        HStack(spacing: 10) {
                            if let runtime = item.runTimeLabel {
                                Text(runtime)
                            }

                            if let premiereDate = item.premiereDateLabel {
                                Text(premiereDate)
                            }
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    }
                    .frame(width: width - 68 - 28 - 240, height: height - 68, alignment: .bottomLeading)

                    VStack(alignment: .center, spacing: 10) {
                        countdownIndicator(remaining: remaining, progress: countdownProgress)

                        Button {
                            coordinator.keepWatching()
                            containerState.isPresentingOverlay = true
                        } label: {
                            Text("Keep Watching")
                                .font(.system(size: 20, weight: .semibold))
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                                .frame(width: 216, height: 46)
                        }
                        .focused($focusedAction, equals: .keepWatching)
                        .onMoveCommand { direction in
                            switch direction {
                            case .left, .right:
                                focusedAction = .playNext
                            default:
                                break
                            }
                        }
                        .buttonStyle(ScreenPlayNextButtonStyle(isPrimary: false))

                        Button {
                            coordinator.playNextEpisode()
                        } label: {
                            Text("Play Next")
                                .font(.system(size: 24, weight: .semibold))
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                                .frame(width: 176, height: 46)
                        }
                        .focused($focusedAction, equals: .playNext)
                        .prefersDefaultFocus(true, in: nextEpisodeFocusScope)
                        .onMoveCommand { direction in
                            switch direction {
                            case .down:
                                if continueWatchingViewModel.hasResumeItems {
                                    allowsContinueWatchingFocus = true
                                } else {
                                    focusedAction = .playNext
                                }
                            case .up:
                                allowsContinueWatchingFocus = false
                            case .left, .right:
                                allowsContinueWatchingFocus = false
                                focusedAction = .keepWatching
                            default:
                                break
                            }
                        }
                        .buttonStyle(ScreenPlayNextButtonStyle(isPrimary: true))
                    }
                    .frame(width: 240, height: height - 68, alignment: .bottom)
                }
                .padding(34)
            }
        }
        .frame(width: width, height: height)
        .overlay {
            Rectangle()
                .stroke(.white.opacity(0.34), lineWidth: 1)
        }
    }

    @ViewBuilder
    private func countdownIndicator(remaining: Int?, progress: Double?) -> some View {
        if let remaining, let progress {
            VStack(alignment: .center, spacing: 4) {
                Text("Starting in")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.secondary)

                ZStack {
                    Circle()
                        .stroke(.white.opacity(0.2), lineWidth: 5)

                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(screenTheme.player.progress.swiftUIColor, style: .init(lineWidth: 5, lineCap: .square))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 1), value: progress)

                    Text("\(remaining)")
                        .font(.system(size: 38, weight: .bold, design: .monospaced))
                        .monospacedDigit()
                }
                .frame(width: 112, height: 112)
            }
        } else {
            Text("AUTOPLAY\nCANCELLED")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

private struct ScreenPlayNextButtonStyle: ButtonStyle {

    let isPrimary: Bool

    @Environment(\.isFocused)
    private var isFocused

    @Environment(\.isEnabled)
    private var isEnabled

    @Environment(\.screenTheme)
    private var screenTheme

    func makeBody(configuration: Configuration) -> some View {
        let fill: ThemeColor
        let foreground: ThemeColor

        if !isEnabled {
            fill = isPrimary ? screenTheme.actions.primaryDisabledFill : screenTheme.actions.secondaryDisabledFill
            foreground = isPrimary ? screenTheme.actions.primaryDisabledForeground : screenTheme.actions.secondaryDisabledForeground
        } else if configuration.isPressed, isPrimary {
            fill = screenTheme.actions.primaryPressedFill
            foreground = screenTheme.actions.primaryPressedForeground
        } else if configuration.isPressed {
            fill = screenTheme.actions.secondaryPressedFill
            foreground = screenTheme.actions.secondaryForeground
        } else if isPrimary {
            fill = screenTheme.actions.primaryFill
            foreground = screenTheme.actions.primaryForeground
        } else {
            fill = screenTheme.actions.secondaryFill
            foreground = screenTheme.actions.secondaryForeground
        }

        let keyline: ThemeColor? = {
            guard isEnabled, isFocused else {
                return isEnabled && !isPrimary ? screenTheme.actions.secondaryBoundary : nil
            }
            return isPrimary ? screenTheme.focus.keylineOnPrimaryFill : screenTheme.focus.keylineOnSurface
        }()

        return configuration.label
            .foregroundStyle(foreground.swiftUIColor)
            .background {
                Rectangle()
                    .fill(fill.swiftUIColor)
                    .overlay {
                        Rectangle()
                            .stroke(keyline?.swiftUIColor ?? .clear, lineWidth: 2)
                    }
            }
            .shadow(
                color: isEnabled && isFocused
                    ? screenTheme.focus.glow.swiftUIColor.opacity(screenTheme.focus.glowOpacity)
                    : .clear,
                radius: CGFloat(screenTheme.focus.glowRadius)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : (isFocused ? 1.04 : 1))
            .animation(.easeOut(duration: 0.15), value: isFocused)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
#endif
