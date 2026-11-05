#!/bin/sh
# SPDX-FileCopyrightText: 2026 Julien Bigot <julien@julien-bigot.fr>
# SPDX-License-Identifier: MIT
# Build the site and check it.
#
# Usage: sh check.sh
# The build fails on any WARN or ERROR (--printPathWarnings included). Then tests/check.py
# without its role checks, since each placement holds part of a tree, and tests/check_layout.py
# with layout-expected.json: the titles of some pages, some links and version menus. The build
# warns that the examples of the versions whose XML has the tutorial's page (PDI's tutorial
# submodule is checked out) link to it as text: the tutorial comes from the latest release only.
# No page has Doxygen's footer or source links. A second build must be identical: the adapter files
# run in no fixed order. A development build (config/development: main and latest) must pass
# check_layout.py --development.
# HUGO selects the Hugo binary (default: the npm-installed one). It needs docsygen: see local.sh.
set -eu

. "$(dirname "$0")/local.sh"
hugo=${HUGO:-hugo}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
# Not --quiet: it would hide the ERROR line that errorf logs.
if ! "$hugo" --source "$here" --baseURL / --printPathWarnings --destination "$tmp/public" > "$tmp/log" 2>&1; then
  cat "$tmp/log" >&2; exit 1
fi
status=0
tutorial='docsygen: /docs/[^ ]*/pdi_example links to Hands_on, which no page of version [^ ]* holds: rendered as text'
if grep -E 'WARN|ERROR' "$tmp/log" | grep -vE "$tutorial" >&2; then status=1; fi
python3 -I "$here/tests/check.py" "$tmp/public" - - || status=1
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
if grep -E 'WARN|ERROR' "$tmp/dev.log" | grep -vE "$tutorial" >&2; then status=1; fi
python3 -I "$here/tests/check_layout.py" "$tmp/dev" "$here/layout-expected.json" --development || status=1
[ $status -eq 0 ] && echo "check.sh: OK"
exit $status
