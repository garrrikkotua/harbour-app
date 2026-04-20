# Harbour

> A native macOS app that blocks distracting websites **and apps** for up to 24 hours.
> Once started, you can't cancel — you wait it out.

<p align="center">
  <img src="docs/screenshots/hero.png" width="520" alt="Harbour setup screen">
</p>

Inspired by [SelfControl](https://github.com/SelfControlApp/selfcontrol), but:

- written in modern **Swift + SwiftUI** (not Objective-C/C)
- also blocks **native Mac apps**, not just websites
- survives VPNs and DoH-aware browsers (Arc, Firefox, Chrome) via packet-filter rules
- ships with presets (Social Media, Video, News) and real favicons for your blocklist

---

## Screens

| Onboarding | Setup | Active |
|:-:|:-:|:-:|
| ![Onboarding](docs/screenshots/onboarding.png) | ![Setup](docs/screenshots/setup.png) | ![Active](docs/screenshots/active.png) |

---

## Install

Download the latest `.dmg` from [Releases](https://github.com/garrrikkotua/harbour-app/releases/latest), open it, and drag `Harbour.app` to `Applications`.

> **First launch:** Harbour is unsigned (no Apple Developer certificate). Right-click the app in Finder → **Open** → **Open** to bypass Gatekeeper. After that it launches normally.
>
> Or, in one line: `xattr -cr /Applications/Harbour.app`

### Uninstall

When no block is active, drag `Harbour.app` to the Trash. The daemon only exists during a block and uninstalls itself when the timer expires. To wipe a stuck install:

```sh
sudo launchctl bootout system/com.harbour.daemon
sudo rm /Library/LaunchDaemons/com.harbour.daemon.plist
sudo rm /usr/local/bin/harbour-daemon
sudo rm -rf /var/db/harbour
```

---

## How it works

Harbour stacks three layers of blocking, each designed to catch what the one above misses:

| Layer | What it blocks | Can be bypassed by |
|---|---|---|
| `/etc/hosts` (0.0.0.0 sink) | Standard OS DNS lookups | Browsers that aggressively use DoH |
| `pfctl` packet filter rules | Outbound TCP/UDP to resolved IPs | New IPs the CDN rotates to mid-session |
| App-process polling (libproc) | Launching/running blocked `.app` bundles | Processes below PID 100 (system critical — intentionally skipped) |

Whenever any block is active, Harbour also implicitly blocks the public DoH resolvers (Cloudflare, Google, Quad9, NextDNS, AdGuard, OpenDNS) at both DNS and IP level — so DoH-enabled browsers can't phone home for alternate DNS. For Meta services, Harbour blocks the full AS32934 IP range (21 CIDR blocks), so Facebook/Instagram/Threads stay blocked even if DNS rotates.

### Architecture

```
Harbour.app/
  Contents/
    MacOS/Harbour              # SwiftUI GUI
    Resources/harbour-daemon   # privileged enforcer, installed to /usr/local/bin on Start Block
```

On **Start Block**, the GUI:

1. Writes `state.json` + a `launchd` plist to `/tmp`
2. Runs an `osascript … with administrator privileges` shell script (one-time password prompt)
3. Installs daemon → `/usr/local/bin/harbour-daemon`, plist → `/Library/LaunchDaemons/com.harbour.daemon.plist`, state → `/var/db/harbour/state.json`
4. `launchctl bootstrap system …` starts the daemon

The daemon:

1. Reads state, appends an `# HARBOUR_BLOCK_START … END` section to `/etc/hosts`
2. Launches an async thread to resolve every blocked domain via `dig` (including DoH endpoints)
3. Writes `pfctl` rules to `/etc/pf.anchors/org.harbour`, appends a marker-delimited anchor to `/etc/pf.conf`, and runs `pfctl -E -f /etc/pf.conf -F states`
4. Every 1s: enumerates all processes via `libproc.proc_listallpids` and `SIGKILL`s any whose path lives inside a blocked `.app` bundle
5. Every 30s: re-asserts `/etc/hosts`
6. Every 5min: re-resolves IPs and *accumulates* them into the pfctl ruleset (CDN-rotation proof)
7. When `Date() >= endTime`: strips `/etc/hosts` section, empties anchor file, reverts `/etc/pf.conf`, releases pfctl's enable token (`pfctl -X <token>`), deletes plist, unloads self

### What Harbour won't do

- **Wildcard subdomains.** `/etc/hosts` is exact-match only. Blocking `youtube.com` won't catch `i.ytimg.com` — add the subdomain explicitly, or pick the Video preset which covers common ones.
- **Block arbitrary IPs.** CDNs like Cloudflare serve thousands of sites from the same IPs. Blocking Cloudflare's whole AS would break the web.
- **Kill system processes.** Finder, Dock, SystemUIServer, Terminal, System Settings, Activity Monitor, Console, Keychain Access are on a defence-in-depth safelist — even if their paths somehow landed in your blocklist, the daemon refuses to kill them.

---

## Build from source

Requires macOS 13+ and Xcode 15+ (for Swift 5.9+).

```sh
git clone https://github.com/garrrikkotua/harbour-app.git
cd harbour-app
./build.sh
open build/Harbour.app
```

`build.sh` uses Swift Package Manager to produce two executables:

- `Harbour` — SwiftUI GUI (`Sources/Harbour/`)
- `harbour-daemon` — root enforcer (`Sources/HarbourDaemon/`)

…and assembles them into `build/Harbour.app` with ad-hoc codesigning. No Xcode project needed.

### Project layout

```
Sources/
  Harbour/                    # SwiftUI GUI
    HarbourApp.swift          # @main entry, first-run → onboarding
    ContentView.swift         # Setup + Active screens
    OnboardingView.swift      # 4-step first-run intro
    AppPickerView.swift       # Spotlight-style app grid
    BlockManager.swift        # Config persistence, state polling
    HelperInstaller.swift     # Privileged install shell script
    Presets.swift             # Social / Video / News presets
    FAQView.swift             # In-app help
    ConfirmView.swift         # Pre-block confirmation
    Safety.swift              # Critical-app safelist
    Theme.swift               # Navy + parchment design system
    FaviconView.swift         # Favicons via Google s2
    HarbourIcons.swift        # Custom lighthouse / ship's wheel
    Models.swift              # Codable types shared with daemon

  HarbourDaemon/              # root enforcer
    main.swift                # hosts, pfctl, libproc kill loop
```

---

## Releases

Releases are **tag-triggered**, not per-commit. To cut a release:

```sh
git tag v0.2.0
git push --tags
```

GitHub Actions (see `.github/workflows/release.yml`) then:
1. Builds `Harbour.app`
2. Creates a `.zip` and `.dmg`
3. Publishes a GitHub Release with both attached and auto-generated changelog

You can also trigger a build manually from the Actions tab (**workflow_dispatch**).

---

## Contributing

PRs welcome — small and focused preferred. Please:
- keep the SwiftUI code SwiftUI, not AppKit where avoidable
- run a 5-minute block locally before opening a PR that touches the daemon
- don't add features to the "can't cancel" escape hatch — defeating the point

---

## License

MIT. See [LICENSE](LICENSE).

## Acknowledgements

- [SelfControl](https://github.com/SelfControlApp/selfcontrol) for the `/etc/hosts` + `pfctl` approach and the Meta IP range list
- Apple's New York serif for display typography
- [Fraunces](https://fonts.google.com/specimen/Fraunces) for design inspiration
