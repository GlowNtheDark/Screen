//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftUI

struct CinematicItemSelector<Item: Poster, TopContent: View>: View {
    private let action: (Item) -> Void
    private let items: [Item]
    private let topContent: (Item) -> TopContent

    init(
        items: [Item],
        action: @escaping (Item) -> Void,
        @ViewBuilder topContent: @escaping (Item) -> TopContent
    ) {
        self.items = items
        self.action = action
        self.topContent = topContent
    }

    var body: some View {
        // Home Continue Watching has no changing top content, so keep poster
        // focus updates out of the shelf's parent view.
        if TopContent.self == EmptyView.self {
            CinematicItemSelectorWithoutTopContent(
                items: items,
                action: action
            )
        } else {
            FocusDrivenCinematicItemSelector(
                items: items,
                action: action,
                topContent: topContent
            )
        }
    }
}

private struct CinematicItemSelectorWithoutTopContent<Item: Poster>: View {

    @FocusState
    private var isSectionFocused

    let items: [Item]
    let action: (Item) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PosterHStack(
                elements: items,
                displayType: .portrait,
                size: .small
            ) { item, _ in
                action(item)
            }
            .environment(\.launchFocusFirstPoster, items.first.map { AnyPoster($0) })
        }
        .background(Color.screenDeepNavy)
        .focusSection()
        .focused($isSectionFocused)
    }
}

private struct FocusDrivenCinematicItemSelector<Item: Poster, TopContent: View>: View {

    @FocusState
    private var isSectionFocused

    @FocusedValue(\.focusedPoster)
    private var focusedPoster

    @State
    private var selectedPoster: AnyPoster?

    let items: [Item]
    let action: (Item) -> Void
    let topContent: (Item) -> TopContent

    private var resolvedSelectedPoster: AnyPoster? {
        selectedPoster ?? items.first.map { AnyPoster($0) }
    }

    private var selectedItem: Item? {
        resolvedSelectedPoster?._poster as? Item
    }

    private func updateSelectedPoster() {
        guard isSectionFocused, let focusedPoster else { return }
        selectedPoster = focusedPoster
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

            if let selectedItem {
                topContent(selectedItem)
                    .id(selectedItem.hashValue)
                    .transition(.opacity)
            }

            PosterHStack(
                elements: items,
                displayType: .portrait,
                size: .small
            ) { item, _ in
                action(item)
            }
            .environment(\.launchFocusFirstPoster, items.first.map { AnyPoster($0) })
        }
        .background(Color.screenDeepNavy)
        .onChange(of: focusedPoster) {
            updateSelectedPoster()
        }
        .onChange(of: isSectionFocused) {
            updateSelectedPoster()
        }
        .focusSection()
        .focused($isSectionFocused)
    }
}

extension CinematicItemSelector where TopContent == EmptyView {

    init(
        items: [Item],
        action: @escaping (Item) -> Void = { _ in }
    ) {
        self.init(
            items: items,
            action: action
        ) { _ in
            EmptyView()
        }
    }
}
