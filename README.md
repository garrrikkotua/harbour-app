# Harbour Control

A native macOS focus app from Pairmind Limited. Block distracting websites and apps for 1 minute to 24 hours. The app has no early-cancel button; quitting the window does not end a block.

## Install

[Download from GitHub Releases](https://github.com/garrrikkotua/harbour-app/releases/latest).

1. Download **Harbour-Control-latest.dmg** from a signed release.
2. Open the disk image and drag **Harbour Control.app** onto **Applications**.
3. Open the app from Applications and complete the introduction.
4. Choose websites, apps, and a duration. Starting a block requires macOS administrator authorization.

**Requirements:** macOS 13 Ventura or later, Apple Silicon or Intel.

The new release workflow produces Developer ID-signed, Apple-notarized installers. Older v0.1.0 downloads are unsigned; they are not replaced until a new release is published. Build from source if no signed release is available yet.

Use **Harbour Control → Check for Updates…** to open the latest GitHub release. Updates are installed manually when no block is active. Checksums are included with new releases in `SHA256SUMS.txt`.

## Features

- Website presets for social media, video, and news.
- App picker with icons and protection for system recovery tools.
- Hosts-file blocking plus IP rules in the macOS packet filter.
- Background enforcement that resumes after reboot.
- Add more websites and apps during a session; accepted additions persist across daemon restarts.
- App-only sessions leave network configuration alone.

## What to expect

Website blocking covers the domain you enter and its `www` variant. Add other subdomains explicitly or choose a preset. IP rules update every five minutes. Secure DNS endpoints are blocked during website sessions, while ordinary DNS on port 53 remains available.

This is a focus tool, not a security boundary against an administrator. VPNs, proxies, custom encrypted DNS, and changing CDN addresses can affect coverage. Sites sharing a blocked IP may also be affected. Blocking a Meta service can affect other Meta services because their network ranges overlap. Firewall activation can interrupt existing network connections.

Blocked apps are terminated approximately once a second. Save work before starting a block. System recovery tools are excluded. Moving or renaming an app can bypass path-based enforcement.

## Privacy and storage

Settings and runtime additions are stored in `~/Library/Application Support/Harbour/`. Active state is stored in `/var/db/harbour/state.json`. The helper is installed to `/Library/PrivilegedHelperTools/com.harbour.daemon`, with a launchd job at `/Library/LaunchDaemons/com.harbour.daemon.plist`.

Harbour has no analytics or account service. Website icons are requested from Google's favicon service, which receives the requested hostname. Website enforcement makes DNS queries; normal network providers can observe those. Diagnostics in `/var/log/harbour-daemon.log` can contain blocked domains and app paths.

## Uninstall

Wait until the block expires, then move the app to the Trash. The daemon removes the active state, launchd job, and its network rules at expiry. Its inactive helper executable may remain; it can be removed by an administrator. Settings can be removed from `~/Library/Application Support/Harbour/`.

For a malfunction, see [recovery guidance](docs/RELEASING.md#recovery). Deleting state files while a block is active can prevent normal cleanup.

## Build from source

Requires Xcode 15 or later with command-line tools selected:

```sh
git clone https://github.com/garrrikkotua/harbour-app.git
cd harbour-app
swift test
./build.sh
open "build/Harbour Control.app"
```

`build.sh` produces a universal app in `build/Harbour Control.app`. Local builds use ad-hoc signing unless `SIGNING_IDENTITY` is supplied. Use `UNIVERSAL=0 ./build.sh` for faster local iteration.

```text
Sources/Harbour/         SwiftUI app and helper installation
Sources/HarbourCore/     Shared models, validation, presets, safety rules
Sources/HarbourDaemon/   Hosts, packet-filter, and app enforcement
Tests/HarbourCoreTests/  Shared-logic regression tests
scripts/                Signed release packaging
```

## Signed GitHub releases

See [release setup and acceptance checks](docs/RELEASING.md) for Pairmind Limited signing, notarization, and the required GitHub secrets. Tags such as `v0.2.0` trigger publication; manual workflow runs create draft releases. The pipeline refuses to publish if signing or notarization fails.

Automated tests and universal builds do not replace testing installation, block expiry, and reboot recovery on real Macs.

## License

MIT. See [LICENSE](LICENSE). Inspired by [SelfControl](https://github.com/SelfControlApp/selfcontrol).
