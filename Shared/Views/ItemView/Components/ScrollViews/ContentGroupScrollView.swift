//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftUI

// TODO: tvOS black background if not enhanced?

extension ItemView {

    struct ContentGroupScrollView: View {

        @EnvironmentObject
        private var focusCoordinator: FocusCoordinator

        #if os(tvOS)
        @Environment(\.screenTheme)
        private var screenTheme
        #endif

        @ObservedObject
        var provider: ItemContentGroupProvider

        let groups: [any ContentGroup]
        let isEnhanced: Bool

        private var isHeaderFocused: Bool {
            focusCoordinator.lastFocusedIDs.contains(Component.header)
        }

        #if os(tvOS)
        private var backdropBaseColor: Color {
            provider.item.type == .movie ? screenTheme.surfaces.canvas.swiftUIColor : .screenDeepNavy
        }
        #endif

        private var backgroundImageItem: BaseItemDto {
            if provider.item.type == .person || provider.item.type == .musicArtist,
               let randomItem = provider.randomBackdropItem
            {
                randomItem
            } else {
                provider.item
            }
        }

        @ViewBuilder
        private var background: some View {
            AlternateLayoutView {
                Color.clear
            } content: {
                ImageView(backgroundImageItem.landscapeImageSources(
                    environment: .init(maxWidth: 1920)
                ))
                .failure {
                    Color.black
                }
                .aspectRatio(contentMode: .fill)
            }
            .accessibilityHidden(true)
            .overlay {
                Rectangle()
                    .fill(Material.regular)
                    .mask(gradient: .linear) {
                        if isHeaderFocused {
                            (location: 0.3, opacity: 0)
                        } else {
                            (location: 0, opacity: 1)
                        }

                        (location: 1, opacity: 1)
                    }
            }
            #if os(tvOS)
            .overlay {
                ZStack {
                    backdropBaseColor
                        .opacity(isHeaderFocused ? 0.18 : 0.46)

                    LinearGradient(
                        colors: [
                            backdropBaseColor.opacity(0.92),
                            backdropBaseColor.opacity(0.48),
                            .clear,
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )

                    LinearGradient(
                        colors: [
                            .clear,
                            backdropBaseColor.opacity(0.22),
                            backdropBaseColor.opacity(0.9),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .allowsHitTesting(false)
            }
            #endif
            .animation(.linear(duration: 0.2), value: isHeaderFocused)
        }

        var body: some View {
            ZStack {
                #if os(tvOS)
                if isEnhanced {
                    background
                        .ignoresSafeArea()
                }
                #endif

                ScrollView {
                    ContentGroupVStack(groups: groups)
                        .edgePadding(.bottom)
                }
                .trackingFrame(for: .scrollView)
                .ignoresSafeArea(edges: isEnhanced ? .all : .horizontal)
                .scrollIndicators(.hidden)
            }
        }
    }
}
