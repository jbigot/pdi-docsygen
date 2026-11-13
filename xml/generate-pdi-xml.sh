#!/bin/sh
# SPDX-FileCopyrightText: 2026 Julien Bigot <julien@julien-bigot.fr>
# SPDX-License-Identifier: MIT
# Generate the Doxygen XML of one version of PDI, inside PDI's CI image (xml/image), with the
# Doxygen configuration PDI uses for its own documentation: the Doxyfile that PDI's CMake build
# configures, found under the build tree's docs/. Only XML is generated, without source listings,
# since PDI's HTML documentation has none (SOURCE_BROWSER = NO). ../fetch-xml.sh runs it, and
# assets/doxygen/README.md says how.
#
# Usage, from the repository root (SRC: a PDI checkout with its submodules, OUT: the directory that
# receives NAME/, IMAGE: the content of xml/image):
#   docker run --rm --user root -v SRC:/work/src:ro -v OUT:/out -v "$PWD/xml":/xml:ro \
#     --tmpfs /work/build:exec IMAGE sh /xml/generate-pdi-xml.sh NAME
#   NAME  the directory under OUT (pdi for main, pdi-1.12, …)
# The image's entrypoint (/bin/bash_run) loads the Spack modules, then runs this script. The
# container runs as root, the one user that can write a bind mount whatever the Docker setup (the
# image's own user, ci, is a subordinate uid under rootless Docker, and can't write the host user's
# /out). Under rootless Docker root's files are the host user's already; under a rootful Docker the
# script gives NAME/ to the owner of /out on the way out, so that the host user can read it, update
# it and remove it. The paths are fixed (/work/src, /work/build, /out) so that two runs write the
# same Doxyfile.xml.
set -eu

name=${1:?usage: generate-pdi-xml.sh NAME}
src=/work/src
build=/work/build
out=/out
# Whatever the outcome, NAME/ goes to the owner of /out (see above).
trap 'chown -R "$(stat -c %u:%g "$out")" "$out/$name" 2> /dev/null || true' EXIT

# The documentation on, the rest of PDI's CMake project (the pdi/ directory) off. Releases that
# need zpp for the documentation (the Fortran interface's header) can't configure without Fortran:
# those are configured again with it, which gives their Fortran pages too. The vendored zpp of 1.8
# predates CMake 4, hence the policy minimum.
configure() {
  cmake -S "$src/pdi" -B "$build" -DBUILD_DOCUMENTATION=ON -DBUILD_TESTING=OFF \
    -DBUILD_FORTRAN="$1" -DBUILD_BENCHMARKING=OFF -DBUILD_PYTHON=OFF \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
    > "$build/cmake.log" 2>&1
}
if ! configure OFF; then
  find "$build" -mindepth 1 -delete
  configure ON || { cat "$build/cmake.log" >&2; exit 1; }
  echo "generate-pdi-xml.sh: $name needed BUILD_FORTRAN=ON to configure" >&2
fi
doxyfile=$(find "$build" -name Doxyfile -path '*docs*' | head -n 1)
[ -n "$doxyfile" ] || { echo "generate-pdi-xml.sh: no Doxyfile in the build tree of $name" >&2; exit 1; }

rm -rf "${out:?}/$name"
# PDI's doc target runs doxygen from the documentation's source directory, or from the source root.
if grep -q 'WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"' "$src/pdi/docs/CMakeLists.txt"; then
  cd "$src/pdi/docs"
else
  cd "$src"
fi
# Doxygen's errors don't change its exit status: an `error:` line on stderr fails the generation,
# and WARN_LOGFILE is emptied so that nothing is diverted from stderr. No clang-assisted parsing,
# even when the image's Doxygen has libclang: Doxygen only uses it to link identifiers in source
# listings, which this XML leaves out, so it changes no byte of the XML and is about ten times slower.
{
  cat "$doxyfile"
  printf '%s\n' GENERATE_HTML=NO GENERATE_XML=YES "OUTPUT_DIRECTORY=$out" "XML_OUTPUT=$name" \
    XML_PROGRAMLISTING=NO QUIET=YES WARNINGS=NO WARN_IF_UNDOCUMENTED=NO WARN_IF_INCOMPLETE_DOC=NO \
    WARN_IF_DOC_ERROR=NO SHOW_USED_FILES=NO VERBATIM_HEADERS=NO WARN_LOGFILE= WARN_AS_ERROR=NO \
    CLANG_ASSISTED_PARSING=NO
} | doxygen - 2> "$build/doxygen.log" || { cat "$build/doxygen.log" >&2; exit 1; }
cat "$build/doxygen.log" >&2
if grep -E 'error:' "$build/doxygen.log" >&2; then
  echo "generate-pdi-xml.sh: Doxygen reported errors for $name" >&2
  exit 1
fi

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
