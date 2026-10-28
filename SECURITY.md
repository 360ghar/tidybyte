# Security policy

## Supported versions

Only the current release gets security fixes: the App Store release of
TidyByte for iPhone and iPad, and the latest `mac-v*` release of Tidybyte for
Mac on [GitHub Releases](https://github.com/360ghar/tidybyte/releases). The
current version shows in the app under **Settings**.

## Report a vulnerability

Do not report a security problem in a public issue, discussion, or pull request.

Use one of these private channels:

- **GitHub:** [Report a vulnerability](https://github.com/360ghar/tidybyte/security/advisories/new)
  (private vulnerability reporting).
- **Email:** [saksham1991999@gmail.com](mailto:saksham1991999@gmail.com).

Include:

- What the problem is and what an attacker can do with it.
- The steps or code to reproduce it.
- The app version, the iOS or macOS version, and the device.

You get a reply within 7 days. After the fix ships, the report
can be made public, and you are credited unless you ask not to be.

## Scope

TidyByte has no backend and no accounts. All processing happens on the
device. The iOS app has no network features. The Mac app contacts the network
only to check for updates and, if you turn it on, to reach the AI provider you
configure. The areas most likely to matter are:

- How the apps read, change, delete, and export photos, videos, and files.
- Data in the shared App Group container that the iOS widget reads.
- Temporary files written during compression and export.
- The SwiftData store that records swipe and cleanup history.
- The Mac app's protected-path rules, Trash and clone operations, and History
  restore.
- The Mac app's MCP server (`tidybyte-mcp`) and its update feed.

Problems in iOS or macOS itself, or in Apple frameworks are out of scope. Report those to
[Apple](https://security.apple.com).
