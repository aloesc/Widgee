# Contributing

Thanks for your interest in Widgee. Issues and pull requests are welcome.

## Setup

- Repository: <https://github.com/aloesc/Widgee> (`git clone https://github.com/aloesc/Widgee.git`).
- macOS 26+, Xcode 26+, [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).
- `xcodegen generate` creates `Widgee.xcodeproj` from `project.yml`. Edit `project.yml`, not the generated project.

## Before opening a PR

- Run the core tests: `cd Packages/WidgeeKit && swift test`.
- Make sure the app builds: `xcodegen generate && xcodebuild -project Widgee.xcodeproj -scheme Widgee build`.
- Keep changes focused; add or update tests for behavior changes.
- Widget format changes must be reflected in `sdk/index.d.ts` and `Packages/WidgeeKit/Sources/Renderer/COMPONENTS.md`.

## Conventions

- Swift 6, strict concurrency.
- Versions follow [SemVer](https://semver.org). Releases are cut from tags `vX.Y.Z` that must match `MARKETING_VERSION` in `project.yml`.
- By contributing you agree that your work is licensed under GPL-3.0.
