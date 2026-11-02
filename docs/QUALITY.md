# Quality and completion

Done means the requested result is implemented within scope, the relevant checks
pass, and material unverified behavior is reported. Preserve unrelated work and iOS
behavior. See [AGENTS.md](../AGENTS.md) for scope and the two-pass limit.

## Choose checks by impact

Normal verification is final diff review plus `git diff --check`. Jamie performs
Xcode builds and runtime validation; do not run Xcode or `xcodebuild` by default.
Build only when explicitly requested, needed to diagnose a compile-sensitive issue,
or fixing an existing compiler/build failure.

Select checks for the behavior actually affected, not every check in a matching row.
For example, an indicator-only edit does not require auditing shelf ordering.
Honor explicit task limits on validation; report any resulting verification gap.

| Change | Relevant verification |
| --- | --- |
| Documentation only | Review links/source paths, instruction consistency, intent vs implementation, and diff scope. No app build needed. |
| Small TV UI edit | Focused static/diff check; inspect changed layout/focus on simulator or device when runtime validation is in scope. |
| Navigation/focus | Exercise the [navigation contract](product-specs/navigation.md), including nested details and any affected direct-play path; verify initial focus, directional moves, Back, and restored tile after refresh. |
| Playback | Start/resume, pause/seek, Back/dismissal, stop reporting, and affected queue/Play Next behavior; test each affected backend. |
| Watched/Continue Watching | Correlate the same item ID in server responses and local mappings; check partial episodes, next episodes, movies, deduplication, and recency ordering. |
| Shared behavior | Add relevant iOS validation when shared paths are affected. Use existing focused tests where useful; add tests for behavior, not implementation duplication. |

A successful build is separate from simulator/physical Apple TV verification.
Physical Apple TV behavior matters especially for focus, scrolling, playback, and
performance work. State which checks ran and distinguish device evidence from
source-only findings. Hardware-dependent player behavior needs device evidence.
At the 2026-09-14 inspection, the `Screen tvOS` shared scheme had no Testables;
check the current scheme before choosing tests. `xcodebuild test` is
not evidence of app coverage without an actual test target.

## Build entry points

When a build is warranted under the rule above, run from the repository root.
Inspect [CI](../.github/workflows/ci.yml),
[Brewfile](../Brewfile), [Cartfile](../Cartfile), and the
[contribution setup](../Documentation/contributing.md) only when setup is relevant.
At bootstrap, CI specifies Xcode 26.6 and the `Screen tvOS` scheme. Verify local
Xcode selection, available destinations, and existing Carthage/package artifacts
before treating an environment failure as a source defect.

For Codex interaction on the Apple TV 4K (3rd generation, 1080p) simulator, use
[`Scripts/build-install-tvos-simulator.sh`](../Scripts/build-install-tvos-simulator.sh).
It pins the `Screen tvOS` Debug product, local Team ID, bundle ID, app-group entitlement,
and a dedicated DerivedData directory; it verifies Xcode's Simulator entitlement
manifests and existing app-group registration before installing the built product
in place. The simulator executable
uses an ad hoc code signature, while Xcode's `Screen.app-Simulated.xcent` carries
`application-identifier` (`36VR7266B9.com.screen.tvos`) and
`com.apple.security.application-groups` (`group.com.snowfin.tvos`). The application
identifier is also the default Keychain access group for this target. The Top Shelf
extension uses `com.screen.tvos.topshelf` and keeps the same App Group entitlement.
Physical-device signing requires App IDs and provisioning profiles for both new
bundle identifiers, with the existing App Group enabled for each. A Simulator build
does not verify Apple Developer portal registration or physical-device profiles.

The new `com.screen.tvos` identity installs separately from the legacy
`com.snowfin.tvos` app and receives a separate application container. The CoreStore
database filename remains `Swiftfin.sqlite`, but the new app does not automatically
read the old app's container. Jellyfin tokens and Seerr sessions use KeychainSwift
without an explicit shared access group, so they may not be available to the new
identity. Any standard UserDefaults entries use the app's bundle domain; custom
named suites retain their existing names but were not runtime-verified across this
identity change.
Shared Top Shelf data remains in `group.com.snowfin.tvos`.

Do not uninstall the legacy app or copy its database, Keychain credentials, or
preferences as part of this identity change. A later migration needs a designed,
signed export/import path (or an explicitly provisioned shared access group),
backups, and a tested rollback plan. This build does not migrate credentials. Keep
the legacy app installed; use the script for updates after the new app-group
container is registered. Do not use `xcodebuild install`, which can replace the app
with a different launcher product and create a new data container.

The generic simulator command below is compile-only. `CODE_SIGNING_ALLOWED=NO`
does not produce the Simulator entitlement manifests and its product must not be
installed or launched for Keychain validation.

The Xcode `Run SwiftFormat` phase is lint-only and never rewrites source files.
Formatting differences are reported as a build warning; the pull-request workflow
keeps the strict, non-mutating SwiftFormat check.

```sh
xcode-select -p
xcodebuild -project Screen.xcodeproj -scheme 'Screen tvOS' -showdestinations
xcodebuild -project Screen.xcodeproj -scheme 'Screen tvOS' \
  -configuration Debug -destination 'generic/platform=tvOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

The generic simulator command checks compilation; select an installed simulator
for interaction testing. For requested device compilation, use
`-destination 'generic/platform=tvOS'`; device installation requires appropriate signing.
Build commands are entry points, not a claim that this bootstrap ran them.
Do not default to clean builds, dependency upgrades, or cache deletion.
CoreStore is pinned to upstream revision `332883717578c009e1e8917a647a2f6c975e8f0a`
(merged PR #519) for Xcode 27 / Swift 6.4 compatibility. It removes the unused
untyped-throws `cs_sync` overload that makes CoreStore 9.3.0 ambiguous to compile.
Keep this pin until a compatible release is verified; the later development branch
also changes library linkage, which this pin intentionally avoids.
Use targeted SwiftFormat/SwiftLint checks for changed Swift files according to the
checked-in configuration; do not format the entire dirty tree.

The upstream guide calls for both platform builds before upstream merge; current
local CI runs tvOS only. This distinction does not waive validation for affected iOS code.

## Final review

Run `git diff --check` and inspect the task's diff (including new files).
After builds inspect `Screen.xcodeproj/project.pbxproj` for incidental rewrites.
Report changes, checks and their results, and material limitations concisely.
Do not rerun passed checks without a new change, failure, or concrete concern.
