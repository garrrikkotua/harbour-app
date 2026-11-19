# Signing and releasing Harbour Control

Public releases require a **Developer ID Application** certificate with its private key, hardened runtime, and Apple notarization. An Apple Development or iPhone Distribution certificate cannot replace it.

The existing bundle identifier `com.igor.harbour` is retained for compatibility. Signing identifies the publisher as Pairmind Limited (team `4Q6NYM988Y`).

## Local release

1. Confirm `security find-identity -v -p codesigning` lists `Developer ID Application: Pairmind Limited (4Q6NYM988Y)`.
2. Run `xcrun notarytool store-credentials harbour-release` interactively. Use an App Store Connect API key with its key ID and issuer ID, or leave the key path blank to use your Apple ID, an app-specific password, and team ID `4Q6NYM988Y`. Keep credentials in Keychain, never in the repository or chat.
3. Run:

```sh
swift test
SIGNING_IDENTITY='Developer ID Application: Pairmind Limited (4Q6NYM988Y)' \
NOTARY_PROFILE=harbour-release VERSION=0.4.0 \
./scripts/package-release.sh
```

`CFBundleVersion` is derived from the version (`0.4.0` → `400`), so Sparkle sees every release as newer than the last. Keep minor and patch numbers below 100, or pass a larger `BUILD_NUMBER`.

The script builds universal binaries, signs the helper and Sparkle before the app, notarizes and staples the app, verifies Gatekeeper acceptance, then creates and notarizes the DMG. The disk image contains an Applications shortcut. ZIP and DMG downloads, a stable `Harbour-Control-latest.dmg` alias, the Sparkle `appcast.xml`, and SHA-256 checksums appear in `build/release/`. Upload all of them: installed apps read `releases/latest/download/appcast.xml`, so publishing the release (not a draft or pre-release) is what ships the update.

## In-app updates (Sparkle)

The app embeds [Sparkle](https://sparkle-project.org) 2. Each release's ZIP is signed with an EdDSA key; the public half is `SUPublicEDKey` in `Resources/Info.plist`. The private key lives in the maintainer's login keychain (created with Sparkle's `generate_keys`, found under `.build/artifacts/sparkle/Sparkle/bin/` after `swift package resolve`) and in the `SPARKLE_PRIVATE_KEY` Actions secret. Locally, `scripts/make-appcast.sh` signs with the keychain key; in CI it uses the secret.

- Export for CI: `generate_keys -x sparkle-private-key.txt`, then `gh secret set SPARKLE_PRIVATE_KEY < sparkle-private-key.txt` and delete the file.
- Never lose or rotate the key casually: installed apps reject updates signed with any other key. Back it up with the Developer ID certificate.
- Updates must also keep the same Developer ID team, or Sparkle refuses them.

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
| `SPARKLE_PRIVATE_KEY` | Sparkle EdDSA private key from `generate_keys -x` |

Export only the relevant signing identity from Keychain Access. Upload secrets through GitHub Settings → Secrets and variables → Actions, or `gh secret set` using stdin. Never commit the .p12 or credentials. The workflow uses a temporary signing keychain and deletes it on completion or failure.

Push a version tag such as `v0.2.0` to publish. Manual dispatch accepts a version and creates a **draft** release at the selected commit. Missing secrets, failed tests, signing failures, rejected notarization, or failed Gatekeeper checks stop publication.

## Repeatable live smoke test

On a test Mac with the built app, run `sudo python3 scripts/smoke-test.py` from your ordinary account (the disposable app runs as that user, because Harbour never closes root processes) for a 25-second app-only session. Add `--include-websites` for a second 60-second session that blocks example.com and verifies live firewall rules. Both sessions check attempt counting: the app open at block start is not counted and a relaunch counts once; TLS and HTTP connections to the sink count `example.com` once per burst and ignore unblocked hosts; the loopback alias and its ownership marker are removed at expiry, and `stats.json` is mode 0600. Your real `stats.json` is moved aside and put back with its permissions. The script refuses to run over an existing Harbour session, uses a disposable copy of `/bin/sleep` as the blocked app, checks normal timer cleanup, and writes logs under `build/`. Website tests can interrupt existing network connections. This does not cover GUI authorization or reboot recovery.

## Manual acceptance checks

Use a test Mac/account and a short block. Website/app enforcement changes system files and terminates blocked apps; save work first.

- Download the notarized DMG from GitHub in a browser; drag the app to Applications and open normally.
- Complete onboarding. Add a website, add an app, choose a duration, and confirm.
- Cancel administrator authorization: app remains responsive and no session starts.
- Start a short website block: blocked site fails, unrelated websites and ordinary DNS work. Repeat with browser secure DNS enabled and the VPNs you intend to support.
- Start an app-only block: selected app exits and cannot remain running; networking is unaffected.
- Add a site and app during a session; verify both are enforced and remain enforced after daemon restart.
- Try opening a blocked site and a blocked app during a session; **Attempts stopped** increases by one each (bursts within a few seconds count once), and the stats sheet lists them. Apps open at block start are not counted.
- From the previous Sparkle-enabled version, **Check for Updates…** finds the new release, installs it and relaunches, while a running block continues.
- Quit/reopen the GUI and reboot during a block; enforcement and remaining time recover.
- Allow expiry while running and while asleep/rebooted. Check hosts markers, PF anchor rules, token, state, the `127.72.66.1` loopback alias (`ifconfig lo0`), and launchd job are removed; unrelated PF rules remain and `stats.json` is kept.
- Test on both Apple Silicon and Intel, including macOS 13. Automated compilation checks both architectures but does not prove runtime compatibility.

## Recovery

The UI deliberately has no cancellation control. For a malfunction, an administrator can end a block in two steps:

```sh
sudo launchctl bootout system/com.harbour.daemon
sudo rm /var/db/harbour/state.json /Library/LaunchDaemons/com.harbour.daemon.plist
```

The first command stops the daemon. On SIGTERM it removes its hosts entries and firewall rules but keeps its state, because macOS sends the same signal at every restart and shutdown, and a block must survive a reboot. Without the second command the block resumes at the next boot. Run the second command only after the first has finished, so the rules are already gone. The app may keep showing a countdown until it is reopened.

If the daemon has crashed instead, do not delete its state: rerun `sudo launchctl bootstrap system /Library/LaunchDaemons/com.harbour.daemon.plist` so it can reapply or clean up. Inspect `/var/log/harbour-daemon.log` to diagnose failures. Do not disable PF globally or overwrite `/etc/hosts` or `/etc/pf.conf` with defaults.

## References

- [Apple: Developer ID](https://developer.apple.com/developer-id/)
- [Apple: Notarizing macOS software](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
