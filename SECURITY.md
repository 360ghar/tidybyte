# Security policy

## Supported versions

Only the current App Store release of TidyByte gets security fixes. The
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
- The app version, iOS version, and device.

You get a reply within 7 days. After the fix ships on the App Store, the report
can be made public, and you are credited unless you ask not to be.

## Scope

TidyByte has no backend, no accounts, and no network features. All processing
happens on the device. The areas most likely to matter are:

- How the app reads, changes, deletes, and exports photos and videos.
- Data in the shared App Group container that the widget reads.
- Temporary files written during compression and export.
- The SwiftData store that records swipe and cleanup history.

Problems in iOS itself or in Apple frameworks are out of scope. Report those to
[Apple](https://security.apple.com).
