# NEON Circuit

Open-source cyberpunk cursors for macOS. Cyan outlines, magenta circuitry, and graphite shapes give arrows, text selection, grabbing, resizing, and background activity a consistent look.

**Version 0.1.0 preview is ad hoc signed and has not completed Developer ID signing or Apple notarization. Its first launch may require your approval in Privacy & Security; the illustrated steps are below.**

[Download preview](https://github.com/YorenZZZ/neon-circuit/releases/tag/v0.1.0-preview) · [中文](README.md) · [Compatibility](docs/compatibility.md) · [Build and distribution](docs/distribution.md) · [MIT License](LICENSE)

![NEON Circuit everyday cursors: arrows, text selection, links, grabbing, dragging, and prohibited actions](docs/images/neon-circuit-A.png)

## Download and install

**The theme applies automatically after you first open the app. Downloading a file does not execute it or change your cursors.**

1. Open the [0.1.0 preview Release](https://github.com/YorenZZZ/neon-circuit/releases/tag/v0.1.0-preview) and download `NEON-Circuit-0.1.0-preview-universal.zip` or `.dmg`. GitHub's **Code → Download ZIP** and Release **Source code** archives contain source, not an app installer.
2. ZIP: extract it and drag **NEON Circuit.app** into **Applications**. DMG: open the disk image, drag the app into Applications, then eject the image.
3. Double-click **NEON Circuit** in Applications. If macOS blocks it, follow the first-launch steps below.
4. The menu bar app checks compatibility, then runs **backup → apply → read back and verify**. Once its status shows that the theme is applied, it is ready to use.
5. Enable **Launch at Login** in the menu if you want the theme on each login. It is off by default for a new installation. If macOS requests approval, allow the app in System Settings' Login Items.

The tested configuration is **Apple Silicon · macOS 27.0 (26A428)**. See [compatibility](docs/compatibility.md) for other configurations.

## First launch: allow the app in Privacy & Security

The three images below are **instructional illustrations, not macOS screenshots**, following the currently supported macOS 27 sequence. They use Chinese interface labels: “隐私与安全” means **Privacy & Security**, “打开” means **Open**, “仍要打开” means **Open Anyway**, and “好” means **OK**. Follow these steps for an unidentified-developer or unnotarized-app prompt only after confirming that the app came from this project's Release and has not been altered. [Apple's macOS 27 guide](https://support.apple.com/guide/mac-help/open-a-mac-app-from-an-unknown-developer-mh40616/mac).

### Step 1: try opening the app

Double-click **NEON Circuit.app** in Applications. If macOS displays an unidentified-developer or unnotarized-app prompt, dismiss it. That attempted launch makes the app's approval entry available in System Settings.

![Instructional illustration, step 1: open NEON Circuit and encounter macOS's unidentified-developer or unnotarized-app prompt](docs/images/open-step-1.svg)

### Step 2: click Open in Security

Open **System Settings → Privacy & Security**, scroll to **Security**, and click **Open** for **NEON Circuit**.

The approval button is available for about an hour after the attempted launch. If it has expired, try opening the app again and return to Settings.

![macOS 27 instructional illustration, step 2: click Open for NEON Circuit in the Security area of Privacy & Security](docs/images/open-step-2.svg)

### Step 3: click Open Anyway and authenticate

Click **Open Anyway**, enter your login password, then click **OK**. macOS saves an exception for this individual app; later launches normally work by double-clicking.

![macOS 27 instructional illustration, step 3: click Open Anyway, enter the login password, and click OK to approve NEON Circuit](docs/images/open-step-3.svg)

Some older macOS versions use **Open Anyway → Open** instead. Follow the prompts for that version; this app's runtime support remains macOS 27.

Company- or school-managed Macs may restrict this option. If the alert says the app **is damaged, will damage your computer, or contains detected malware**, stop installation and check the download source; do not treat that alert as the unnotarized-app prompt described above. Approval also does not expand the [tested configurations](docs/compatibility.md).

## Using the app

NEON Circuit lives in the menu bar. Click its cursor icon to manage the theme.

| Menu action | What it does |
| --- | --- |
| Reapply Theme | Applies and verifies the theme, and enables subsequent automatic application. |
| Restore Original Cursors | Restores and verifies the first saved baseline, and stops automatic application. If restoration cannot be verified, the app reports failure and preserves the backup for retry. |
| Launch at Login | Lets you choose whether to register a login item. |
| Open Backup Folder | Opens your local recovery files and the most recent operation record. |
| Getting Started / Help | Shows a short usage guide. |
| Quit | Closes the menu bar app. The currently applied cursors remain until session cursor reset or reboot; restore them first if desired. |

When the theme is enabled, the app reapplies it after wake or session activation. Restoring your cursors stops this behavior.

The first backup captures the current session's cursors. If another cursor tool or an older theme is active, use that tool to restore the macOS originals, quit it, and reboot. Confirm the original appearance before first opening NEON Circuit so its recovery baseline matches the originals you expect.

Backups and operation records stay in your user's `~/Library/Application Support/NEON Circuit/`. Keep the backup until you have restored your cursors. An incomplete backup or a system build mismatch stops the operation and shows an error. See [compatibility](docs/compatibility.md) before updating macOS.

## Examples

These design atlases show the theme's functional states and its appearance on dark and light backgrounds. They are not screenshots from every app. The theme currently covers **50 system cursor registration keys**; the atlas includes **56 design states**, including compatibility and special designs that the current system replacement interface does not use.

### Resizing and navigation

![NEON Circuit resizing and navigation cursors, including moving, zooming, waiting, and background activity designs](docs/images/neon-circuit-B.png)

Waiting and activity designs are shown as animation keyframes. **The native macOS spinning wait cursor remains unchanged in this version.** The background activity animation can be replaced. B10 is a theme design preview, not a claim that the system spinning wait cursor is replaced.

<details>
<summary>More examples: window edges, resizing, and special states</summary>

**Bidirectional and inward edge resizing**

![NEON Circuit bidirectional and inward edge resizing cursors](docs/images/neon-circuit-C.png)

**Inward and outward resizing**

![NEON Circuit inward and outward window resizing cursors](docs/images/neon-circuit-D.png)

**Compatibility and special-state designs**

![NEON Circuit compatibility and special-state design atlas](docs/images/neon-circuit-E.png)

</details>

## Questions

**Why do some cursors stay unchanged?** NEON Circuit replaces system cursor registrations in your current login session. App-drawn pointers, custom webpage image cursors, game crosshairs, FileVault unlock, and pre-login screens are outside this scope. An app must request a particular system cursor for that state to appear.

**What if opening the app does not apply the theme?** Check the menu bar status and try Reapply Theme. If the app reports an incompatible system version or cursor interface, keep the original state and check [compatibility](docs/compatibility.md). Avoid having multiple cursor tools apply themes automatically at the same time.

**Will reopening the app override my restore choice?** No. The app remembers restoration. Choose Reapply Theme to enable the theme and automatic application again.

**How do I uninstall?** Restore your cursors and wait for successful verification, disable Launch at Login, quit the app, then delete NEON Circuit.app from Applications. Keep the recovery backup initially.

**Does the app connect to a server?** Cursor operations, backup, verification, and settings stay on your Mac. The app has no account, telemetry, or auto-update service. macOS performs its own checks for downloaded software.

## Build from source

You need macOS and Apple's Xcode Command Line Tools. Included theme, icon, and example assets require no Node.js, Python, or additional libraries. Download or clone the source and enter the project directory in Terminal:

```sh
# Only if Command Line Tools are not installed
xcode-select --install
./scripts/build.sh
open "build/NEON Circuit.app"
# Optional: create ZIP and DMG files locally
./scripts/package.sh
```

The build script creates `build/NEON Circuit.app`; packaging writes preview ZIP and DMG files to `dist/` and does not itself upload or publish them. The build targets a Universal app containing `arm64` and `x86_64`. A compiled Intel binary is not evidence of Intel runtime compatibility. The current preview is ad hoc signed and unnotarized; see [build and distribution](docs/distribution.md) for a future Developer ID release workflow.

## License and acknowledgments

The application source and original theme assets use the [MIT License](LICENSE). Cursor interface research and compatibility work were informed by the [Mousecape](https://github.com/alexzielenski/Mousecape) community. This project does not bundle or distribute the Mousecape app. Cursor replacement uses private macOS interfaces and needs validation after system updates.

For compatibility reports, include your Mac chip, macOS version and build, app version, the failed action, and the menu bar message. Do not attach full personal paths, cursor backup files, or unreviewed operation logs.
