# SPDX-FileCopyrightText: 2026 Julien Bigot <julien@julien-bigot.fr>
# SPDX-License-Identifier: MIT
# Sourced by the other scripts, to build with a local docsygen: it exports
# HUGO_MODULE_REPLACEMENTS, which replaces github.com/jbigot/docsygen by the checkout named by
# DOCSYGEN_SRC (default: docsygen/ next to this repository), and the other modules by their copy
# in Go's module cache (Hugo wants every module of the graph replaced once one is). Without
# DOCSYGEN_SRC and its checkout, nothing is replaced: the build then needs a released docsygen.
#
# It sets here, the directory of this repository, and PATH to find the npm-installed hugo.
here=$(cd "$(dirname "$0")" && pwd)
export PATH="$here/node_modules/.bin:$PATH"
docsygen=${DOCSYGEN_SRC:-$(dirname "$here")/docsygen}
if [ -d "$docsygen" ]; then
  # modcache MODULE: the directory of the module's version in Go's module cache, as go.mod says.
  modcache() {
    version=$(sed -n "s#^[[:space:]]*$1 \\(v[^ ]*\\).*#\\1#p" "$here/go.mod" | head -n 1)
    (cd "$here" && go mod download -json "$1@$version") | sed -n 's/^[[:space:]]*"Dir": "\(.*\)",$/\1/p'
  }
  HUGO_MODULE_REPLACEMENTS="github.com/jbigot/docsygen -> $docsygen"
  HUGO_MODULE_REPLACEMENTS="$HUGO_MODULE_REPLACEMENTS,github.com/docsy/docsy/theme -> $(modcache github.com/docsy/docsy/theme)"
  HUGO_MODULE_REPLACEMENTS="$HUGO_MODULE_REPLACEMENTS,github.com/jbigot/hugo-xml-document -> $(modcache github.com/jbigot/hugo-xml-document)"
  export HUGO_MODULE_REPLACEMENTS
fi
