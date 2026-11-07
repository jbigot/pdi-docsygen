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
# warns that the examples and main pages of the versions whose XML has the tutorial's page (PDI's
# tutorial submodule is checked out) link to it as text: the tutorial comes from the latest
# release only, whose own warning is not tolerated.
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
# The latest release must place the tutorial (content/_content.gotmpl): only the other versions
# are expected to warn that their example and their main page link to it as text.
latest=$(sed -n 's/.*"version" "\([^"]*\)" "latest" true.*/\1/p' "$here/content/_content.gotmpl")
[ -n "$latest" ] || { echo "check.sh: no latest version in content/_content.gotmpl" >&2; exit 1; }
tutorial='docsygen: /docs/[^ /]*(/pdi_example)? links to Hands_on, which no page of version [^ ]* holds: rendered as text'
# unexpected LOG: its WARN and ERROR lines, but for the tutorial's of the versions but the latest.
unexpected() {
  grep -E 'WARN|ERROR' "$1" | awk -v re="$tutorial" -v latest="$latest" \
    '!($0 ~ re && index($0, "version " latest " holds") == 0)' || true
}
# The filter must keep the tutorial's warning of the latest release (a self-check).
printf 'WARN  docsygen: /docs/%s/pdi_example links to Hands_on, which no page of version %s holds: rendered as text\n' \
  "$latest" "$latest" > "$tmp/latest-warning"
if [ -z "$(unexpected "$tmp/latest-warning")" ]; then
  echo "check.sh: the tolerated tutorial warning covers the latest release ($latest)" >&2; exit 1
fi
unexpected "$tmp/log" > "$tmp/unexpected"
if [ -s "$tmp/unexpected" ]; then cat "$tmp/unexpected" >&2; status=1; fi
python3 -I "$DOCSYGEN_TOOLS/check.py" "$tmp/public" - - || status=1
# Every page of the latest release has a redirect at its numbered path, in each section.
for section in docs plugins plugin-dev tutorial; do
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
