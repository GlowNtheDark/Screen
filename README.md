<div align="center">
  <img alt="Screen" src="./Resources/primary-wide.svg">
  <h1>Screen</h1>
  <img src="https://img.shields.io/badge/tvOS-26+-red"/>
  <img src="https://img.shields.io/badge/Jellyfin-12.0-9962be"/>
</div>

<p align="center"><b>Screen</b> is a native tvOS client for the <a href="https://github.com/jellyfin/jellyfin">Jellyfin</a> media server, built with SwiftUI and VLC.</p>

## Download

The existing App Store listing is still published under the legacy Swiftfin name and keeps its existing app identity: [Swiftfin on the App Store](https://apps.apple.com/us/app/swiftfin/id1604098728). Screen preserves that identity so installed users retain their data.

## Documentation

For this Screen checkout, start with the [agent guide](AGENTS.md), [architecture map](ARCHITECTURE.md), and [product documentation](docs/PRODUCT.md).

- [Library support](https://github.com/GlowNtheDark/Screen/blob/main/Documentation/libraries.md)
- [Media playback](https://github.com/GlowNtheDark/Screen/blob/main/Documentation/players.md)
- [Minimum supported OS](https://github.com/GlowNtheDark/Screen/blob/main/Documentation/version.md)
- [Common issues](https://github.com/GlowNtheDark/Screen/blob/main/Documentation/common_issues.md)
- [Contribution guide](https://github.com/GlowNtheDark/Screen/blob/main/Documentation/contributing.md)

These capability and setup documents were inherited from upstream Swiftfin and may describe iOS or upstream behavior that is not current Screen behavior.

## Translations

The localization files retain their existing Weblate project source at [translate.jellyfin.org/projects/swiftfin](https://translate.jellyfin.org/projects/swiftfin/) while the repository migration is prepared.

## Development

Open [Screen.xcodeproj](Screen.xcodeproj) and build the **Screen tvOS** scheme. See [QUALITY.md](docs/QUALITY.md) for the isolated simulator build workflow. The GitHub repository and remote are not renamed as part of this source migration.
