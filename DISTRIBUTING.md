# Distributing Mac App Volume Control

The recommended public distribution path is direct distribution with Developer ID signing and Apple notarization, then publishing the notarized zip through GitHub Releases or a website.

## One-Time Setup

1. Enroll in the Apple Developer Program.
2. Create or download a `Developer ID Application` certificate in Xcode.
3. Create a notarytool keychain profile:

```sh
xcrun notarytool store-credentials "mac-app-volume-control" \
  --apple-id "you@example.com" \
  --team-id "TEAMID" \
  --password "app-specific-password"
```

## Local Test Build

```sh
scripts/package-local.sh
```

This creates:

```sh
.dist/Mac App Volume Control.app
.dist/MacAppVolumeControl.zip
```

The local build is ad-hoc signed and is intended for testing on your Mac.

## Release Build

```sh
DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (TEAMID)" \
NOTARY_PROFILE="mac-app-volume-control" \
scripts/package-release.sh
```

This creates a Developer ID signed, notarized, and stapled app plus a zip ready for GitHub Releases.

## Notes

- macOS users have the smoothest install experience when the app is signed with Developer ID and notarized.
- Free distribution is fine; GitHub Releases is enough as a hosting channel.
- If you include third-party character-inspired icons, confirm you have the rights to redistribute them before publishing.
