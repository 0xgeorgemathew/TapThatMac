# Packaging and distribution

Build an arm64 `.app` with `bash scripts/build-app.sh`. Signing reads `SIGNING_IDENTITY` and `TEAM_ID` from the environment, falling back to the git-ignored `scripts/signing.env`; the certificate's actual team must match. The build stages and verifies the bundle before replacing `dist/Tap That Mac.app`. Local development builds may fail distribution assessment because they are not notarized.

Use a stable installation location before registering the sensor helper. Register/remove it through the app; building alone does not register it. The app and helper authenticate their exact identifiers and configured signing team. Never run the UI as root.

For distribution, configure a Developer ID Application certificate and a notarytool keychain profile:

```sh
cp scripts/signing.env.example scripts/signing.env
```

Then edit the ignored `scripts/signing.env` with the exact certificate name, Team ID, and notarytool profile. The template is intentionally safe to commit; the real file is ignored.

```sh
SIGNING_IDENTITY='Developer ID Application: Your Name (CERTIFICATE_ID)' \
TEAM_ID='YOURTEAMID' NOTARY_PROFILE='tapthatmac-notary' bash scripts/notarize.sh
bash scripts/create-dmg.sh
```

Notarization submits the app to Apple, staples and verifies it, and produces `dist/tapthatmac.zip`. The separate DMG script packages the current bundle with a drag-to-Applications layout; it does not notarize the DMG itself. Keep credentials in the environment/keychain. No signing identity or credential is stored in this repository or CI.

Before distribution, verify installation, permissions, helper lifecycle and physical detection on a second supported Mac. A successful build or replay does not establish those checks.

## Sharing a development build

Use `SIGNING_IDENTITY=- bash scripts/build-app.sh`, then `bash scripts/create-dmg.sh` for an ad-hoc build. The DMG includes `Start Here.txt` with installation, per-app quarantine removal and manual permission instructions. Accessibility and Input Monitoring still require approval in System Settings. Ad-hoc builds cannot use the authenticated sensor helper.

## Upgrading from the previous name

Tap That Mac uses `com.tapthatmac.app` and the `com.tapthatmac.sensor` helper. macOS may require fresh Accessibility, Input Monitoring and Login Items approval. Before removing the previous app, use its Remove Helper control to unregister its daemon; the renamed app does not remove the old registered helper automatically.

At launch, missing preferences are copied once from the legacy `com.tapthatx.app` domain. Existing new preferences take priority, including later cleared choices. Missing files from `~/Library/Application Support/TapThatX/` are copied into `~/Library/Application Support/Tap That Mac/`; originals and existing destination files are retained. New calibration and runtime files use the new folder. File-copy failures are logged and retried on the next launch.

## Publishing a release

`install.sh` installs the newest GitHub release, betas included. It looks for an asset named `TapThatMac-<version>.zip` containing `Tap That Mac.app`, verifies it against `TapThatMac-<version>.zip.sha256`, clears the download quarantine and installs to `/Applications`.

```sh
bash scripts/release.sh 0.1.0-beta.1
gh release create v0.1.0-beta.1 dist/release/* --prerelease --title 'Tap That Mac 0.1.0-beta.1' --notes-file notes.md
```

The version must start with `CFBundleShortVersionString` from `Packaging/Info.plist`; bump `CFBundleVersion` for every release. The script refuses ad-hoc builds. Sign every release with the same identity, or macOS asks users to approve Accessibility and Input Monitoring again. Releases are signed but not notarized until a Developer ID certificate is configured; the installer and the DMG's `Start Here.txt` explain the first launch.
