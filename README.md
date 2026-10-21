# Procaine

<img src="images/procaine-icon-v03.png" width="96" alt="Procaine molecular Bluetooth icon">

**Bluetooth sleep protection with simple everyday controls.**

Procaine is a native macOS menu-bar utility and maintenance fork of
[Bluesnooze](https://github.com/odlp/bluesnooze). Choose independent sleep actions:
turn Bluetooth off, pause Logi Options+, or use both. Both actions start disabled;
starting the app leaves Bluetooth unchanged.

This first release is in development. No Procaine download or Homebrew cask has
been published yet. The deployment minimum is macOS 13; that is not a claim that
every version or Mac has been tested.

## Everyday controls

- Toggle Bluetooth sleep control and Logi Options+ sleep control independently.
- The menu-bar mark shows molecular details when either action is selected and a simpler outline when both are off.
- Bluetooth returns on wake only if Procaine turned it off for that sleep cycle.
- Pause or resume automation without immediately changing Bluetooth.
- See the Bluetooth power state reported by macOS and whether a change was confirmed.
- Restore Bluetooth or Logi Options+ manually after unconfirmed restoration.
- Open Bluetooth settings and manage launch at login.

**Logi Options+ mode is experimental.** The default sandboxed build cannot stop
the service; a local test build without App Sandbox passed stop/restore validation.
Release security settings and actual sleep/wake checks remain pending. The intended
action stops only the supported user background
service, restores it on wake, and leaves Bluetooth power alone. It does not change
Logi login preferences or control its updater. If Procaine crashes while the service
is stopped, reopen Procaine to recover; custom controls may be unavailable until then.
Normal Quit attempts restoration first. Sleep benefits and Watch unlock remain unverified.

In Settings, turn off **Show menu bar icon** to hide it. Open Procaine from
Applications or Spotlight to return to Settings, pause, or recover. If Bluesnooze
or another Procaine copy is running, automation pauses to avoid conflicts.

## Limits

- **Apple Watch unlock:** it requires Bluetooth. Sleep protection can interfere;
  leave the Bluetooth sleep action off when you need Watch unlock. Logi-only mode
  leaves the radio on; combined Watch behavior still needs testing.
- Bluetooth power control uses a private macOS API. Power reports do not prove
  accessory readiness, and no instant reconnection or battery-saving guarantee is made.
- Procaine does not repair interference, change audio routing, unpair devices, or
  reset Bluetooth system services. Logi control is opt-in and limited to its supported service.
- Device shortcuts, hotkeys, and audio routing are future work, not current features.

## Build and check

Use Xcode with the macOS SDK. There are no third-party runtime dependencies.

```sh
open Procaine.xcodeproj
./scripts/check.sh
```

The check script runs hardware-free policy tests and builds an ad-hoc-signed
universal app. It does not install or launch the app or toggle Bluetooth.

See the [release checklist](docs/release-checklist.md) before replacing an
installed copy, notarizing, or publishing. Disable Bluesnooze's login item and quit
it before an approved replacement. The new app identity may require Bluetooth
permission again; enable Procaine's own login item after installation.

## Attribution

Based on Bluesnooze by Oliver Peate and its contributors. The upstream history and
[MIT license](LICENSE) are preserved. Procaine is independently maintained and is
not an upstream Bluesnooze release.
