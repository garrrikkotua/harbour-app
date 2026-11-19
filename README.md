# Harbour Control

A free, open-source macOS focus app by Igor Kotua. Block distracting websites and apps for 1 minute to 24 hours. The app has no early-cancel button; quitting the window does not end a block.

**Website:** [garrrikkotua.github.io/harbour-app](https://garrrikkotua.github.io/harbour-app/) · **Download:** [Harbour-Control-latest.dmg](https://github.com/garrrikkotua/harbour-app/releases/latest/download/Harbour-Control-latest.dmg)

## Install

[Download from GitHub Releases](https://github.com/garrrikkotua/harbour-app/releases/latest).

1. Download **Harbour-Control-latest.dmg** from a signed release.
2. Open the disk image and drag **Harbour Control.app** onto **Applications**.
3. Open the app from Applications and complete the introduction.
4. Choose websites, apps, and a duration. Starting a block requires macOS administrator authorization.

**Requirements:** macOS 13 Ventura or later, Apple Silicon or Intel.

Releases from v0.2.0 onward are Developer ID-signed and notarized by Apple. v0.1.0 was unsigned.

From 0.4.0, Harbour Control updates itself. It checks GitHub once a day and offers each new signed release; **Harbour Control → Check for Updates…** checks now, and **Install Updates Automatically** installs them without asking. Updates are verified with an EdDSA signature and Apple notarization. An update never ends or changes a running block. Earlier versions update manually from the latest release. Checksums are included with new releases in `SHA256SUMS.txt`.

## Features

- Website presets for social media, video, and news.
- App picker with icons and protection for system recovery tools.
- Hosts-file blocking plus IP rules in the macOS packet filter.
- Background enforcement that resumes after reboot.
- Add more websites and apps during a session; accepted additions persist across daemon restarts.
- App-only sessions leave network configuration alone.
- Attempt stats: every time you try to open a blocked website or app is counted, per day and per target, with a 14-day chart and your most-tried distractions.

## What to expect

Website blocking covers the domain you enter with its `www`, `m` and `mobile` variants. Well-known sites (X, YouTube, Reddit, Instagram, Facebook, Threads, TikTok, LinkedIn, Twitch) also cover the hosts they load content from, so a page the browser restores from its cache can't load new posts or media; the list is in `Sources/HarbourCore/RelatedDomains.swift` and leaves out shared CDNs and link shorteners. Add other subdomains explicitly or choose a preset. IP rules update every five minutes. Addresses on shared hosting and CDNs (Cloudflare, Fastly, Vercel, CloudFront, AWS Global Accelerator) are never IP-blocked, because they also serve unrelated sites; those sites are blocked by name only. Refresh the list with `scripts/update-shared-hosting.py`. Secure DNS endpoints are blocked during website sessions, while ordinary DNS on port 53 remains available.

This is a focus tool, not a security boundary against an administrator. VPNs, proxies, custom encrypted DNS, and changing CDN addresses can affect coverage. Sites sharing a blocked IP may also be affected. Blocking a Meta service can affect other Meta services because their network ranges overlap. Firewall activation can interrupt existing network connections.

Attempts are counted once per burst: one page load or app relaunch within a few seconds is one attempt. Website attempts are counted when the browser uses the system resolver; browsers with their own secure DNS or a VPN can skip the count while still being blocked. Apps already open when a block starts are closed without counting.

Blocked apps are terminated approximately once a second. Save work before starting a block. System recovery tools are excluded. Moving or renaming an app can bypass path-based enforcement.

## Privacy and storage

Settings and runtime additions are stored in `~/Library/Application Support/Harbour/`. Active state is stored in `/var/db/harbour/state.json`, and attempt stats per account in `/var/db/harbour/stats-<uid>.json` (kept across blocks: 400 days of detail plus a lifetime total, readable only by root and that account). Blocked names point at the `127.72.66.1` counting sink only after its two ports are bound, the alias is Harbour's own, and PF rules rejecting every other port on that address are loaded; until then, or if any step fails, they go to 0.0.0.0 and nothing is counted.

During a website block, blocked names resolve to `127.72.66.1`, a loopback alias the daemon adds for the session. Its listener reads only the requested hostname (TLS SNI or HTTP `Host`), resets the connection and counts it; nothing is served, logged beyond the domain, or sent anywhere. Local servers on `127.0.0.1` are unaffected. If the alias or ports 80/443 are unavailable, Harbour falls back to the `0.0.0.0` null route without counting. The helper is installed to `/Library/PrivilegedHelperTools/com.harbour.daemon`, with a launchd job at `/Library/LaunchDaemons/com.harbour.daemon.plist`.

Harbour has no analytics or account service. The updater fetches `appcast.xml` from GitHub Releases once a day without sending system details; turn this off with **Check for Updates Automatically**. Website icons are requested from Google's favicon service, which receives the requested hostname. Website enforcement makes DNS queries; normal network providers can observe those. Diagnostics in `/var/log/harbour-daemon.log` can contain blocked domains and app paths; the daemon makes the log root-only, and individual attempts are never logged. Attempt history is kept per account in `/var/db/harbour/stats-<uid>.json`, readable only by root and that account. Website icons in the stats sheet come only from the local cache.

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
site/                   Landing page, deployed to GitHub Pages
```

## Signed GitHub releases

See [release setup and acceptance checks](docs/RELEASING.md) for Pairmind Limited signing, notarization, and the required GitHub secrets. Tags such as `v0.2.0` trigger publication; manual workflow runs create draft releases. The pipeline refuses to publish if signing or notarization fails.

Automated tests and universal builds do not replace testing installation, block expiry, and reboot recovery on real Macs.

## License

MIT. See [LICENSE](LICENSE). Inspired by [SelfControl](https://github.com/SelfControlApp/selfcontrol).
