### Why

<!-- The problem, and how to see it. Link the issue if there is one: "Fixes #123". -->

### What changes

<!-- The approach, in a few points. -->

### Tests

<!-- What you ran, and on which device or simulator. Give numbers for performance work. -->

### Screenshots

<!-- Before and after, for UI changes. Delete this section if there are none. -->

### Checklist

- [ ] New user-facing text goes through a String Catalog, and the CI localization checks pass.
- [ ] No new third-party dependency, network call, or analytics.
- [ ] iOS: layout changes checked on iPad, or on iPhone Duo if the change touches window size.
- [ ] Mac: `swift test` and `swiftlint lint --strict --baseline .swiftlint-baseline.json` pass in `macos/`.
- [ ] Tests added or updated for logic changes.
