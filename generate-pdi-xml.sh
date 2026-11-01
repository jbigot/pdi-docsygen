#!/bin/sh
# SPDX-FileCopyrightText: 2026 Julien Bigot <julien@julien-bigot.fr>
# SPDX-License-Identifier: MIT
# Regenerate assets/doxygen/NAME/ from a tag of a PDI checkout, with the Doxygen configuration
# PDI uses for its own documentation: the Doxyfile that PDI's CMake build configures (Doxyfile,
# or Doxyfile.doxygen_doc for releases that use doxygen_add_docs), found under the build tree's
# docs/. Only XML is generated, without source listings, since PDI's HTML documentation has none
# (SOURCE_BROWSER = NO). assets/doxygen/README.md says how each directory was made.
#
# Usage: sh generate-pdi-xml.sh PDI_SOURCE_DIR TAG NAME
#   TAG   the tag (or commit) of PDI to render, checked out in a temporary git worktree
#   NAME  the directory under assets/doxygen/ (pdi for main, pdi-1.12, …)
# DOXYGEN selects the Doxygen binary (default: Doxygen 1.18.0, as docsygen's tests download it).
set -eu

site=$(cd "$(dirname "$0")" && pwd)
pdi_source=$1
tag=$2
name=$3
doxygen=${DOXYGEN:-/var/tmp/docsygen-matrix/doxygen-1.18.0/doxygen-1.18.0/bin/doxygen}
out=$site/assets/doxygen

work=$(mktemp -d /var/tmp/pdi-xml.XXXXXX)
trap 'git -C "$pdi_source" worktree remove --force "$work/src" 2> /dev/null || true; rm -rf "$work"' EXIT
git -C "$pdi_source" worktree add -q -d "$work/src" "$tag"
cd "$work/src"
# PDI's CMake project is the pdi/ directory of the release; the documentation on, the rest off.
# Releases that need zpp for the documentation (the Fortran interface's header) can't configure
# without Fortran: those are configured again with it, which gives their Fortran pages too. The
# vendored zpp of 1.8 predates CMake 4, hence the policy minimum.
configure() {
  cmake -S pdi -B "$work/build" -DBUILD_DOCUMENTATION=ON -DBUILD_TESTING=OFF -DBUILD_FORTRAN="$1" \
    -DBUILD_BENCHMARKING=OFF -DBUILD_PYTHON=OFF -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
    > "$work/cmake.log" 2>&1
}
if ! configure OFF; then
  rm -rf "$work/build"
  configure ON || { cat "$work/cmake.log" >&2; exit 1; }
  echo "generate-pdi-xml.sh: $tag needed BUILD_FORTRAN=ON to configure" >&2
fi
doxyfile=$(find "$work/build" -name 'Doxyfile*' -path '*docs*' | head -n 1)
[ -n "$doxyfile" ] || { echo "generate-pdi-xml.sh: no Doxyfile in the build tree of $tag" >&2; exit 1; }

rm -rf "${out:?}/$name"
mkdir -p "$out"
# PDI's doc target runs doxygen from the documentation's source directory, or from the source root.
if grep -q 'WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"' "$work/src/pdi/docs/CMakeLists.txt"; then
  cd "$work/src/pdi/docs"
else
  cd "$work/src"
fi
{
  cat "$doxyfile"
  printf '%s\n' GENERATE_HTML=NO GENERATE_XML=YES "OUTPUT_DIRECTORY=$out" "XML_OUTPUT=$name" \
    XML_PROGRAMLISTING=NO QUIET=YES WARNINGS=NO WARN_IF_UNDOCUMENTED=NO WARN_IF_INCOMPLETE_DOC=NO \
    WARN_IF_DOC_ERROR=NO
} | "$doxygen" -

# Doxygen's output carries no license: give each file the one it has in the repository (REUSE), in
# a .license file next to it. PDI's XML and images are PDI's (BSD-3-Clause); the schemas and the
# stylesheet are Doxygen's, and xml.xsd the W3C's.
for file in "$out/$name"/*; do
  case ${file##*/} in
    *.license) continue ;;
    xml.xsd) holder='2001 W3C (MIT, ERCIM, Keio, Beihang)'; spdx=W3C-20150513 ;;
    combine.xslt|*.xsd) holder='1997-2026 Dimitri van Heesch'; spdx=GPL-2.0-or-later ;;
    *) holder="2015-2026 Commissariat a l'energie atomique et aux energies alternatives (CEA)"
       spdx=BSD-3-Clause ;;
  esac
  # The tags are split so that reuse doesn't read them in this script.
  printf '%s\n%s\n' "SPDX-""FileCopyrightText: $holder" "SPDX-""License-Identifier: $spdx" \
    > "$file.license"
done
