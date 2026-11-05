//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftUI

// TODO: scroll if description too long
// TODO: move currentProgram tracking to a MediaPlayerObserver

struct MediaInfoSupplement: MediaPlayerSupplement {

    let displayTitle: String = L10n.info
    let item: BaseItemDto

    var id: String {
        "MediaInfo-\(item.id ?? "any")"
    }

    var videoPlayerBody: some PlatformView {
        InfoOverlay(item: item)
    }

    #if os(tvOS)
    func videoPlayerBody(
        focusedRestartAction: FocusState<VideoPlayer.PlaybackControls.Dropdown.FocusTarget?>.Binding,
        onRestart: @escaping () -> Void
    ) -> some PlatformView {
        InfoOverlay(
            item: item,
            focusedRestartAction: focusedRestartAction,
            onRestart: onRestart
        )
    }
    #endif
}

extension MediaInfoSupplement {

    private struct InfoOverlay: PlatformView {

        @Environment(\.safeAreaInsets)
        private var safeAreaInsets: EdgeInsets

        @EnvironmentObject
        private var containerState: VideoPlayerContainerState
        @EnvironmentObject
        private var manager: MediaPlayerManager

        @State
        private var item: BaseItemDto

        #if os(tvOS)
        private let focusedRestartAction: FocusState<VideoPlayer.PlaybackControls.Dropdown.FocusTarget?>.Binding?
        #endif
        private let onRestart: (() -> Void)?

        private var restartActionTitle: String {
            #if os(tvOS)
            if item.type == .episode {
                // swiftlint:disable:next hard_coded_display_string
                return "Restart Episode"
            }
            #endif

            return L10n.fromBeginning
        }

        init(item: BaseItemDto) {
            self._item = State(initialValue: item)
            #if os(tvOS)
            self.focusedRestartAction = nil
            #endif
            self.onRestart = nil
        }

        #if os(tvOS)
        init(
            item: BaseItemDto,
            focusedRestartAction: FocusState<VideoPlayer.PlaybackControls.Dropdown.FocusTarget?>.Binding,
            onRestart: @escaping () -> Void
        ) {
            self._item = State(initialValue: item)
            self.focusedRestartAction = focusedRestartAction
            self.onRestart = onRestart
        }
        #endif

        @ViewBuilder
        private var accessoryView: some View {
            VStack(alignment: .leading) {
                DotHStack {
                    if item.type == .episode {
                        if let premiereDateLabel = item.premiereDateLabel {
                            Text(premiereDateLabel)
                        }
                        if let seasonEpisodeLocator = item.seasonEpisodeLabel {
                            Text(seasonEpisodeLocator)
                        }
                    } else if let premiereYear = item.premiereDateYear {
                        Text(premiereYear)
                    }

                    if let runtime = item.runTimeLabel {
                        Text(runtime)
                    }

                    if let officialRating = item.officialRating {
                        Text(officialRating)
                    }
                }
            }
        }

        @ViewBuilder
        private var restartButton: some View {
            Button {
                manager.proxy?.setSeconds(.zero)
                manager.setPlaybackRequestStatus(status: .playing)
                if let onRestart {
                    onRestart()
                } else {
                    containerState.select(supplement: nil)
                }
            } label: {
                Label(restartActionTitle, systemImage: "play.fill")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            .buttonStyle(.supplementAction)
        }

        @ViewBuilder
        private var fromBeginningButton: some View {
            #if os(tvOS)
            if let focusedRestartAction {
                restartButton
                    .focused(focusedRestartAction, equals: .restartEpisode)
                    .frame(height: UIDevice.isTV ? 80 : 40)
            } else {
                restartButton
                    .focusable(true)
                    .frame(height: UIDevice.isTV ? 80 : 40)
            }
            #else
            restartButton
                .focusable(true)
                .frame(height: UIDevice.isTV ? 80 : 40)
            #endif
        }

        // TODO: may need to be a layout for correct overview frame
        //       with scrolling if too long
        var iOSView: some View {
            CompactOrRegularView(
                isCompact: containerState.isCompact
            ) {
                iOSCompactView
            } regularView: {
                regularContent
                    .edgePadding()
            }
            .padding(.leading, safeAreaInsets.leading)
            .padding(.trailing, safeAreaInsets.trailing)
            .task(id: item.currentProgram?.endDate) {
                await updateCurrentProgram()
            }
        }

        @ViewBuilder
        private var iOSCompactView: some View {
            VStack(alignment: .leading) {
                Text(item.displayTitle)
                    .fontWeight(.semibold)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if let currentProgram = item.currentProgram {
                    Text(currentProgram.displayTitle)
                        .fontWeight(.semibold)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .foregroundStyle(.secondary)
                }

                if let overview = item.overview ?? item.currentProgram?.overview {
                    Text(overview)
                        .font(.subheadline)
                        .fontWeight(.regular)
                }

                accessoryView
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !item.isLiveStream {
                    fromBeginningButton
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .padding(.vertical)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .edgePadding()
        }

        @ViewBuilder
        private var regularContent: some View {
            HStack(alignment: .bottom, spacing: EdgeInsets.edgePadding) {
                // TODO: determine what to do with non-portrait (channel, home video) images
                //       - use aspect ratio?
                PosterImage(
                    item: item,
                    type: item.preferredPosterDisplayType,
                    contentMode: .fit
                )
                .posterCornerRadius(item.preferredPosterDisplayType)
                .environment(\.isOverComplexContent, true)

                VStack(alignment: .leading, spacing: 5) {
                    Text(item.displayTitle)
                        .font(.callout)
                        .fontWeight(.semibold)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    if let currentProgram = item.currentProgram {
                        Text(currentProgram.displayTitle)
                            .font(.callout)
                            .fontWeight(.semibold)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .foregroundStyle(.secondary)
                    }

                    if let overview = item.overview ?? item.currentProgram?.overview {
                        Text(overview)
                            .font(.subheadline)
                            .fontWeight(.regular)
                            .lineLimit(4)
                    }

                    accessoryView
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if !item.isLiveStream {
                    AlternateLayoutView {
                        Label(restartActionTitle, systemImage: "play.fill")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .padding()
                            .edgePadding(.horizontal)
                            .frame(height: UIDevice.isTV ? 80 : 50)
                    } content: {
                        fromBeginningButton
                    }
                }
            }
        }

        var tvOSView: some View {
            regularContent
                .edgePadding(.horizontal)
                .padding(.vertical, EdgeInsets.edgePadding / 2)
                .background {
                    Rectangle()
                        .fill(Material.thin)
                }
                .clipShape(Rectangle())
                .edgePadding()
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .focusSection()
                .task(id: item.currentProgram?.endDate) {
                    await updateCurrentProgram()
                }
        }

        private func updateCurrentProgram() async {
            guard let userSession = manager.userSession,
                  let endDate = item.currentProgram?.endDate
            else { return }

            try? await Task.sleep(for: .seconds(max(endDate.timeIntervalSinceNow + 1, 1)))

            guard let newItem = try? await item.getFullItem(userSession: userSession) else { return }

            item = newItem
        }
    }
}
