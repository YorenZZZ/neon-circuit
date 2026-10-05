# Verification

Run `./scripts/build.sh` followed by `./tests/check.sh`.

These checks verify both binary slices and bundle signatures, decode every
themed cursor, reject malformed hotspots, PNGs and animation metadata, and
exercise the application's read-only diagnostics. They do not register
cursors, create original backups, change settings or enable login items.

On a supported Mac in a logged-in graphical session, this additional check
reads system cursor mappings and images without changing them:

```sh
"build/NEON Circuit.app/Contents/MacOS/neon-cursorctl" preflight Resources/NEON-CIRCUIT.cape
```

CI only establishes compilation and offline validation. It does not establish
compatibility, apply/restore success, startup behavior, or Gatekeeper acceptance.
Before extending the support table or distributing an application, manually
validate first launch, backup, apply, readback, restore, menu controls, wake,
and login behavior on the claimed OS build and hardware.
