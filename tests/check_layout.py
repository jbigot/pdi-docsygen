# SPDX-FileCopyrightText: 2026 Julien Bigot <julien@julien-bigot.fr>
# SPDX-License-Identifier: MIT
"""Check the example site in PDI's organization (check.sh).

Usage: python3 -I check_layout.py PUBLIC EXPECTED.json [--doxygen VERSION] [--development]
EXPECTED.json is {"pages": {URL: TITLE}, "links": [[URL, HREF]], "links-doxygen-1.18": [[URL, HREF]],
"menu": {URL: MENU}, "development": {"links": …, "menu": …}}; with --development, its development
part is checked. "links-doxygen-1.18" are the links that only Doxygen 1.18 and later gives (1.17
doesn't mark [[deprecated]] declarations): VERSION is the Doxygen that generated the XML, and below
1.18 a line names the known regression instead of checking them, so that the check turns strict
by itself with an image that has 1.18. Each check:
  - each page exists, and its <title> is TITLE, before Docsy's " | <site title>";
  - each page's main content links HREF (tests/check.py checks that every link resolves);
  - each page's version menu is MENU, as tests/site/check_versions.py reads it.
Exit 1 on any failure.
"""
import json, os, re, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import htmltree
from check_versions import menu


def version_tuple(v):
    return tuple(int(n) for n in re.findall(r'\d+', v)[:3])


def main(argv):
    development = '--development' in argv
    argv = [a for a in argv if a != '--development']
    doxygen = None
    if '--doxygen' in argv:
        i = argv.index('--doxygen')
        doxygen = argv[i + 1]
        del argv[i:i + 2]
    public, expected = argv
    with open(expected) as f:
        want = json.load(f)
    if development:
        want = want['development']
    errors = []
    texts = {}
    links = list(want.get('links', []))
    since_1_18 = want.get('links-doxygen-1.18', [])
    if since_1_18 and not development:
        if doxygen is None:
            errors.append('--doxygen VERSION is needed: the expectations have links of Doxygen 1.18')
        elif version_tuple(doxygen) >= (1, 18):
            links += since_1_18
        else:
            print(f'check_layout.py: Doxygen {doxygen} generated the XML: {len(since_1_18)} link(s) '
                  f'not checked, known regression of Doxygen < 1.18, which does not mark [[deprecated]] '
                  f'declarations (PDI::Datatype_template_ptr is not in the deprecated list); '
                  f'an image with Doxygen 1.18 restores it and makes the check strict')

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
