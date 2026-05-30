# Mac App Volume Control

A macOS menu bar mixer for adjusting per-app audio volume.

GitHub repository:

```text
https://github.com/hjin9a/mac-app-volume-control
```

## Build

```sh
swift build -c release
```

The executable is written to:

```sh
`.build/release/MacAppVolumeControl`
```

## Notes

- Requires macOS 14.2 or newer.
- Per-app audio capture may require Screen & System Audio Recording permission.
- The app bundle is packaged by `scripts/package-local.sh`.
- Public distribution should use Developer ID signing and notarization for the smoothest Gatekeeper experience.
- See `DISTRIBUTING.md` for the release flow.
