#!/bin/sh
# SPDX-FileCopyrightText: 2026 Julien Bigot <julien@julien-bigot.fr>
# SPDX-License-Identifier: MIT
# Time the build of the site with N copies of PDI's reference, as N versions.
#
# Usage: sh bench.sh N [HUGO_ARG ...]
# The site is built as it is, but for its configuration: PDI's XML is copied N times, to
# assets/doxygen/pdi-1 … pdi-N, and one adapter generates the versions v1 … vN at /docs/vK/, but
# vN, the latest, at /docs/latest/ with redirects from /docs/vN/. Each copy ends with its own
# comment: Hugo shares the resources of identical files, which
# would build one version's XML only. Prints the wall time of hugo alone, the page count and the
# size of public/; with HUGO_ARGs (--templateMetrics …), also hugo's output.
# HUGO selects the Hugo binary (default: the npm-installed one). local.sh says how to build with a
# local docsygen.
set -eu

n=${1:?usage: bench.sh N [HUGO_ARG ...]}
shift
. "$(dirname "$0")/local.sh"
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
mkdir -p "$out/content/docs"
cat > "$out/content/docs/_content.gotmpl" <<GOTMPL
{{- range \$k := seq $n -}}
  {{- partial "docsygen/adapter.html" (dict "store" \$ "dir" (printf "doxygen/pdi-%d" \$k) "version" (printf "v%d" \$k)
      "path" ":version" "latest" (eq \$k $n)) -}}
{{- end -}}
GOTMPL
{
  printf 'module:\n  mounts:\n'
  # Not docs/_index.md either: it redirects to a version that bench.sh doesn't build, as the
  # other sections do.
  printf '    - {source: content, target: content, files: ["! _content.gotmpl", "! docs/_index.md", "! plugins/**", "! plugin-dev/**", "! tutorial/**"]}\n'
  printf '    - {source: "%s", target: content}\n' "$out/content"
  printf '    - {source: assets, target: assets, files: ["! doxygen/**"]}\n'
  k=1
  while [ "$k" -le "$n" ]; do
    mkdir -p "$out/xml/pdi-$k"
    cp "$here"/assets/doxygen/pdi/* "$out/xml/pdi-$k/"
    for f in "$out/xml/pdi-$k"/*.xml; do printf '<!-- bench.sh copy %d -->\n' "$k" >> "$f"; done
    printf '    - {source: "%s", target: assets/doxygen/pdi-%d}\n' "$out/xml/pdi-$k" "$k"
    k=$((k + 1))
  done
  for dir in static layouts data i18n archetypes; do printf '    - {source: %s, target: %s}\n' "$dir" "$dir"; done
  printf 'menu:\n  main:\n    - {name: Documentation, pageRef: /docs/, weight: 10}\n'
} > "$out/bench.yaml"
hugo=${HUGO:-hugo}
start=$(date +%s.%N)
# Not --quiet: it would hide the ERROR line that errorf logs.
if ! "$hugo" --source "$here" --config "$here/hugo.yaml,$out/bench.yaml" --destination "$out/public" "$@" > "$out/log" 2>&1; then
  cat "$out/log" >&2; exit 1
fi
end=$(date +%s.%N)
if [ $# -gt 0 ]; then cat "$out/log"; fi
pages=$(sed -n 's/^ *Pages *│ *\([0-9]*\).*/\1/p' "$out/log")
printf 'bench.sh: %d copies: %.1f s, %s pages, %s\n' "$n" "$(echo "$end - $start" | bc)" "$pages" "$(du -sh "$out/public" | cut -f1)"
