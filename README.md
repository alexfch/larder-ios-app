# Larder

<!-- One or two sentences: what the app does and who it's for. -->

## Design

Prototypes are designed in Claude Design and tracked in [`docs/design/`](docs/design/README.md),
including exported snapshots and links to live interactive versions.

## Product

The PRD lives at [docs/Larder_PRD_v2.0.md](docs/Larder_PRD_v2.0.md).

## Development

Native SwiftUI + SwiftData, iOS 17+. The Xcode project is generated from
[`project.yml`](project.yml) via [XcodeGen](https://github.com/yonaskolb/XcodeGen) rather than
committed directly, so it never goes stale relative to the file layout:

```bash
brew install xcodegen   # once
xcodegen generate       # after pulling, or after adding/removing files
open Larder.xcodeproj
```
