# SPDX-FileCopyrightText: 2026 Julien Bigot <julien@julien-bigot.fr>
# SPDX-License-Identifier: MIT
"""Check the output of the Docsy-flavor test site.

Usage: python3 -I check.py PUBLIC XMLDIR ROOT_URL [--links PAGE EXPECTED.json] [--under DIR]
  PUBLIC    the built site
  XMLDIR    the Doxygen XML of one version root
  ROOT_URL  that version root's URL (/ref/), where its paths.json is published
  --under DIR  report only the errors of the pages below DIR (docs/api/), for a site that has
  pages of its own
  XMLDIR and ROOT_URL are both - for a site whose placements hold parts of a tree: the checks of
  the roles are left out.
Checks:
  - every compound with a role (paths.json), and every memberdef and enumvalue id with a target,
    appears exactly once as data-doxygen-id in the pages under ROOT_URL;
  - every internal href resolves to a file, and its fragment to an id in that file, but the
    links the documentation's authors wrote (class docsygen-ulink), left as they are;
  - no id appears twice in a file;
  - no `name` attribute on an <a>, nor an id of Doxygen's anchors (a<N>_…, r_…), which nothing
    links to;
  - no <p> holds a block element;
  - no class but docsygen-*, Docsy's alert classes, mermaid and the Bootstrap classes docsygen uses
    (badge, d-block, figure, figure-caption, fw-bold, mb-0, mb-2, small, text-bg-secondary,
    text-body-secondary, text-*-emphasis),
    outside KaTeX's output (.katex*), the highlighted code (div.highlight) and the language-* class of
    code that Chroma has no lexer for,
    on the pages of the test site (those that Docsy didn't lay out: without .td-content, nor a
    td-* class on <body>, as Docsy's home and community pages have; Docsy's classes are its
    business);
  - no {{<, {{%, HAHAHUGOSHORTCODE, ZgotmplZ or heading with its {#id} as text (what a docsygen
    shortcode called as {{< >}} leaves) is left;
  - PUBLIC has a page, and with --under, DIR has one;
  - with --links, the hrefs of PAGE's main element (a path under PUBLIC) are, in order, the list
    of EXPECTED.json.
Docsy's print pages (_print/), which repeat every page of a section, are link targets only.
Exit 1 on any failure.
"""
import collections, glob, json, os, re, sys, urllib.parse
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import htmltree

BLOCKS = {'div', 'table', 'ul', 'ol', 'dl', 'pre', 'p', 'blockquote', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'hr'}
LEFTOVERS = ('{{<', '{{%', 'HAHAHUGOSHORTCODE', 'ZgotmplZ')
# A heading that Markdown didn't read: a shortcode called as {{< >}} returns the Markdown it holds as text.
HEADING_LEFT = re.compile(r'#{1,6} [^\n<]*\{#[\w:.-]+\}')
ALLOWED = re.compile(r'^(docsygen-.*|alert|alert-.*|h4|mermaid|katex.*|language-.*|badge|d-block|figure|figure-caption|fw-bold|mb-0|mb-2|small|td-max-width-on-larger-screens|text-bg-secondary|text-body-secondary|text-(primary|secondary|success|danger|warning|info|dark)-emphasis)$')


def foreign_classes(node, out):
    """The classes of node and its descendants that ALLOWED rejects, as {class: count}, skipping
    KaTeX's output and the highlighted code (div.highlight)."""
    for c in node.children:
        if not isinstance(c, htmltree.Node):
            continue
        cls = htmltree.classes(c)
        if any(x.startswith('katex') for x in cls) or (c.tag == 'div' and 'highlight' in cls):
            continue
        for x in cls:
            if not ALLOWED.match(x):
                out[x] += 1
        foreign_classes(c, out)


def walk(node):
    for c in node.children:
        if isinstance(c, htmltree.Node):
            yield c
            yield from walk(c)


