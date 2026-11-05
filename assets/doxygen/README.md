<!--
SPDX-FileCopyrightText: 2026 Julien Bigot <julien@julien-bigot.fr>
SPDX-License-Identifier: MIT
-->

# PDI's Doxygen XML

The site renders [PDI](https://github.com/pdidev/pdi)'s reference in the versions of
`../../xml/versions.txt` (`content/_content.gotmpl` places them). Their XML is not in git: the
`pdi*/` directories here are made by `../../fetch-xml.sh`, and git ignores them. Only this file is
tracked.

## How it is made

`fetch-xml.sh [NAME ...]`:

1. resolves the tag of `../../xml/image` (PDI's CI image, `ghcr.io/pdidev/spack/latest/clang/openmpi/all:v4`)
   to its current digest, once, and runs every version on that digest;
2. resolves the ref of each line of `xml/versions.txt` (`NAME REPO REF`: a tag or a branch) to a
   commit with `git ls-remote`, and checks it out with its submodules in a clone cached under
   `/var/tmp/pdi-docsygen/pdi` (or `PDI_SRC`);
3. runs `xml/generate-pdi-xml.sh NAME` in the image, with the checkout read-only at `/work/src`
   and this directory at `/out`.

The script configures `pdi/` of the checkout with CMake, in `/work/build`, with the documentation on
and everything else that can be off turned off, which writes the Doxyfile and the generated headers
that it lists as inputs, and exports the compilation database:

```sh
cmake -S pdi -B BUILD -DBUILD_DOCUMENTATION=ON -DBUILD_TESTING=OFF -DBUILD_FORTRAN=OFF \
  -DBUILD_BENCHMARKING=OFF -DBUILD_PYTHON=OFF -DCMAKE_EXPORT_COMPILE_COMMANDS=ON
```

Doxygen then runs with PDI's Doxyfile, from the directory that PDI's `doc` target runs it from, and
these settings on top: XML only, `XML_PROGRAMLISTING=NO` (PDI's HTML has no source listings),
`SHOW_USED_FILES=NO` and `VERBATIM_HEADERS=NO` (no "generated from the following file" footer, as in
PDI's HTML), the warnings off, and, when the image's `doxygen -V` reports clang support,
`CLANG_ASSISTED_PARSING=YES` with `CLANG_DATABASE_PATH` the build directory. The generation fails
when Doxygen's stderr has an `error:` line: libclang that doesn't find a header falls back silently
to Doxygen's own parser. Each XML file gets a `.license` file (REUSE).

The paths are fixed, so that two generations are identical, `Doxyfile.xml` included.

## The stamp

`NAME/.source` holds `COMMIT IMAGE_DIGEST SCRIPTS_SHA256`: the PDI commit the ref pointed to, the
image's digest, and a hash of the generation scripts (`xml/generate-pdi-xml.sh` and `xml/lib.sh`,
the docker run). A version is generated again when it differs: a new commit of `main`, a new digest of the image's tag `v4` (which regenerates every
version), or an edit of a script. CI keys its cache on the same three things
(`pdi-xml-NAME-COMMIT-DIGEST-SCRIPTS_HASH`, `.github/workflows/xml.yml`, whose hash of the scripts
is GitHub's `hashFiles`, not this one); it generates with the commands of `fetch-xml.sh`, which are
in `../../xml/lib.sh`.

## Notes on the old releases

- A release configured with `BUILD_FORTRAN=OFF` has no Fortran interface in its pages when its
  `pdif.h`, which zpp generates, is an input of the Doxyfile: Doxygen warns that the input is
  missing and skips it (1.0 to 1.7 do). 1.8 to 1.10 can't configure without Fortran, and are
  configured with `BUILD_FORTRAN=ON` (the script retries by itself), which gives their Fortran
  pages. The vendored zpp of 1.8 predates CMake 4: `CMAKE_POLICY_VERSION_MINIMUM=3.5`.
- Doxygen warns that `DOT_MULTI_TARGETS` is obsolete in all the Doxyfiles, and ignores it.
- With the tutorial submodule checked out, 1.0 to 1.4 and 1.9 to 1.12 have a Hands-on page; only the
  latest release's is rendered (`content/_content.gotmpl`), and `check.sh` expects the warnings of
  the other versions' examples, which link to it.
- The image's Doxygen is 1.17.0, which doesn't list `[[deprecated]]` entries in the deprecated list
  as 1.18 does: 1.8 to 1.10, whose only deprecated entry is such a one, have no such page.
