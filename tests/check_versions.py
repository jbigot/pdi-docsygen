# SPDX-FileCopyrightText: 2026 Julien Bigot <julien@julien-bigot.fr>
# SPDX-License-Identifier: MIT
"""Check the version menu and the canonical link of pages of a Docsy site with several versions.

Usage: python3 -I check_versions.py PUBLIC EXPECTED.json
  PUBLIC         the built site
  EXPECTED.json  [{page, menu, canonical, notice}]: page a URL path (/docs/1.7/), menu the
                 entries of its version menu (Docsy's .td-version-menu) in order, as [label,
                 href], the active one marked with a third item, "active"; canonical the href of
                 its <link rel="canonical">, or null for none; notice its docsygen notice
                 (.docsygen-notice) as [older or main, the href of its link], or null for none
Exit 1 on any difference.
"""
import json, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import htmltree


def menu(tree):
    out = []
    for m in htmltree.find(tree, '.td-version-menu'):
        for a in htmltree.find(m, 'a.dropdown-item'):
            entry = [htmltree.text(a), a.attrs.get('href')]
            if 'active' in htmltree.classes(a) and a.attrs.get('aria-current') == 'page':
                entry.append('active')
            out.append(entry)
    return out


def canonical(tree):
    links = [n.attrs.get('href') for n in htmltree.find(tree, 'link[rel=canonical]')]
    return links


def notices(tree):
    out = []
    for n in htmltree.find(tree, '.docsygen-notice'):
        kind = 'older' if 'an older release' in htmltree.text(n) else 'main' if 'development version' in htmltree.text(n) else '?'
        out.append([kind] + [a.attrs.get('href') for a in htmltree.find(n, 'a')])
    return out


def main(argv):
    public, expected = argv
    with open(expected) as f:
        entries = json.load(f)
    errors = []
    for e in entries:
        path = os.path.join(public, e['page'].strip('/'), 'index.html')
        if not os.path.exists(path):
            errors.append(f'{e["page"]}: no such page')
            continue
        with open(path, encoding='utf-8') as f:
            tree = htmltree.parse(f.read())
        got = menu(tree)
        if got != e['menu']:
            errors.append(f'{e["page"]}: menu {got}, not {e["menu"]}')
        want = [] if e['canonical'] is None else [e['canonical']]
        got = canonical(tree)
        if got != want:
            errors.append(f'{e["page"]}: canonical {got}, not {want}')
        want = [] if e['notice'] is None else [e['notice']]
        got = notices(tree)
        if got != want:
            errors.append(f'{e["page"]}: notice {got}, not {want}')
    for x in errors:
        print(x)
    print(f'check_versions.py: {len(entries)} pages, {len(errors)} errors')
    return 1 if errors else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
