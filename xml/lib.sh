# SPDX-FileCopyrightText: 2026 Julien Bigot <julien@julien-bigot.fr>
# SPDX-License-Identifier: MIT
# What ../fetch-xml.sh and .github/workflows/xml.yml share, so that a laptop and CI generate the same
# bytes: source it (. xml/lib.sh). POSIX sh; needs Docker (with buildx) and git.

# image_digest IMAGE: the digest the tag of IMAGE points to now.
image_digest() {
  docker buildx imagetools inspect "$1" | awk '$1 == "Digest:" { print $2; exit }'
}

# resolve_commit REPO REF: the commit a tag or a branch of REPO points to. A tag's commit is the
# peeled line (^{}) when the tag is annotated.
resolve_commit() {
  git ls-remote "$1" "refs/heads/$2" "refs/tags/$2" "refs/tags/$2^{}" \
    | awk -v ref="$2" '{ sha[$2] = $1 }
        END { for (r in sha) if (r == "refs/tags/" ref "^{}") peeled = sha[r]
              print peeled ? peeled : sha["refs/tags/" ref] ? sha["refs/tags/" ref] : sha["refs/heads/" ref] }'
}

# generate_version PINNED SRC OUT NAME: generate-pdi-xml.sh's NAME/ into OUT, from the checkout SRC
# (with its submodules), in the image PINNED (IMAGE@DIGEST), xml_dir being the xml/ directory. generate-pdi-xml.sh says why OUT's
# files are the host user's, and why the build tree is a tmpfs.
generate_version() {
  docker run --rm --user root -v "$2":/work/src:ro -v "$3":/out -v "$xml_dir":/xml:ro \
    --tmpfs /work/build:exec "$1" sh /xml/generate-pdi-xml.sh "$4"
}
