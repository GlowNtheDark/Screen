//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import JellyfinAPI
import Logging
import SwiftUI

struct PlayButton: View {

    @Default(.accentColor)
    private var accentColor

    @ObservedObject
    var provider: ItemContentGroupProvider

    #if os(tvOS)
    @Environment(\.screenTheme)
    private var screenTheme
    #endif

    @EnvironmentObject
    private var focusCoordinator: FocusCoordinator

    #if os(tvOS)
    @FocusState
    private var focusedMovieActionID: String?
    #endif

    @Router
    private var router

    private var currentMediaPlayerItemProvider: MediaPlayerItemProvider? {
        provider.currentMediaPlayerItemProvider
    }

    private var mediaSource: String? {
        guard provider.mediaPlayerItemProvider?.item.mediaSources?.count ?? 0 > 1 else { return nil }
        return provider.mediaPlayerItemProvider?.mediaSource?.displayTitle
    }

    private var primaryTint: Color {
        #if os(tvOS)
        screenTheme.actions.primaryFill.swiftUIColor
        #else
        accentColor
        #endif
    }

    private var primaryForeground: Color {
        #if os(tvOS)
        screenTheme.actions.primaryForeground.swiftUIColor
        #else
        accentColor.overlayColor
        #endif
    }

    private var mediaSourceSelection: Binding<MediaSourceInfo?> {
        Binding(
            get: { provider.mediaPlayerItemProvider?.mediaSource },
            set: provider.selectMediaSource
        )
    }

    #if os(tvOS)
    private var isPlayFromBeginningActionEligible: Bool {
        provider.item.type == .movie && provider.mediaPlayerItemProvider != nil
    }

    private var isEpisodeArtworkFocusPending: Bool {
        provider.episodeRouteIntent != nil
            && (focusCoordinator.pendingInitialFocusTarget != nil
                || focusCoordinator.request?.hasPrefix("episode-artwork:") == true)
    }

    private var isEpisodeRouteFocusPending: Bool {
        provider.episodeRouteIntent != nil && focusCoordinator.hasPendingFocusRequest
    }
    #endif

    private func play(
        fromBeginning: Bool = false,
        originatingFocusID: String = ItemView.Component.play
    ) {
        let mediaPlayerItemProvider = if fromBeginning {
            currentMediaPlayerItemProvider?.modifyingItem {
                $0.userData?.playbackPositionTicks = 0
            }
        } else {
            currentMediaPlayerItemProvider
        }

        guard let mediaPlayerItemProvider else {
            provider.logger.error("Play selected with no playback item provider")
            return
        }

        let queue: (any MediaPlayerQueue)? = mediaPlayerItemProvider.item.type == .episode ?
            EpisodeMediaPlayerQueue(episode: mediaPlayerItemProvider.item) : nil

        let onPlayerDismiss: (() -> Void)?
        #if os(tvOS)
        if provider.item.type == .movie {
            let targetID = originatingFocusID == ItemView.Component.playFromBeginning
                && !isPlayFromBeginningActionEligible
                ? ItemView.Component.play
                : originatingFocusID
            focusCoordinator.focus(targetID)

            onPlayerDismiss = {
                guard originatingFocusID == ItemView.Component.playFromBeginning,
                      !isPlayFromBeginningActionEligible
                else { return }

                focusCoordinator.focus(ItemView.Component.play)
            }
        } else {
            onPlayerDismiss = nil
        }
        #else
        onPlayerDismiss = nil
        #endif

        router.route(
            to: .videoPlayer(
                provider: mediaPlayerItemProvider,
                queue: queue,
                onWillDismiss: onPlayerDismiss
            )
        )
    }

