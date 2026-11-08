#!/bin/sh
# SPDX-FileCopyrightText: 2026 Julien Bigot <julien@julien-bigot.fr>
# SPDX-License-Identifier: MIT
# Build the site and check it.
#
# Usage: sh check.sh
# The build fails on any WARN or ERROR (--printPathWarnings included). Then docsygen's
# tools/check.py (from the checkout local.sh uses) without its role checks, since each placement
# holds part of a tree, its tools/check_redirects.py on each section's latest release, and
# tests/check_layout.py
# with layout-expected.json: the titles of some pages, some links and version menus. The build
# warns that the main pages of the versions whose XML has the tutorial's and the example's pages
# link to them as text: the tutorial and its example come from main only, whose own warnings are
# not tolerated.
# No page has Doxygen's footer or source links. A second build must be identical: the adapter files
# run in no fixed order. A development build (config/development: main and latest) must pass
# check_layout.py --development.
# HUGO selects the Hugo binary (default: the npm-installed one). It needs docsygen: see local.sh.
set -eu

. "$(dirname "$0")/local.sh"
# docsygen's checks of a built site, and the htmltree.py that tests/check_*.py import.
DOCSYGEN_TOOLS=$docsygen/tools
[ -f "$DOCSYGEN_TOOLS/check.py" ] || { echo "check.sh: $DOCSYGEN_TOOLS/check.py is missing: set DOCSYGEN_SRC to a docsygen checkout" >&2; exit 1; }
export DOCSYGEN_TOOLS
hugo=${HUGO:-hugo}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
# Not --quiet: it would hide the ERROR line that errorf logs.
if ! "$hugo" --source "$here" --baseURL / --printPathWarnings --destination "$tmp/public" > "$tmp/log" 2>&1; then
  cat "$tmp/log" >&2; exit 1
fi
status=0
latest=$(sed -n 's/.*"version" "\([^"]*\)" "latest" true.*/\1/p' "$here/content/_content.gotmpl")
[ -n "$latest" ] || { echo "check.sh: no latest version in content/_content.gotmpl" >&2; exit 1; }
# The version that places the tutorial and its example (content/_content.gotmpl): only the other
# versions are expected to warn that their main page links to them as text.
tutorial_version=$(sed -n 's/.*"version" "\([^"]*\)" "tutorial" true.*/\1/p' "$here/content/_content.gotmpl")
[ -n "$tutorial_version" ] || { echo "check.sh: no tutorial version in content/_content.gotmpl" >&2; exit 1; }
tutorial='docsygen: /docs/[^ /]* links to (Hands_on|PDI_example), which no page of version [^ ]* holds: rendered as text'
# unexpected LOG: its WARN and ERROR lines, but for the tutorial's of the versions without it.
unexpected() {
  grep -E 'WARN|ERROR' "$1" | awk -v re="$tutorial" -v mine="$tutorial_version" \
    '!($0 ~ re && index($0, "version " mine " holds") == 0)' || true
}
# The filter must keep the warnings of the version that places the tutorial (a self-check).
for page in Hands_on PDI_example; do
  printf 'WARN  docsygen: /docs/%s links to %s, which no page of version %s holds: rendered as text\n' \
    "$tutorial_version" "$page" "$tutorial_version"
done > "$tmp/tutorial-warning"
if [ "$(unexpected "$tmp/tutorial-warning" | wc -l)" -ne 2 ]; then
  echo "check.sh: the tolerated tutorial warnings cover the version that places it ($tutorial_version)" >&2; exit 1
fi
unexpected "$tmp/log" > "$tmp/unexpected"
if [ -s "$tmp/unexpected" ]; then cat "$tmp/unexpected" >&2; status=1; fi
python3 -I "$DOCSYGEN_TOOLS/check.py" "$tmp/public" - - || status=1
# Every page of the latest release has a redirect at its numbered path, in each versioned section.
for section in docs plugins plugin-dev; do
  python3 -I "$DOCSYGEN_TOOLS/check_redirects.py" "$tmp/public" "/$section/latest/" "/$section/$latest/" || status=1
done
# Chroma's classes (markup.highlight.noClasses: false) need their rules in the CSS: Docsy's
# `@import 'td/code-dark'` gives them, in light and dark mode. A few dozen at least, one per token.
rules=$(find "$tmp/public" -name '*.css' -exec grep -oh '\.chroma [^{]*{' {} + | wc -l)
if [ "$rules" -lt 20 ]; then
  echo "check.sh: the CSS has $rules .chroma rules: add @import 'td/code-dark'; to assets/scss/_styles_project.scss" >&2
  status=1
fi
# Neither the "generated from the following file" footer nor Doxygen's source links (SHOW_USED_FILES,
# VERBATIM_HEADERS and SOURCE_BROWSER are NO): PDI's own documentation has none.
if grep -rlE --include='*.html' 'was generated from the following file|Definition at line|Definition in file' "$tmp/public" > "$tmp/footers"; then
  echo "check.sh: $(wc -l < "$tmp/footers") pages with a footer or a source link, among them:" >&2
  head -n 5 "$tmp/footers" | sed "s#^$tmp/public##" >&2
  status=1
fi
python3 -I "$here/tests/check_layout.py" "$tmp/public" "$here/layout-expected.json" || status=1
if ! "$hugo" --source "$here" --baseURL / --destination "$tmp/again" > "$tmp/again.log" 2>&1; then
  cat "$tmp/again.log" >&2; exit 1
fi
if ! diff -r "$tmp/public" "$tmp/again" > "$tmp/again.diff"; then
  head -n 20 "$tmp/again.diff" >&2; echo "check.sh: two builds differ" >&2; status=1
fi
if ! "$hugo" --source "$here" --baseURL / --environment development --destination "$tmp/dev" > "$tmp/dev.log" 2>&1; then
  cat "$tmp/dev.log" >&2; exit 1
fi
unexpected "$tmp/dev.log" > "$tmp/unexpected"
if [ -s "$tmp/unexpected" ]; then cat "$tmp/unexpected" >&2; status=1; fi
python3 -I "$here/tests/check_layout.py" "$tmp/dev" "$here/layout-expected.json" --development || status=1
[ $status -eq 0 ] && echo "check.sh: OK"
exit $status
