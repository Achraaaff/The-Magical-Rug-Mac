Native macOS edition of The Magical Rug, prepared for an Intel Mac on macOS 15.7.1.

Download **The-Magical-Rug-Mac-universal.dmg**, open it, and drag **The Magical Rug.app** to **Applications**. Open the app from there. No Codex or developer tools are needed.

- Universal binary: native Intel x86_64 and Apple Silicon arm64; macOS 14+.
- Shared Linux cloth solver, gradual outward corner folding, opaque underside, Metal depth testing.
- Direct middle dragging, resize, rotate, fold/flatten, saved pose, and display-change handling.
- **Control–Option–R** silently locks/unlocks; clicks pass through while locked.
- Menu bar controls and optional automatic startup through macOS Login Items.
- No Finder automation, Accessibility, or Screen Recording permission is required.

The app is ad-hoc signed, **not Developer ID signed or notarized**. If macOS blocks first launch, try opening it once, then use **System Settings → Privacy & Security → Open Anyway**. Do not disable Gatekeeper. Setup instructions are included in the disk image and the app's Help menu.

Validation: portable cloth/input tests, native Intel macOS compilation, Metal shader compilation, both binary architectures, bundle resources, and code-signature integrity. No manual physical-Mac desktop validation has been performed. Spaces, Stage Manager, and every external-display arrangement are not verified.

SHA-256 checksums are included in `SHA256SUMS.txt`.