def main(argv):
    links = None
    if '--links' in argv:
        i = argv.index('--links')
        links, argv = argv[i + 1:i + 3], argv[:i] + argv[i + 3:]
    under = None
    if '--under' in argv:
        i = argv.index('--under')
        under, argv = argv[i + 1].strip('/') + '/', argv[:i] + argv[i + 2:]
    public, xmldir, root_url = argv
    paths = {'pages': {}, 'targets': {}}
    if root_url != '-':
        with open(os.path.join(public, root_url.strip('/'), 'paths.json')) as f:
            paths = json.load(f)
    member_ids = set()
    for name in glob.glob(os.path.join(xmldir, '*.xml')) if xmldir != '-' else []:
        with open(name, encoding='utf-8') as f:
            member_ids.update(re.findall(r'<(?:memberdef|enumvalue)\b[^>]*\bid="([^"]+)"', f.read()))
    expected = {r['id'] for p in paths['pages'].values() for r in p['roles'] if r.get('role') == 'compound'}
    expected |= {i for i in paths.get('targets', {}) if i in member_ids}
    errors = []
    marks = collections.Counter()
    ids = {}
    trees = {}
    for path in sorted(glob.glob(os.path.join(public, '**', '*.html'), recursive=True)):
        with open(path, encoding='utf-8') as f:
            text = f.read()
        rel = os.path.relpath(path, public)
        printed = rel.split(os.sep)[0] == '_print'
        in_root = root_url != '-' and ('/' + rel.replace(os.sep, '/')).startswith(root_url)
        # {{% is what a page shows of a shortcode call it documents, in code (Hugo can't escape it).
        prose = re.sub(r'<(pre|code)\b.*?</\1>', '', text, flags=re.S)
        for s in LEFTOVERS:
            if s in (prose if s == '{{%' else text):
                errors.append(f'{rel}: {s} left')
        if HEADING_LEFT.search(text):
            errors.append(f'{rel}: a heading with its {{#id}} left as text')
        tree = htmltree.parse(text)
        trees[rel] = tree
        seen = collections.Counter()
        if printed:
            ids[rel] = {n.attrs['id'] for n in walk(tree) if 'id' in n.attrs}
            continue
        for n in walk(tree):
            if 'id' in n.attrs:
                seen[n.attrs['id']] += 1
            if n.tag == 'a' and 'name' in n.attrs:
                errors.append(f'{rel}: <a name={n.attrs["name"]!r}>')
            if re.match(r'^(a\d+_|r_)', n.attrs.get('id', '')):
                errors.append(f'{rel}: id {n.attrs["id"]!r} is a Doxygen anchor')
            if 'data-doxygen-id' in n.attrs and in_root:
                marks[n.attrs['data-doxygen-id']] += 1
            if n.tag == 'p':
                inner = next((d.tag for d in walk(n) if d.tag in BLOCKS), None)
                if inner:
                    errors.append(f'{rel}: a <p> holds a <{inner}>')
        ids[rel] = set(seen)
        docsy = htmltree.find(tree, '.td-content') or any(
            c.startswith('td-') for b in htmltree.find(tree, 'body') for c in htmltree.classes(b))
        for main in ([] if docsy else htmltree.find(tree, 'main')):
            foreign = collections.Counter()
            foreign_classes(main, foreign)
            errors += [f'{rel}: class {x!r} appears {k} times' for x, k in sorted(foreign.items())]
        errors += [f'{rel}: id {i!r} appears {k} times' for i, k in sorted(seen.items()) if k > 1]
    for i in sorted(expected):
        if marks[i] != 1:
            errors.append(f'data-doxygen-id {i!r} appears {marks[i]} times')
    for i, k in sorted(marks.items()):
        if k > 1 and i not in expected:
            errors.append(f'data-doxygen-id {i!r} appears {k} times')
    for rel, tree in sorted(trees.items()):
        base = '/' + rel.replace(os.sep, '/')
        for n in walk(tree):
            href = n.attrs.get('href') if n.tag == 'a' else None
            # docsygen-ulink: a link its author wrote, which docsygen leaves as is.
            if not href or htmltree.EXTERNAL.match(href) or href.startswith('javascript:') or 'docsygen-ulink' in htmltree.classes(n):
                continue
            url = urllib.parse.urljoin(base, href)
            target, _, fragment = url.partition('#')
            target = urllib.parse.unquote(target).lstrip('/')
            if target.endswith('/') or target == '':
                target += 'index.html'
            if target not in ids and os.path.isfile(os.path.join(public, target)):
                continue  # not a page: a Markdown version, an image, a script
            if target not in ids:
                errors.append(f'{rel}: {href} leads to no file')
            elif fragment and urllib.parse.unquote(fragment) not in ids[target]:
                errors.append(f'{rel}: {href} leads to no id in {target}')
    if links:
        page, want_file = links
        with open(want_file) as f:
            want = json.load(f)
        got = [n.attrs.get('href') for m in htmltree.find(trees[page], 'main') for n in walk(m) if n.tag == 'a' and 'href' in n.attrs]
        if got != want:
            errors.append(f'{page}: links {got} instead of {want}')
    if not trees:
        errors.append(f'{public}: no page')
    elif under and not any(rel.replace(os.sep, '/').startswith(under) for rel in trees):
        errors.append(f'{under}: no page')
    if under:
        # Errors on pages outside the subtree are the site's own: only what docsygen made counts.
        errors = [e for e in errors if e.split(': ', 1)[0].replace(os.sep, '/').startswith(under)
                  or not e.split(': ', 1)[0].endswith('.html')]
    for e in errors:
        print(e)
    print(f'check.py: {len(trees)} files, {len(expected)} ids, {len(errors)} errors')
    return 1 if errors else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
