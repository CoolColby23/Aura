# Building & Preview Builds

Local debug build:

```bash
swift build -c debug
```

Build and replace the local copy in `/Applications`:

```bash
./scripts/sync-preview-app.sh
```

`scripts/package-app.sh` creates `Aura.app` in the repository without
installing it. Local preview builds omit the iCloud KVS entitlement because a
development certificate alone cannot authorize iCloud. For a provisioned
release build that includes cross-device theme syncing, set
`AURA_ENABLE_ICLOUD_SYNC=1`; the packager resolves the signing team's KVS
identifier into the release entitlement.

The packager selects an available Apple Development certificate by its unique
identity hash. Set `AURA_SIGNING_IDENTITY=-` for an ad-hoc preview, or set
it to a specific certificate hash when several signing identities are present.

CI preview builds are triggered on branches matching `preview/**` and on pull requests to `main`. They run tests, package a DMG, and upload it as a workflow artifact (not a GitHub Release).

Production and pre-release GitHub Releases are created only from `v*` tags via `.github/workflows/release.yml`. See `CONTRIBUTING.md`.
