# AppVolumeGlass

A macOS menu bar mixer for adjusting per-app audio volume.

## Build

```sh
swift build -c release
```

The executable is written to:

```sh
.build/release/AppVolumeGlass
```

## Notes

- Requires macOS 14.2 or newer.
- Per-app audio capture may require Screen & System Audio Recording permission.
- The current app bundle in this workspace is assembled manually under `outputs/AppVolumeGlass`.
- Public distribution should use Developer ID signing and notarization for the smoothest Gatekeeper experience.
