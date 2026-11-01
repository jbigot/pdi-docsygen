#!/bin/sh
# SPDX-FileCopyrightText: 2026 Julien Bigot <julien@julien-bigot.fr>
# SPDX-License-Identifier: MIT
# Build the site with a local docsygen (local.sh): hugo, with the arguments of this script.
#
# Usage: sh build.sh [HUGO_ARG ...]
set -eu

. "$(dirname "$0")/local.sh"
cd "$here"
exec hugo "$@"
