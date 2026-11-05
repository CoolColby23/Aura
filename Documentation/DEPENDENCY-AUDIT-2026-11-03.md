# Dependency maintenance — 2026-11-03

Verified stable releases from each upstream's official GitHub Releases API and release notes, including dereferencing annotated action tags to commits. No prereleases or floating action tags were selected.

| Dependency | Before | Selected stable release | Scope |
| --- | --- | --- | --- |
| [Sparkle](https://github.com/sparkle-project/Sparkle/releases/tag/2.10.1) | 2.10.0 | 2.10.1, `ab7d71291238df6e0492143b120c9b696a35f603` | Package.swift, SwiftPM and iOS Xcode resolved graphs |
| [CodeQL Action](https://github.com/github/codeql-action/releases/tag/v4.39.2) | 4.38.2 | 4.39.2, `1fc58d04a4d4374f921bdac573c3811c240f9c26` | Both init and analyze |
| [upload-artifact](https://github.com/actions/upload-artifact/releases/tag/v7.0.2) | 7.0.1 | 7.0.2, `cf430e030ddbb5b0abf93d22962f4752f3646cd9` | Preview DMG artifacts |
| [checkout](https://github.com/actions/checkout/releases/tag/v7.0.1) | 7.0.1 | unchanged | All workflows |
| [setup-xcode](https://github.com/maxim-lobanov/setup-xcode/releases/tag/v1.7.0) | 1.7.0 | unchanged | All Swift workflows |
| [github-script](https://github.com/actions/github-script/releases/tag/v9.0.0) | 9.0.0 | unchanged | PR size advisory |
| [action-gh-release](https://github.com/softprops/action-gh-release/releases/tag/v3.0.3) | 3.0.3 | unchanged | Release workflow |

The root manifest is the only Swift package manifest. iOS consumes the local AuraCore product; Xcode resolves the root package graph, including Sparkle, although Sparkle is linked only by the macOS executable. Both tracked resolved files now select the same Sparkle revision. WidgetExtension is source-only, has no independent resolved graph, and is checked by `scripts/verify-widget-source.sh`. There are no npm/pnpm/yarn/CocoaPods/Carthage manifests or locks in this repository.

Sparkle 2.10.1 fixes Unicode-normalized installation paths, appcast namespaces and release-notes links. Its macOS 12 minimum is compatible with Aura's macOS 15 minimum. CocoaPods removal does not affect this SwiftPM project. Release appcasts continue to use upstream `generate_appcast`; updater Ed25519 verification, nested framework signing and package signature checks remain enabled. No major-version migration is needed in this batch.

Open bot PR overlap at audit time: #39 selects Sparkle 2.10.1 but updates only the root lock; #34 selects upload-artifact 7.0.2; #40/#41 select CodeQL 4.39.1. This maintenance batch includes the coordinated equivalent changes and the newer 4.39.2 release; do not separately apply older pins. No bot PR was merged or closed.

CodeQL's `releases/latest` is a **bundle** release, not necessarily an Action release. The selected Action release is 4.39.2 (default bundle 2.27.4). Keep macOS 15/Xcode 26.0 for traced Swift scans: upstream [does not support Xcode 27/macOS 27/Swift 6.4 tracing](https://github.blog/changelog/2026-10-19-codeql-changes-for-macos-27-xcode-27-and-swift-6-4/). Moving that audit runner/toolchain is deferred until tracing support is available; do not disable the scan to upgrade it.

All five published [Sparkle repository security advisories](https://github.com/sparkle-project/Sparkle/security/advisories) were checked: GHSA-3x7w-j75x-ppq5 and GHSA-4v99-qgq9-6pxp are patched in 2.9.6; GHSA-gmj2-gq3j-vqmj in 2.9.5; GHSA-hg88-v3cw-3qrh and GHSA-g3hp-f6mg-559v in 2.9.2. Selected 2.10.1 is outside their affected ranges. This is an upstream advisory check, not proof that an audit found no possible vulnerabilities.