    @ViewBuilder
    private var versionMenu: some View {
        if let mediaSources = provider.mediaPlayerItemProvider?.item.mediaSources,
           mediaSources.count > 1
        {
            let menu = Menu {
                Picker(
                    L10n.version,
                    sources: mediaSources,
                    selection: mediaSourceSelection,
                    noneStyle: nil
                )
            } label: {
                #if os(tvOS)
                let shape: Rectangle = .rect
                #else
                let shape: RoundedRectangle = .rect(cornerRadius: 10, style: .circular)
                #endif

                Label {
                    Text(L10n.version)
                } icon: {
                    Image(systemName: "ellipsis")
                        #if os(tvOS)
                            .rotationEffect(.degrees(90))
                        #endif
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .backport
                .glassEffect(
                    .regular.selection(
                        tint: .clear,
                        foregroundColor: .primary
                    ),
                    in: shape
                )
                #if os(tvOS)
                .frame(
                    width: provider.item.type == .episode ? 60 : nil,
                    height: provider.item.type == .episode ? 75 : nil
                )
                #endif
            }
            .foregroundStyle(.primary, .secondary)
            .font(.title3)
            .fontWeight(.semibold)
            .menuStyle(.button)
            #if os(tvOS)
            .disabled(isEpisodeRouteFocusPending)
            #endif
            .labelStyle(.iconOnly)
            #if !os(tvOS)
            .aspectRatio(1, contentMode: .fit)
            #else
            .frame(width: 60)
            #endif

            #if os(tvOS)
            if provider.item.type == .episode {
                menu
                    .buttonStyle(BasicHoverButtonStyle(scalesOnInteraction: false))
                    .buttonBorderShape(.roundedRectangle(radius: 0))
            } else {
                menu.buttonStyle(BasicHoverButtonStyle())
            }
            #else
            menu.buttonStyle(BasicHoverButtonStyle())
            #endif
        }
    }

    @ViewBuilder
    private var playButton: some View {
        let button = Button {
            play()
        } label: {
            Group {
                #if os(tvOS)
                if provider.item.type == .movie {
                    Label(L10n.play, systemImage: "play.fill")
                        .labelStyle(.iconOnly)
                        .font(.title2)
                        .accessibilityLabel(L10n.play)
                } else {
                    playButtonTextLabel
                }
                #else
                playButtonTextLabel
                #endif
            }
            .fontWeight(.semibold)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .backport
            #if os(tvOS)
            .glassEffect(
                .regular.selection(
                    tint: primaryTint,
                    foregroundColor: primaryForeground
                ),
                in: .rect
            )
            #else
            .glassEffect(
                .regular.selection(
                    tint: primaryTint,
                    foregroundColor: primaryForeground
                ),
                in: .capsule
            )
            #endif
        }
        #if os(tvOS)
        .buttonBorderShape(.roundedRectangle(radius: 0))
        #else
            .buttonBorderShape(.capsule)
        #endif
        .contextMenu {
            if currentMediaPlayerItemProvider?.item.userData?.playbackPositionTicks != 0 {
                Button(L10n.playFromBeginning, systemImage: "gobackward") {
                    play(fromBeginning: true)
                }
            }
        }
        .disabled(provider.mediaPlayerItemProvider == nil)
        #if os(tvOS)
        .disabled(isEpisodeArtworkFocusPending)
        #endif

        #if os(tvOS)
        if provider.item.type == .episode {
            // Separate the focus outline from the themed Play fill without resizing the control.
            button.buttonStyle(BasicHoverButtonStyle(scalesOnInteraction: false, outlineInset: -3))
        } else {
            button.buttonStyle(ScreenPrimaryPlayButtonStyle())
        }
        #else
        button.buttonStyle(BasicHoverButtonStyle())
        #endif
    }

    @ViewBuilder
    private var coordinatedPlayButton: some View {
        #if os(tvOS)
        if provider.item.type == .movie {
            playButton.coordinatedFocus(
                ItemView.Component.play,
                selection: $focusedMovieActionID
            )
        } else {
            playButton.coordinatedFocus(
                ItemView.Component.play,
                consumesRequestOnAcquisition: true
            )
        }
        #else
        playButton.coordinatedFocus(
            ItemView.Component.play,
            consumesRequestOnAcquisition: true
        )
        #endif
    }

    private var playButtonTextLabel: some View {
        HStack {
            Image(systemName: "play.fill")

            VStack(spacing: 2) {
                Text(currentMediaPlayerItemProvider?.item.playButtonLabel ?? L10n.play)

                if let mediaSource {
                    Marquee(mediaSource, speed: 40, delay: 3, fade: 5)
                        .font(.caption)
                        .fontWeight(.medium)
                }
            }
            .font(UIDevice.isTV ? .title3 : .callout)
        }
    }

    #if os(tvOS)
    private var playFromBeginningButton: some View {
        Button {
            play(
                fromBeginning: true,
                originatingFocusID: ItemView.Component.playFromBeginning
            )
        } label: {
            Label(L10n.playFromBeginning, systemImage: "gobackward")
                .labelStyle(.iconOnly)
                .font(.title2)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    Rectangle()
                        .fill(screenTheme.actions.secondaryFill.swiftUIColor)
                }
                .overlay {
                    Rectangle()
                        .stroke(screenTheme.actions.secondaryBoundary.swiftUIColor, lineWidth: 1)
                }
                .foregroundStyle(screenTheme.actions.secondaryForeground.swiftUIColor)
                .contentShape(Rectangle())
                .accessibilityLabel(L10n.playFromBeginning)
        }
        .buttonStyle(BasicHoverButtonStyle())
        .coordinatedFocus(
            ItemView.Component.playFromBeginning,
            selection: $focusedMovieActionID
        )
        .disabled(provider.mediaPlayerItemProvider == nil)
    }
    #endif

    private var actionRowContent: some View {
        HStack(alignment: .center, spacing: UIDevice.isTV ? 30 : 10) {
            coordinatedPlayButton

            #if os(tvOS)
            if provider.item.type == .movie {
                playFromBeginningButton
            } else {
                versionMenu
            }
            #else
            versionMenu
            #endif
        }
        .frame(height: UIDevice.isTV ? 75 : 44)
    }

    @ViewBuilder
    private var actionRow: some View {
        #if os(tvOS)
        if provider.item.type == .movie {
            actionRowContent
                .defaultFocus(
                    $focusedMovieActionID,
                    focusCoordinator.request ?? ItemView.Component.play
                )
        } else {
            actionRowContent
        }
        #else
        actionRowContent
        #endif
    }

    var body: some View {
        actionRow
    }
}

#if os(tvOS)
private struct ScreenPrimaryPlayButtonStyle: ButtonStyle {

    @Environment(\.screenTheme)
    private var screenTheme

    @Environment(\.isFocused)
    private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .isSelected(isFocused)
            .scaleEffect(configuration.isPressed ? 0.97 : isFocused ? 1.045 : 1)
            .brightness(isFocused ? 0.04 : 0)
            .shadow(
                color: isFocused ? screenTheme.focus.glow.swiftUIColor.opacity(0.42) : .clear,
                radius: isFocused ? 24 : 0
            )
            .animation(.easeOut(duration: 0.16), value: isFocused)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
#endif
