#!/bin/sh
# SPDX-FileCopyrightText: 2026 Julien Bigot <julien@julien-bigot.fr>
# SPDX-License-Identifier: MIT
# Serve the site, with a local docsygen (local.sh).
#
# Usage: sh preview.sh [PORT]
# hugo server builds main and latest only (config/development/hugo.yaml): set HUGO_ENVIRONMENT to
# production to build every version. The port is 1313 by default, on 127.0.0.1.
set -eu

. "$(dirname "$0")/local.sh"
cd "$here"
exec hugo server --bind 127.0.0.1 --port "${1:-1313}" --renderToMemory --disableFastRender
