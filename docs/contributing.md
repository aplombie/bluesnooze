# Contributing

Use Xcode with the macOS SDK. Run `./scripts/check.sh` before submitting changes.
The checks build an ad-hoc-signed app without installing it or changing Bluetooth.

Enable the repository's local privacy checks after cloning:

```sh
git config core.hooksPath .githooks
```

Keep personal agent instructions, planning, diagnostic logs, credentials, and signing
settings local. `AGENTS.md`, `CLAUDE.md`, `.agent/`, `planning/`, and local agent
configuration directories are ignored. Commit and push hooks reject these paths,
including historical copies; GitHub also checks published branch history.
These checks protect designated paths, not arbitrary sensitive content elsewhere.

Preserve the upstream MIT license and attribution. Use synthetic or sanitized test
data. Follow the [release checklist](release-checklist.md) before distributing builds.
