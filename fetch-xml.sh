#!/bin/sh
# SPDX-FileCopyrightText: 2026 Julien Bigot <julien@julien-bigot.fr>
# SPDX-License-Identifier: MIT
# Generate the Doxygen XML of PDI's versions (xml/versions.txt) into assets/doxygen/NAME/, in PDI's
# image (xml/image), whose tag is resolved to its current digest once: every version is generated
# on that digest. A version is generated again only when its stamp, assets/doxygen/NAME/.source,
# differs from "COMMIT IMAGE_DIGEST SCRIPT_SHA256": the PDI commit its ref points to now, the image
# digest, and the hash of xml/generate-pdi-xml.sh. assets/doxygen/README.md says more.
#
# Usage: sh fetch-xml.sh [NAME ...]    (default: every version of xml/versions.txt)
# XML_OUT replaces assets/doxygen as the output directory (for experiments).
# Needs Docker (with buildx) and git. The checkouts of PDI are made in a clone cached under
# /var/tmp/pdi-docsygen/pdi, or in PDI_SRC when it is set: a git repository, which is checked out
# and cleaned over. The commits are fetched from the REPO of xml/versions.txt, a commit at a time.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
script=$here/xml/generate-pdi-xml.sh
out=${XML_OUT:-$here/assets/doxygen}
src=${PDI_SRC:-/var/tmp/pdi-docsygen/pdi}

image=$(cat "$here/xml/image")
digest=$(docker buildx imagetools inspect "$image" | awk '$1 == "Digest:" { print $2; exit }')
[ -n "$digest" ] || { echo "fetch-xml.sh: cannot resolve the digest of $image" >&2; exit 1; }
pinned=${image%:*}@$digest
docker image inspect "$pinned" > /dev/null 2>&1 || docker pull -q "$pinned" > /dev/null
script_sha=$(sha256sum "$script" | cut -d ' ' -f 1)

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
  # A tag's commit is the peeled line (^{}) when the tag is annotated.
  commit=$(git ls-remote "$repo" "refs/heads/$ref" "refs/tags/$ref" "refs/tags/$ref^{}" \
    | awk -v ref="$ref" '{ sha[$2] = $1 }
        END { for (r in sha) if (r == "refs/tags/" ref "^{}") peeled = sha[r]
              print peeled ? peeled : sha["refs/tags/" ref] ? sha["refs/tags/" ref] : sha["refs/heads/" ref] }')
  [ -n "$commit" ] || { echo "fetch-xml.sh: $ref not found in $repo" >&2; status=1; continue; }
  stamp="$commit $digest $script_sha"
  if [ "$(cat "$out/$name/.source" 2> /dev/null)" = "$stamp" ]; then
    echo "fetch-xml.sh: $name is up to date ($ref at $commit)"
    continue
  fi
  echo "fetch-xml.sh: generating $name ($ref at $commit)"
  if ! { git -C "$src" cat-file -e "$commit^{commit}" 2> /dev/null \
           || git -C "$src" fetch -q --depth 1 "$repo" "$commit"; } \
     || ! git -C "$src" checkout -q -f --detach "$commit" \
     || ! git -C "$src" clean -q -ffdx \
     || ! git -C "$src" submodule update -q --init --recursive --force --depth 1; then
    echo "fetch-xml.sh: cannot check out $commit of $repo" >&2; status=1; continue
  fi
  rm -rf "${out:?}/$name"
  # generate-pdi-xml.sh says why OUT's files are the host user's, and why the build tree is a tmpfs.
  if docker run --rm --user root -v "$src":/work/src:ro -v "$out":/out -v "$here/xml":/xml:ro \
       --tmpfs /work/build:exec "$pinned" sh /xml/generate-pdi-xml.sh "$name"; then
    printf '%s\n' "$stamp" > "$out/$name/.source"
    # The tags are split so that reuse doesn't read them in this script.
    printf '%s\n%s\n' "SPDX-""FileCopyrightText: 2026 Julien Bigot <julien@julien-bigot.fr>" \
      "SPDX-""License-Identifier: MIT" > "$out/$name/.source.license"
  else
    echo "fetch-xml.sh: the generation of $name failed" >&2
    rm -rf "${out:?}/$name"; status=1
  fi
done < "$here/xml/versions.txt"
exit $status
