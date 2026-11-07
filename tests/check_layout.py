# SPDX-FileCopyrightText: 2026 Julien Bigot <julien@julien-bigot.fr>
# SPDX-License-Identifier: MIT
"""Check the example site in PDI's organization (check.sh).

Usage: python3 -I check_layout.py PUBLIC EXPECTED.json [--development]
EXPECTED.json is {"pages": {URL: TITLE}, "links": [[URL, HREF]], "menu": {URL: MENU},
"development": {"links": …, "menu": …}}; with --development, its development part is checked.
Each check:
  - each page exists, and its <title> is TITLE, before Docsy's " | <site title>";
  - each page's main content links HREF (tests/check.py checks that every link resolves);
  - each page's version menu is MENU, as tests/site/check_versions.py reads it.
Exit 1 on any failure.
"""
import json, os, re, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
if 'DOCSYGEN_TOOLS' in os.environ: sys.path.insert(0, os.environ['DOCSYGEN_TOOLS'])
import htmltree
from check_versions import menu


def main(argv):
    development = '--development' in argv
    argv = [a for a in argv if a != '--development']
    public, expected = argv
    with open(expected) as f:
        want = json.load(f)
    if development:
        want = want['development']
    errors = []
    texts = {}
    links = list(want.get('links', []))

    def page(url):
        if url not in texts:
            path = os.path.join(public, url.strip('/'), 'index.html')
            texts[url] = open(path, encoding='utf-8').read() if os.path.isfile(path) else None
        return texts[url]

    for url, title in want.get('pages', {}).items():
        text = page(url)
        m = re.search(r'<title>([^<]*?)(?: \| [^<]*)?</title>', text or '')
        if text is None:
            errors.append(f'{url}: no page')
        elif not m or m.group(1) != title:
            errors.append(f'{url}: titled {m.group(1) if m else None!r}, not {title!r}')
    for url, href in links:
        text = page(url)
        main = re.search(r'<main\b.*</main>', text or '', re.S)
        if text is None:
            errors.append(f'{url}: no page')
        elif not main or f'href="{href}"' not in main.group(0):
            errors.append(f'{url}: no link to {href}')
    for url, entries in want.get('menu', {}).items():
        text = page(url)
        got = menu(htmltree.parse(text)) if text is not None else None
        if got != entries:
            errors.append(f'{url}: menu {got}, not {entries}')
    for e in errors:
        print(e)
    print(f'check_layout.py: {len(want.get("pages", {}))} pages, {len(links)} links, '
          f'{len(want.get("menu", {}))} menus, {len(errors)} errors')
    return 1 if errors else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
