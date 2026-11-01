# SPDX-FileCopyrightText: 2026 Julien Bigot <julien@julien-bigot.fr>
# SPDX-License-Identifier: MIT
"""HTML trees and CSS-like selectors, for the checks of tests/site.

A tree is a Node('#document'), with Node elements and str text as children (parse()).
A SELECTOR is TAG, TAG.CLASS, TAG#ID, .CLASS or #ID, each optionally followed by [ATTR],
[ATTR=VALUE] or [ATTR^=PREFIX] and by :contains(TEXT) (jQuery's), or those alone; a space selects
descendants and ~ later siblings, as in CSS.
"""
import html.parser, re

VOID = {'area', 'base', 'br', 'col', 'embed', 'hr', 'img', 'input', 'link', 'meta', 'param',
        'source', 'track', 'wbr'}
BLOCK = {'div', 'p', 'table', 'tr', 'td', 'th', 'ul', 'ol', 'li', 'dl', 'dt', 'dd',
         'h1', 'h2', 'h3', 'h4', 'h5', 'h6', '#document'}
SPACE = re.compile('[ \t\n\r\f]+')
EXTERNAL = re.compile(r'^(?:[A-Za-z][A-Za-z0-9+.-]*:|//)')


class Node:
    def __init__(self, tag, attrs, parent=None):
        self.tag, self.attrs, self.children, self.parent = tag, attrs, [], parent

    def __repr__(self):
        return f'<{self.tag} {self.attrs}>'


class _Builder(html.parser.HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.root = Node('#document', {})
        self.stack = [self.root]

    def _append(self, node):
        node.parent = self.stack[-1]
        self.stack[-1].children.append(node)

    def handle_starttag(self, tag, attrs):
        node = Node(tag, {k: v or '' for k, v in attrs})
        self._append(node)
        if tag not in VOID:
            self.stack.append(node)

    def handle_startendtag(self, tag, attrs):
        self._append(Node(tag, {k: v or '' for k, v in attrs}))

    def handle_endtag(self, tag):
        for i in range(len(self.stack) - 1, 0, -1):
            if self.stack[i].tag == tag:
                del self.stack[i:]
                return

    def handle_data(self, data):
        siblings = self.stack[-1].children
        if siblings and isinstance(siblings[-1], str):
            siblings[-1] += data
        else:
            siblings.append(data)


def parse(text):
    """The document tree of an HTML string; comments, declarations and PIs are dropped."""
    builder = _Builder()
    builder.feed(text)
    builder.close()
    return builder.root


def classes(node):
    return node.attrs.get('class', '').split()


def _simple(node, selector):
    """Whether node matches TAG, TAG.CLASS[.CLASS…], TAG#ID, .CLASS or #ID, each optionally
    followed by [ATTR], [ATTR=VALUE] or [ATTR^=PREFIX] and by :contains(TEXT), or those alone."""
    m = re.fullmatch(r'([a-z0-9]*)((?:\.[^.#\[:]+)*)(?:#([^\[:]+))?(?:\[([a-z-]+)(?:(\^?=)([^\]]*))?\])?'
                     r'(?::contains\((.*)\))?', selector)
    if not m or not selector:
        raise ValueError(f'unsupported selector {selector!r}')
    tag, cls, ident, attr, op, value, contained = m.groups()
    if attr is not None:
        actual = node.attrs.get(attr)
        if actual is None or (op is not None and not (actual.startswith(value) if op == '^=' else actual == value)):
            return False
    if contained is not None and contained not in text(node):
        return False
    return ((not tag or node.tag == tag) and all(c in classes(node) for c in cls.split('.')[1:])
            and (ident is None or node.attrs.get('id') == ident))


def _steps(selector):
    """selector as [(combinator, simple selector)], the first combinator None: ' ' or '~',
    outside brackets and parentheses."""
    steps, simple, combinator, depth = [], '', None, 0
    for c in selector.strip() + ' ':
        if c in '[(':
            depth += 1
        elif c in '])':
            depth -= 1
        if depth or c not in ' ~':
            simple += c
            continue
        if simple:
            steps.append((combinator, simple))
            simple, combinator = '', ' '
        if c == '~':
            combinator = '~'
    return steps or [(None, '')]


def _matches(node, steps):
    combinator, simple = steps[-1]
    if not _simple(node, simple):
        return False
    if len(steps) == 1:
        return True
    if combinator == '~':
        siblings = [c for c in node.parent.children if isinstance(c, Node)] if node.parent else []
        return any(_matches(s, steps[:-1]) for s in siblings[:siblings.index(node)])
    n = node.parent
    while n is not None:
        if _matches(n, steps[:-1]):
            return True
        n = n.parent
    return False


def matches(node, selector):
    """Whether node matches selector: simple selectors (see _simple) separated by a space, for
    a descendant, or by ~, for a later sibling, as in CSS."""
    return _matches(node, _steps(selector))


def find(node, selector):
    """Every descendant of node that matches selector, in document order."""
    out = []
    for c in node.children:
        if isinstance(c, Node):
            if matches(c, selector):
                out.append(c)
            out.extend(find(c, selector))
    return out


def text(node):
    """The text content of node, with whitespace runs collapsed."""
    def walk(n):
        return ''.join(c if isinstance(c, str) else walk(c) for c in n.children)
    return SPACE.sub(' ', walk(node)).strip()
