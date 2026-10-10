# Release checklist

Procaine is a development build. Complete these checks before distributing a release;
macOS 13 is the deployment minimum, not a tested compatibility guarantee.

## Build and behavior

- Run `./scripts/check.sh` for policy tests, a universal build, and signature verification.
- Verify both opt-in sleep actions, manual recovery, quit/crash recovery, and denied Bluetooth access.
- Verify actual launch at login, hidden-icon Settings access, sleep/full-wake behavior,
  maintenance wakes, and accessory reconnection on each claimed supported configuration.
- Confirm Logi Options+ controls return after wake. Logi-only mode must leave Bluetooth unchanged.
- Resolve release security settings: the default sandboxed build cannot stop the Logi service.
  An unsandboxed test result does not validate the final distribution configuration.

## Distribution

- Preserve the MIT license and upstream attribution; review outgoing history and artifacts for private data.
- Configure Developer ID signing and notarization; submit using `scripts/prepare-release.sh`.
- Test the actual quarantined download, installation, upgrade, login item, and removal.
- Disable competing utilities and their login items before replacement; retain a rollback copy.
- Publish the release archive before its Homebrew cask, then test cask installation and removal.

No instant reconnection, battery-saving, or universal compatibility claim is established.
