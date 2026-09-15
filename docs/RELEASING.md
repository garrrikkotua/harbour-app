# Signing and releasing Harbour Control

Public releases require a **Developer ID Application** certificate with its private key, hardened runtime, and Apple notarization. An Apple Development or iPhone Distribution certificate cannot replace it.

The existing bundle identifier `com.igor.harbour` is retained for compatibility. Signing identifies the publisher as Pairmind Limited (team `4Q6NYM988Y`).

## Local release

1. Confirm `security find-identity -v -p codesigning` lists `Developer ID Application: Pairmind Limited (4Q6NYM988Y)`.
2. Run `xcrun notarytool store-credentials harbour-release` interactively. Enter your Apple ID, an app-specific password, and team ID `4Q6NYM988Y`. Keep credentials in Keychain, never in the repository or chat.
3. Run:

```sh
swift test
SIGNING_IDENTITY='Developer ID Application: Pairmind Limited (4Q6NYM988Y)' \
NOTARY_PROFILE=harbour-release VERSION=0.2.0 BUILD_NUMBER=2 \
./scripts/package-release.sh
```

The script builds universal binaries, signs the helper before the app, notarizes and staples the app, verifies Gatekeeper acceptance, then creates and notarizes the DMG. The disk image contains an Applications shortcut. ZIP and DMG downloads, a stable `Harbour-Control-latest.dmg` alias, and SHA-256 checksums appear in `build/release/`.

Before publishing, verify the manual acceptance checks below. Create a draft GitHub release with all files in `build/release/`, review it, then publish.

## GitHub Actions setup

Configure these **repository Actions secrets**:

| Secret | Value |
|---|---|
| `APPLE_CERTIFICATE_P12_BASE64` | Base64 of the exported Developer ID Application certificate **and private key** (.p12) |
| `APPLE_CERTIFICATE_PASSWORD` | Password protecting that .p12 |
| `APPLE_SIGNING_IDENTITY` | `Developer ID Application: Pairmind Limited (4Q6NYM988Y)` |
| `APPLE_ID` | Apple ID authorized for the team |
| `APPLE_TEAM_ID` | `4Q6NYM988Y` |
| `APPLE_APP_PASSWORD` | Apple ID app-specific password for notarization |

Export only the relevant signing identity from Keychain Access. Upload secrets through GitHub Settings → Secrets and variables → Actions, or `gh secret set` using stdin. Never commit the .p12 or credentials. The workflow uses a temporary signing keychain and deletes it on completion or failure.

Push a version tag such as `v0.2.0` to publish. Manual dispatch accepts a version and creates a **draft** release at the selected commit. Missing secrets, failed tests, signing failures, rejected notarization, or failed Gatekeeper checks stop publication.

## Manual acceptance checks

Use a test Mac/account and a short block. Website/app enforcement changes system files and terminates blocked apps; save work first.

- Download the notarized DMG from GitHub in a browser; drag the app to Applications and open normally.
- Complete onboarding. Add a website, add an app, choose a duration, and confirm.
- Cancel administrator authorization: app remains responsive and no session starts.
- Start a short website block: blocked site fails, unrelated websites and ordinary DNS work. Repeat with browser secure DNS enabled and the VPNs you intend to support.
- Start an app-only block: selected app exits and cannot remain running; networking is unaffected.
- Add a site and app during a session; verify both are enforced and remain enforced after daemon restart.
- Quit/reopen the GUI and reboot during a block; enforcement and remaining time recover.
- Allow expiry while running and while asleep/rebooted. Check hosts markers, PF anchor rules, token, state, and launchd job are removed; unrelated PF rules remain.
- Test on both Apple Silicon and Intel, including macOS 13. Automated compilation checks both architectures but does not prove runtime compatibility.

## Recovery

The UI deliberately has no cancellation control. For a malfunction, an administrator can unload the daemon:

```sh
sudo launchctl bootout system/com.harbour.daemon
```

The running daemon handles termination by cleaning its hosts and firewall entries. Verify cleanup before deleting `/var/db/harbour`. If the process has crashed, do not merely delete its state: expired state is needed for startup cleanup. Inspect `/var/log/harbour-daemon.log` to diagnose failures. Do not disable PF globally or overwrite `/etc/hosts` or `/etc/pf.conf` with defaults.

## References

- [Apple: Developer ID](https://developer.apple.com/developer-id/)
- [Apple: Notarizing macOS software](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
