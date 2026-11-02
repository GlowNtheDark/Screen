#!/bin/bash

set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
simulator_udid="058EB71A-7C11-4BBA-8030-7F13137575F5"
simulator_name="Apple TV 4K (3rd generation) (at 1080p)"
scheme="Screen tvOS"
bundle_identifier="com.screen.tvos"
extension_bundle_identifier="com.screen.tvos.topshelf"
team_identifier="36VR7266B9"
app_group_identifier="group.com.snowfin.tvos"
derived_data_path="${SCREEN_TVOS_SIMULATOR_DERIVED_DATA_PATH:-/Volumes/External HD/Xcode/DerivedData/Screen-Codex-TVOS-Simulator}"

device_line="$(xcrun simctl list devices available | rg "$simulator_udid" || true)"
if [[ "$device_line" != *"$simulator_name"* ]]; then
	echo "Expected simulator '$simulator_name' ($simulator_udid) is unavailable." >&2
	exit 1
fi

if [[ "$device_line" != *"(Booted)"* ]]; then
	xcrun simctl boot "$simulator_udid"
	xcrun simctl bootstatus "$simulator_udid" -b
fi

echo "Building $scheme for $simulator_name with Simulator entitlements enabled."
xcodebuild -quiet \
	-project "$project_root/Screen.xcodeproj" \
	-scheme "$scheme" \
	-configuration Debug \
	-destination "platform=tvOS Simulator,id=$simulator_udid" \
	-derivedDataPath "$derived_data_path" \
	CODE_SIGNING_ALLOWED=YES \
	CODE_SIGNING_REQUIRED=YES \
	CODE_SIGN_IDENTITY="Apple Development" \
	CODE_SIGN_STYLE=Automatic \
	DEVELOPMENT_TEAM="$team_identifier" \
	build

app_path="$derived_data_path/Build/Products/Debug-appletvsimulator/Screen.app"
app_entitlements="$derived_data_path/Build/Intermediates.noindex/Screen.build/Debug-appletvsimulator/Screen tvOS.build/Screen.app-Simulated.xcent"
extension_entitlements="$derived_data_path/Build/Intermediates.noindex/Screen.build/Debug-appletvsimulator/Screen Top Shelf.build/Screen Top Shelf.appex-Simulated.xcent"

if [[ ! -d "$app_path" || ! -f "$app_entitlements" || ! -f "$extension_entitlements" ]]; then
	echo "The build did not produce the app and Simulator entitlement manifests." >&2
	exit 1
fi

product_bundle_identifier="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app_path/Info.plist")"
app_identifier="$(/usr/libexec/PlistBuddy -c 'Print :application-identifier' "$app_entitlements")"
app_group="$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.application-groups:0' "$app_entitlements")"
extension_identifier="$(/usr/libexec/PlistBuddy -c 'Print :application-identifier' "$extension_entitlements")"
extension_app_group="$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.application-groups:0' "$extension_entitlements")"

if [[ "$product_bundle_identifier" != "$bundle_identifier" \
	|| "$app_identifier" != "$team_identifier.$bundle_identifier" \
	|| "$app_group" != "$app_group_identifier" \
	|| "$extension_identifier" != "$team_identifier.$extension_bundle_identifier" \
	|| "$extension_app_group" != "$app_group_identifier" ]]; then
	echo "The built Simulator entitlements do not match the configured app identity." >&2
	/usr/libexec/PlistBuddy -c Print "$app_entitlements" >&2
	exit 1
fi

signature_details="$(/usr/bin/codesign -dv --verbose=4 "$app_path" 2>&1)"
if [[ "$signature_details" != *"Identifier=$bundle_identifier"* \
	|| "$signature_details" != *"Signature=adhoc"* ]]; then
	echo "The build product is not the expected tvOS Simulator app." >&2
	printf '%s\n' "$signature_details" >&2
	exit 1
fi
/usr/bin/codesign --verify --deep --strict "$app_path"

if ! group_container_before="$(xcrun simctl get_app_container "$simulator_udid" "$bundle_identifier" "$app_group_identifier" 2>/dev/null)"; then
	echo "The simulator has no registered $app_group_identifier container; refusing to install." >&2
	echo "Restore the entitlement-capable simulator installation before routine updates." >&2
	exit 1
fi

echo "Simulator application identifier: $app_identifier"
echo "Simulator app group: $app_group"
echo "Installing the built Debug product in place (no uninstall)."
xcrun simctl install "$simulator_udid" "$app_path"

group_container_after="$(xcrun simctl get_app_container "$simulator_udid" "$bundle_identifier" "$app_group_identifier")"
if [[ "$group_container_after" != "$group_container_before" ]]; then
	echo "The install changed the simulator app-group container; stopping before launch." >&2
	echo "Before: $group_container_before" >&2
	echo "After:  $group_container_after" >&2
	exit 1
fi

xcrun simctl terminate "$simulator_udid" "$bundle_identifier" >/dev/null 2>&1 || true
xcrun simctl launch "$simulator_udid" "$bundle_identifier"
