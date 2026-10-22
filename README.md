# The Magical Rug for Mac

A native Mac edition of [The Magical Rug](https://github.com/Achraaaff/The-Magical-Rug), prepared for **an Intel Mac running macOS 15.7.1**. It shares the Linux version's C++ cloth physics and interaction rules, with an AppKit desktop panel and Metal renderer.

## Install on your friend's Mac

1. Download **The-Magical-Rug-Mac-universal.dmg** from [Releases](https://github.com/Achraaaff/The-Magical-Rug-Mac/releases/latest).
2. Open the disk image and drag **The Magical Rug.app** to **Applications**.
3. Open the app from Applications. If macOS blocks the first launch, follow **System Settings → Privacy & Security → Open Anyway** after trying to open it once. The build is ad-hoc signed, not Apple-notarized; do not disable Gatekeeper or other system protections. [Apple's instructions](https://support.apple.com/en-us/102445).
4. In the welcome screen, leave **Open automatically when I log in** checked if wanted. Approve it in macOS Login Items if prompted.

Your friend does **not** need Codex, Terminal commands, Homebrew, Qt, Xcode, or the source code. You can download the DMG and send it to her directly; she does not need access to this private repository to use a file you send.

The download contains native **Intel x86_64 and Apple Silicon arm64** code. Minimum macOS is **14.0**; the stated target is Intel / **15.7.1**. A Metal-compatible GPU is required. No NVIDIA GPU is needed.

## Controls

| Action | Control |
| --- | --- |
| Move | Drag the middle |
| Lift and fold over the top | Drag a corner toward the middle |
| Lock / unlock | **Control–Option–R** |
| Resize | Option-drag, or the rug menu |
| Rotate | Scroll over the rug, or Shift-drag |
| Fold / flatten | Double-click, or the rug menu |
| Recover position | **Center Rug** / **Flatten Rug** in the rug menu |
| Use another monitor | Open the rug menu on that display, then **Move to This Display** |

The menu bar icon is a pair of overlapping rectangles. It provides lock, size, fold, position, login, Help, and Quit controls. Right-clicking an unlocked rug opens the same menu.

When **locked**, the current pose freezes, the window ignores all mouse input, and clicks pass through to Finder. No badge, toolbar, or hover effect is drawn on the rug. Unlocking restores interaction. The lock state and cloth shape survive a normal quit and relaunch or a login restart.

The rug is a separate transparent desktop-level window above Finder's icons and below normal apps. It does not alter the wallpaper, desktop sorting, file positions, or icon visibility. File drags started in Finder pass through it. It does not scan icon positions or simulate bumps over files; no Accessibility, Finder Automation, or Screen Recording permission is needed.

## Validation and limits

**A flawless first run cannot be promised without checking the actual Mac.** The goal is a self-contained download that avoids development work on your friend's laptop.

The build workflow runs on GitHub's **Intel macOS 15 runner** and:

- checks direct movement, silent locking, saved-state restoration, and viewport changes;
- folds all four corners, checks that the underside remains visible on top, detects triangle crossings, and bounds material stretch and opposite-corner movement;
- compiles the native Cocoa app for **x86_64 and arm64**;
- compiles the Metal shaders ahead of launch;
- checks the universal architectures, bundle resources, plist, and code-signature integrity;
- produces a drag-to-Applications DMG, ZIP, and SHA-256 checksums.

These checks cover the portable model, compilation, and packaging. They do **not** verify the live Finder desktop, first-launch Gatekeeper prompts, GPU visuals, Spaces, Stage Manager, or every monitor arrangement on a physical Mac. The app is not notarized. The bundled Help page explains installation and recovery.

One rug on one selected display is supported. Disconnecting or resizing a display adapts the saved shape while retaining lock state. The app pauses simulation and rendering when settled or locked; a lightweight timer manages click-through while unlocked.

## Build and release

End users should download the DMG. Developers with a Mac and Xcode can run:

```sh
./scripts/test-core.sh
./scripts/build-macos.sh
./scripts/package-macos.sh
```

No package manager or third-party runtime is needed. The build runs the two architecture compilations sequentially. `scripts/test-core.sh` also runs on Linux with a C++17 compiler; that does not test the macOS adapter.

For the hosted build, open **Actions → Build Mac installer → Run workflow**. Set the release tag, such as `v1.0.0`. The workflow builds and publishes the DMG to this repository's private Releases page. Keep release tags unique when making a new version.

By default the app uses an **ad-hoc code signature**. `MAC_SIGN_IDENTITY` can select an installed Apple Developer ID identity for a local build. Developer ID signing and Apple notarization require the owner's Apple credentials and are not configured in the private build workflow. Signature-integrity validation is different from Gatekeeper trust or notarization.

## Implementation

- `Sources/Physics/cloth.hpp`: the unchanged solver copied from the Linux repository, with its origin commit and SHA-256 recorded in `UPSTREAM.json`.
- `Sources/RugModel.hpp`: portable screen projection, picking, movement, gradual lift-over path, lock, saved pose restoration, resizing, and idle behavior.
- `Sources/MagicalRug.mm`: native AppKit panel, Metal rendering, global Carbon hotkey, menu bar controls, Login Items, and macOS state persistence.
- `Resources/Rug.metal`: fully opaque front/back cloth material, depth-tested geometry, and floor shadow.
- `Tests/`: portable interaction and geometric checks.
- `.github/workflows/`: Intel macOS build, package, artifact, and release automation.

GPU geometry uses three bounded buffers and waits only when a free frame is available. Depth testing resolves which cloth layer is visible. Locking cancels an active drag, stops physics, and sets `ignoresMouseEvents` on the whole desktop panel. The hotkey uses Carbon registration rather than a global keyboard monitor, avoiding an Accessibility permission requirement. If the shortcut is occupied, the menu lock remains available.

State lives in the app's macOS preferences domain, **com.achraaaff.TheMagicalRug**. Invalid or excessively stretched saved meshes are rejected. Nothing from the original laptop's personal Plasma configuration is included.

## Troubleshooting and uninstall

- **Won't open:** install in Applications first, try opening once, then follow [Apple's Open Anyway steps](https://support.apple.com/en-us/102445). Managed Macs may prohibit this; that needs the administrator's approval.
- **Rug doesn't move:** it may be locked. Use Control–Option–R or the menu.
- **Shortcut unavailable:** another app may own it. The app reports a conflict and retains the menu control.
- **Rug offscreen or awkwardly folded:** unlock it, then use Center Rug or Flatten Rug.
- **Login setting isn't approved:** allow The Magical Rug in System Settings → General → Login Items, or add it manually there.
- **Remove:** turn off Open at Login, quit from the menu bar, then move the app from Applications to the Trash. No daemon, kernel extension, or system-wide service is installed by this project.

## Credits

MIT-licensed. The Linux cloth solver and texture originated in [siliconbag/under-the-rug](https://github.com/siliconbag/under-the-rug), the original native Mac rug by Artem. The app icon is also from that MIT-licensed project. This edition reuses the revised Linux physics and rules with a new native Mac adapter and installer. Preserve [LICENSE](LICENSE) and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) when redistributing.
