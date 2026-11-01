// SPDX-FileCopyrightText: 2026 Julien Bigot <julien@julien-bigot.fr>
// SPDX-License-Identifier: MIT
module github.com/jbigot/pdi-docsygen

go 1.12

require (
	github.com/docsy/docsy/theme v0.18.0 // indirect
	github.com/jbigot/docsygen v0.0.0 // indirect
	github.com/jbigot/hugo-xml-document v0.0.1 // indirect
)

// docsygen has no release yet: until it has, build with local.sh, which points
// HUGO_MODULE_REPLACEMENTS at a checkout (see README.md).
