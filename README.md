# TidyByte

[![CI](https://github.com/360ghar/tidybyte/actions/workflows/ci.yml/badge.svg)](https://github.com/360ghar/tidybyte/actions/workflows/ci.yml)
[![Mac app](https://github.com/360ghar/tidybyte/actions/workflows/macos.yml/badge.svg)](https://github.com/360ghar/tidybyte/actions/workflows/macos.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

TidyByte finds space you can reclaim and removes it only after you approve.
Everything runs on your device. This repository holds every part of it.

| Folder | Product | Built with | Get it |
|---|---|---|---|
| [`ios/`](ios/) | TidyByte for iPhone and iPad. Swipe through the photo library to keep or delete, and clean duplicates, screenshots, and large videos. | Swift, SwiftUI, iOS 17+ | [App Store](https://apps.apple.com/in/app/tidybyte/id6775769763) |
| [`macos/`](macos/) | Tidybyte for Mac. Caches, developer files, large and old files, duplicates, and apps with their leftovers. Files go to the Trash, and History can restore them. | Swift 6, SwiftPM, macOS 26+ | [Download the DMG](https://github.com/360ghar/tidybyte/releases/download/mac-v1.0.0/Tidybyte-1.0.0.dmg) |
| [`website/`](website/) | The marketing site, in 21 languages. | Astro, Tailwind | [tidybyte.360ghar.com](https://tidybyte.360ghar.com) |

Each folder builds on its own. Run its commands from inside it:

```bash
(cd ios && xcodegen generate && npm ci)      # then see ios/README.md
(cd macos && swift build && swift test)      # see macos/README.md
(cd website && npm ci && npm run dev)        # http://localhost:4321
```

Releases: iOS tags are `v*` (for example `v1.1.3`), and Mac tags are `mac-v*`
(for example `mac-v1.0.0`).

## Contributing

Contributions are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) for setup, the
CI checks, and how to send a pull request.

- New here? Start with a
  [`good first issue`](https://github.com/360ghar/tidybyte/labels/good%20first%20issue).
- Questions and ideas go to
  [Discussions](https://github.com/360ghar/tidybyte/discussions).
- Found a bug? Use the
  [bug report form](https://github.com/360ghar/tidybyte/issues/new/choose).
- Security problems: follow [SECURITY.md](SECURITY.md).

This project follows a [Code of Conduct](CODE_OF_CONDUCT.md).

## Support the project

TidyByte is free, with no ads, accounts, or subscriptions. If it saves you
space, you can support its development:

- [Sponsor on GitHub](https://github.com/sponsors/saksham1991999)
- Star the repository
- Rate the app on the [App Store](https://apps.apple.com/in/app/tidybyte/id6775769763)

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file
for details.
