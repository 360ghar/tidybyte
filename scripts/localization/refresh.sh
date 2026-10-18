#!/usr/bin/env bash
#
# Regenerates both String Catalogs from the source of truth.
#
# Run after adding, changing, or removing a user-facing string, and after
# editing anything in `scripts/localization/translations/`.
#
#   ./scripts/localization/refresh.sh
#
# The pipeline, in order:
#
#   1. `xcstringstool sync` — Xcode's own extractor. It reads the `.stringsdata`
#      the compiler emitted, so it sees exactly the literals SwiftUI treats as
#      localizable keys, with the placeholder types the compiler inferred.
#      This is the authority for `Text`/`Label`/`Button` literals.
#   2. `extract.mjs` — our scanner. Covers what Xcode cannot see: the `L10n.*`
#      calls that build strings in code, plus the display properties
#      (`CleanupTool.name`, `PhotoCategory.title`, …) that return English text.
#   3. `build-catalog.mjs` — merges translations into the catalog, expands
#      plural variations, and pins reordered placeholders positionally.
#   4. `check.mjs` — fails on missing languages, placeholder mismatches, and
#      wrong plural categories.
#
# Steps 1 and 2 both write into the catalog, so the order matters: sync must run
# first, or the merge would drop the compiler-found keys.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

# A dedicated, repo-local DerivedData by default.
#
# Not `~/Library/Developer/Xcode/DerivedData`, because that directory is shared
# with Xcode's own builds and accumulates `Tidybyte-<hash>/Build/` trees from
# every checkout and configuration. This pipeline's output has to be a pure
# function of the source: the CI gate is `git diff --exit-code` on the catalog,
# so reading a `.stringsdata` left behind by some earlier build would make the
# gate depend on machine history. `build/` is gitignored.
DERIVED="${DERIVED_DATA_PATH:-$ROOT/build/LocalizationDerivedData}"
DESTINATION="${DESTINATION:-platform=iOS Simulator,name=iPhone 18 Pro}"

echo "==> Building to emit .stringsdata"
xcodebuild build \
  -project Tidybyte.xcodeproj \
  -scheme Tidybyte \
  -destination "$DESTINATION" \
  -derivedDataPath "$DERIVED" \
  -skipPackagePluginValidation \
  CODE_SIGNING_ALLOWED=NO \
  > /dev/null

echo "==> Syncing Xcode's extraction into the catalog"
# The widget shares the app's catalog, so both targets' .stringsdata merge into
# the same file. Passing them in one call is what keeps the widget's own keys
# (its display name, its intent titles) alongside the app's.
#
# The build and this lookup must agree on where DerivedData is. They did not:
# `-derivedDataPath` was missing above while `$DERIVED` was still used here, so
# setting DERIVED_DATA_PATH pointed the build at the default location and the
# lookup at the override. The lookup then read whatever `.stringsdata` happened
# to be lying there — stale output from an earlier build — and `sync` merged
# keys from source that no longer exists. A dead catalog key is invisible: it
# reports 100% coverage in 20 languages for a string nothing looks up.
#
# With `-derivedDataPath` given, Xcode places `Intermediates.noindex` directly
# under `$DERIVED/Build`; it only nests it inside a per-project `Tidybyte-<hash>`
# directory when using the shared default location. Accept either, but do not
# widen the search past `$DERIVED` — picking up a second tree is the bug above.
INTERMEDIATES=()
while IFS= read -r dir; do
  [ -n "$dir" ] && INTERMEDIATES+=("$dir")
done < <(find "$DERIVED" -maxdepth 3 -type d -name 'Intermediates.noindex' 2>/dev/null || true)

APP_DATA=""
WIDGET_DATA=""
if [ ${#INTERMEDIATES[@]} -gt 0 ]; then
  APP_DATA=$(find "${INTERMEDIATES[@]}" -name '*.stringsdata' -path '*Tidybyte.build*' 2>/dev/null || true)
  WIDGET_DATA=$(find "${INTERMEDIATES[@]}" -name '*.stringsdata' -path '*TidybyteWidget.build*' 2>/dev/null || true)
fi

if [ -z "$APP_DATA" ]; then
  echo "FAIL: no app .stringsdata under $DERIVED" >&2
  echo "      Xcode's keys would be missing from the catalog, so stop here" >&2
  echo "      rather than merge a partial one. Check the build output above." >&2
  exit 1
fi

# shellcheck disable=SC2086
xcrun xcstringstool sync Tidybyte/Resources/Localizable.xcstrings --stringsdata $APP_DATA $WIDGET_DATA > /dev/null

echo "==> Scanning for code-built strings"
node scripts/localization/extract.mjs | tail -3

echo "==> Collecting Xcode's key set"
node scripts/localization/collect-xcode-keys.mjs --derived "$DERIVED"

echo "==> Merging translations"
node scripts/localization/build-catalog.mjs

echo "==> Validating"
node scripts/localization/check.mjs

echo
echo "Catalogs refreshed."
