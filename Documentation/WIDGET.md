# Aura desktop widget

`AuraWidget.xcodeproj` builds the existing WidgetKit small/medium desktop and
Notification Center widget as a macOS 15+ app extension. The workspace includes
this target. `scripts/build-widget.sh OUTPUT_DIRECTORY` builds an unsigned real
`.appex`; `package-app.sh` embeds it in `Aura.app/Contents/PlugIns` before signing
inside-out (Sparkle, widget, host). Versions and build numbers follow the host.

The app and sandboxed extension use the existing `group.fm.aura.Aura` suite.
Private Mode now redacts metadata, platform and progress **before persistence**,
not just when rendering. No suite rename or existing-data migration occurs.

For isolated packaging/CI, use `AURA_SIGNING_IDENTITY=-`. These ad-hoc artifacts
prove compilation, embedding, metadata consistency and signature integrity.
They do not prove app-group access or widget-gallery acceptance on hardware.
`verify-package.sh` retains its host/Sparkle checks and additionally checks the
extension signature, matching team, sandbox entitlement, shared group,
executable, extension point and host/extension versions.

For provisioned packaging, supply all three explicitly:

- `AURA_SIGNING_IDENTITY`: signing identity hash.
- `AURA_HOST_PROVISIONING_PROFILE`: profile for `fm.aura.Aura`.
- `AURA_WIDGET_PROVISIONING_PROFILE`: profile for `fm.aura.Aura.Widget`.

The profiles must be unexpired, authorize the same team and exact App IDs, and
contain `group.fm.aura.Aura`. Packaging validates and embeds these profiles;
it never registers IDs, installs profiles or changes developer configuration.
The host retains its existing automation entitlement and sandbox policy. Only
the extension is sandboxed. Real signing fails closed when profiles are absent.
No compatible profiles or Developer ID identity were available during this pass.

Remaining release acceptance: provision both App IDs/group, verify actual signed
launch and shared defaults access on a clean test Mac, add the widget from the
gallery, verify timeline/progress refresh and Private Mode entry/exit. Verify
privacy also removes the previous public snapshot from the shared suite. Test
upgrade from the existing installed host with an existing widget. Keep these as
hardware gates; an unsigned build or ad-hoc signature does not satisfy them.

The existing tag release workflow still explicitly selects ad-hoc signing and
creates draft artifacts. Before a widget-capable public release, its packaging
step must be configured with the reviewed signing identity and matching profiles
through secure CI inputs, and provisioned hardware acceptance must pass. No CI
secrets were installed or release signing policy silently changed by this PR.
