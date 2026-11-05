#!/bin/sh
# SPDX-FileCopyrightText: 2026 Julien Bigot <julien@julien-bigot.fr>
# SPDX-License-Identifier: MIT
# Generate the Doxygen XML of PDI's versions (xml/versions.txt) into assets/doxygen/NAME/, in PDI's
# image (xml/image), whose tag is resolved to its current digest once: every version is generated
# on that digest. A version is generated again only when its stamp, assets/doxygen/NAME/.source,
# differs from "COMMIT IMAGE_DIGEST SCRIPTS_SHA256": the PDI commit its ref points to now, the image
# digest, and the hash of the generation scripts, xml/generate-pdi-xml.sh and xml/lib.sh (the docker
# run that shapes the output). assets/doxygen/README.md says more.
#
# Usage: sh fetch-xml.sh [NAME ...]    (default: every version of xml/versions.txt)
# XML_OUT replaces assets/doxygen as the output directory (for experiments).
# Needs Docker (with buildx) and git. The checkouts of PDI are made in a clone cached under
# /var/tmp/pdi-docsygen/pdi (PDI_CACHE), which is checked out and cleaned over. PDI_SRC may name a repository of
# one's own (a PDI checkout): it is only a place to fetch a commit from when it has it, instead of
# the network, and is never modified, nor is its working tree read: uncommitted work is safe. The
# other commits are fetched from the REPO of xml/versions.txt, a commit at a time.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
xml_dir=$here/xml
script=$xml_dir/generate-pdi-xml.sh
. "$xml_dir/lib.sh"
out=${XML_OUT:-$here/assets/doxygen}
src=${PDI_CACHE:-/var/tmp/pdi-docsygen/pdi}

image=$(cat "$xml_dir/image")
digest=$(image_digest "$image")
[ -n "$digest" ] || { echo "fetch-xml.sh: cannot resolve the digest of $image" >&2; exit 1; }
pinned=${image%:*}@$digest
docker image inspect "$pinned" > /dev/null 2>&1 || docker pull -q "$pinned" > /dev/null
scripts_sha=$(cat "$script" "$xml_dir/lib.sh" | sha256sum | cut -d ' ' -f 1)

if [ ! -d "$src/.git" ] && [ ! -f "$src/.git" ]; then
  mkdir -p "$src"
  git init -q "$src"
fi

mkdir -p "$out"
status=0
while read -r name repo ref; do
  case $name in '' | '#'*) continue ;; esac
  if [ $# -gt 0 ]; then
    case " $* " in *" $name "*) ;; *) continue ;; esac
  fi
  commit=$(resolve_commit "$repo" "$ref")
  [ -n "$commit" ] || { echo "fetch-xml.sh: $ref not found in $repo" >&2; status=1; continue; }
  stamp="$commit $digest $scripts_sha"
  if [ "$(cat "$out/$name/.source" 2> /dev/null)" = "$stamp" ]; then
    echo "fetch-xml.sh: $name is up to date ($ref at $commit)"
    continue
  fi
  echo "fetch-xml.sh: generating $name ($ref at $commit)"
  if ! { git -C "$src" cat-file -e "$commit^{commit}" 2> /dev/null \
           || { [ -n "${PDI_SRC:-}" ] \
                && git -C "$PDI_SRC" cat-file -e "$commit^{commit}" 2> /dev/null \
                && git -C "$src" fetch -q "$PDI_SRC" "$commit"; } \
           || git -C "$src" fetch -q --depth 1 "$repo" "$commit"; } \
     || ! git -C "$src" checkout -q -f --detach "$commit" \
     || ! git -C "$src" clean -q -ffdx \
     || ! git -C "$src" submodule update -q --init --recursive --force --depth 1; then
    echo "fetch-xml.sh: cannot check out $commit of $repo" >&2; status=1; continue
  fi
  rm -rf "${out:?}/$name"
  if generate_version "$pinned" "$src" "$out" "$name"; then
    printf '%s\n' "$stamp" > "$out/$name/.source"
    # The tags are split so that reuse doesn't read them in this script.
    printf '%s\n%s\n' "SPDX-""FileCopyrightText: 2026 Julien Bigot <julien@julien-bigot.fr>" \
      "SPDX-""License-Identifier: MIT" > "$out/$name/.source.license"
  else
    echo "fetch-xml.sh: the generation of $name failed" >&2
    rm -rf "${out:?}/$name"; status=1
  fi
done < "$xml_dir/versions.txt"
exit $status
