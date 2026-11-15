<p align="center">
  <img src="docs/banner.png" alt="Widgee: desktop widgets for macOS 26+" width="100%">
</p>

# Widgee

Desktop widgets for macOS, written in JavaScript and rendered natively with SwiftUI. Widgee is a menu bar app that places widgets on your desktop. It shows a Dock icon only while its window is open.

Source code and releases: <https://github.com/aloesc/Widgee>. Bug reports and ideas: [Issues](https://github.com/aloesc/Widgee/issues).

> Status: early development (0.x). The API and widget format may change between minor versions.

## Screenshots

![Widgets on the desktop](docs/screenshots/desktop.png)

| Gallery | Create a widget with an AI agent |
| --- | --- |
| ![Gallery](docs/screenshots/gallery.png) | ![Create Widget](docs/screenshots/create-widget.png) |

## Requirements

- macOS 26 or later (Apple silicon or Intel).

## Install

1. Download `Widgee-<version>.dmg` from the Releases page. A `SHA256SUMS.txt` is attached to each release; check it with `shasum -a 256 -c SHA256SUMS.txt`.
2. Open the DMG and drag **Widgee.app** to **Applications**.

### First launch without a signature

Widgee is signed ad-hoc and is **not notarized** (no Apple Developer ID), so Gatekeeper blocks the first launch. Use one of:

- Right-click (or Control-click) `Widgee.app` in Applications, choose **Open**, then confirm **Open**.
- Try to open the app once, then go to **System Settings → Privacy & Security**, scroll to the message about Widgee and click **Open Anyway**.
- Or remove the quarantine attribute in Terminal:

  ```sh
  xattr -cr /Applications/Widgee.app
  ```

You only need to do this once per downloaded version.

## Widgets

Built-in widgets: clock, system monitor and weather (Open-Meteo, no API key; pick a city by search or use your current location).

**Create a widget with an AI agent:** open *Create Widget…* from the menu bar icon, describe the widget you want, copy the generated prompt and paste it into your AI agent (Claude Code, Cursor, …). The prompt already contains the widgets folder path, the manifest format and the SDK reference. When the agent finishes, the widget shows up in the gallery automatically.

User widgets live in:

```
~/Library/Application Support/Widgee/Widgets/
```

Each widget is a folder:

```
my-widget/
  manifest.json
  widget.js
```

### Creating a widget

- `manifest.json` describes the widget: `id` (kebab-case), `name`, `version` (SemVer), `author`, `sdk`, `sizes`, `permissions`, `settings`. See `App/Resources/BuiltinWidgets/clock/manifest.json` for an example.
- `widget.js` is an ES module that imports from `"widgee"` and default-exports `defineWidget({...})`.
- Data comes from declarative **sources**: `system(...)` (metrics), `timer(...)` and `http(...)`. The host polls them and re-renders the widget; until the first value arrives, `ctx.data[key]` is `null`, and metrics can be `null` too, so handle that.

```js
import { defineWidget, VStack, Text, system } from "widgee";

export default defineWidget({
  sources: { cpu: system("cpu", { interval: 2 }) },
  render(ctx) {
    const cpu = ctx.data.cpu;
    return VStack({ padding: 14 },
      Text({ text: cpu ? Math.round(cpu.total) + "%" : "—", size: 24 }));
  },
});
```

The snippet is illustrative (the `cpu` metric must also be listed in `permissions.system`); see the references below for exact types.

References:

- Type definitions: [`sdk/index.d.ts`](sdk/index.d.ts)
- Component reference: [`Packages/WidgeeKit/Sources/Renderer/COMPONENTS.md`](Packages/WidgeeKit/Sources/Renderer/COMPONENTS.md)

### Permissions

Widgets run in a JavaScriptCore sandbox with no file, network or shell access. Anything else must be declared in `manifest.json`:

- `permissions.system`: list of system metrics the widget may read.
- `permissions.network`: allowlist of domains for `http` sources (HTTPS only; the host performs the request, not the JS).

Calls outside the declared permissions are rejected and logged. Request the minimum you need. Installing a third-party widget runs its code: only use widgets you trust.

## Building from source

Requirements: Xcode 26+, [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
git clone https://github.com/aloesc/Widgee.git
cd Widgee
brew install xcodegen
xcodegen generate
open Widgee.xcodeproj          # or: xcodebuild -project Widgee.xcodeproj -scheme Widgee build

cd Packages/WidgeeKit && swift test
```

Build a DMG (output in `dist/`, universal arm64 + x86_64, ad-hoc signed):

```sh
brew install create-dmg   # optional; falls back to hdiutil without a window layout
scripts/build-dmg.sh
```

Note: ES module loading uses private JavaScriptCore APIs. They work outside the App Store but may change in a future macOS; CI runs the module loading tests on every push.

## Planned

Widget catalog, auto-update and support for macOS 14+ are not available yet.

## Support

Widgee is free and open source. If you find it useful, you can support the development: [donatty.com/aloescc](https://donatty.com/aloescc).

## Versioning

[SemVer](https://semver.org). Releases are tagged `vX.Y.Z`, matching `MARKETING_VERSION` in `project.yml`.

## License

[GPL-3.0](LICENSE).
