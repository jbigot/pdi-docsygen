<!--
SPDX-FileCopyrightText: 2026 Julien Bigot <julien@julien-bigot.fr>
SPDX-License-Identifier: MIT
-->

# pdi-docsygen

A draft of [PDI](https://pdi.dev)'s website, built with [docsygen](https://github.com/jbigot/docsygen)
and [Docsy](https://www.docsy.dev/): PDI's reference, generated from Doxygen's XML, in the latest
patch release of every minor release since 1.0 (1.0.1, 1.1.0, 1.2.2, 1.3.1, 1.4.3, 1.5.5, 1.6.0,
1.7.1, 1.8.3, 1.9.3, 1.10.1, 1.11.2, 1.12.0) and `main`, in four sections with their own sidebars:

- the user documentation at `/docs/<version>/` (the guide's pages and the C API);
- the plugins at `/plugins/<version>/`;
- the plugin developer documentation at `/plugin-dev/<version>/` (how to create a plugin, the
  plugin API);
- the tutorial at `/tutorial/<version>/`, from the latest release only.

Each section redirects to its latest version, and the home and community pages come from PDI's
[new-site](https://github.com/pdidev/new-site). It is published at
<https://jbigot.github.io/pdi-docsygen/>.

## Build

Hugo and Dart Sass come from npm, which must be 11.18 or later (an older npm installs the wrong
`sass`): run `npx npm@11 install` once. Hugo needs Go for its modules.

The reference's XML is not in git: run `sh fetch-xml.sh` first, which needs Docker and git (see
[The XML](#the-xml)).

docsygen has no release yet: build with a local checkout, which `local.sh` points
`HUGO_MODULE_REPLACEMENTS` at (`DOCSYGEN_SRC`, by default `docsygen/` next to this repository). Hugo
wants every module of the graph replaced once one is, so `local.sh` replaces Docsy and
hugo-xml-document too, by their copy in Go's module cache.

```sh
sh build.sh              # hugo, with the local docsygen
sh preview.sh [PORT]     # hugo server, with main and the latest release only
sh check.sh              # build and check: links, titles, version menus (layout-expected.json)
sh bench.sh N            # time the build of N copies of the reference
```

`check.sh` runs docsygen's `tools/check.py` from the checkout that `local.sh` uses, and
`tests/check_*.py` import its `tools/htmltree.py` (`DOCSYGEN_TOOLS`, which `check.sh` sets).
`tests/check_versions.py` is a copy of docsygen's `tests/docsy/` one, but for where it finds
`htmltree.py`: update it from there.

## The XML

`sh fetch-xml.sh [NAME ...]` generates the Doxygen XML of each version of `xml/versions.txt` into
`assets/doxygen/` (git-ignored), in PDI's own CI image (`xml/image`), and only when the PDI commit,
the image or a generation script (`xml/generate-pdi-xml.sh`, `xml/lib.sh`) changed since the last time. It needs Docker and git. It checks PDI out in its own cache clone; `PDI_SRC` may name a PDI checkout of
your own to fetch commits from, which is never modified, and `PDI_MAIN_REF` a ref of that checkout,
such as a branch not pushed yet, to generate main from. `assets/doxygen/README.md` says how.

CI does the same (`.github/workflows/xml.yml`, called once by `website.yml`, whose checks and build
wait for it). A first job resolves the image's tag to its digest and each version's ref to a commit;
then one job per version, in parallel, restores that version's XML from the Actions cache or
generates it with the same commands as `fetch-xml.sh` (`xml/lib.sh`), and uploads it as an
artifact named after the version, which the site's job downloads into `assets/doxygen/`. The cache
key is `pdi-xml-NAME-COMMIT-DIGEST-SCRIPTS_HASH`: the PDI commit, the image digest and a hash of
the generation scripts (`xml/generate-pdi-xml.sh`, `xml/lib.sh`). A version that fails to generate fails the run: the site is never built
without it.

Nothing runs on a schedule or on PDI's pushes while the site is a prototype: a rebuild comes from a
push, a pull request or a manual run. What the XML then depends on is re-resolved each time: a push
to a branch that `xml/versions.txt` follows (`main`'s), or an edit of a generation script, regenerates the
versions concerned; and since the image's `v4` tag is not pinned, its next digest (the image is
rebuilt weekly) regenerates every version, 14 generations at once, at the first run after it.

## License

MIT, but for PDI's XML, images and site assets (BSD-3-Clause), and the schemas and stylesheet that
Doxygen copies into its XML output (GPL-2.0-or-later, `xml.xsd`: W3C-20150513). The repository
follows the [REUSE specification](https://reuse.software/spec/).
