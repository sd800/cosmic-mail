#!/usr/bin/env python3
"""Regenerate the HTML standard's named character references using Python's standard library."""
from html.entities import html5
from pathlib import Path


def swift(text):
    return '"' + ''.join(
        '\\u{%x}' % ord(c) if ord(c) < 32 or ord(c) > 126
        else '\\' + c if c in '\\"' else c for c in text
    ) + '"'


target = Path(__file__).resolve().parent.parent / 'Sources/MailCore/HTMLEntities.swift'
names = {name[:-1]: text for name, text in html5.items() if name.endswith(';')}
target.write_text(
    '// Named character references defined by the HTML standard. Values are decoded once, then escaped.\n'
    'enum HTMLEntities {\n  static let named: [String: String] = [\n'
    + ''.join('    ' + swift(name) + ': ' + swift(text) + ',\n' for name, text in sorted(names.items()))
    + '  ]\n}\n'
)
