"""Static website integrity checks. Run from the repository root."""
from html.parser import HTMLParser
from pathlib import Path
import re
import hashlib
import json
import unittest
from urllib.parse import urlsplit, unquote
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
WEB = ROOT / 'web'

class Page(HTMLParser):
    def __init__(self, text):
        super().__init__(convert_charrefs=True)
        self.tags = []
        self.feed(text)

    def handle_starttag(self, tag, attrs):
        self.tags.append((tag, dict(attrs)))

class WebsiteTests(unittest.TestCase):
    def setUp(self):
        self.source = (WEB / 'index.html').read_text()
        self.page = Page(self.source)
        self.ids = [attrs['id'] for _, attrs in self.page.tags if 'id' in attrs]

    def test_local_assets_and_anchors(self):
        self.assertEqual(len(self.ids), len(set(self.ids)), 'Duplicate element IDs')
        for tag, attrs in self.page.tags:
            for key in ['href', 'src', 'aria-controls', 'aria-labelledby']:
                if key not in attrs: continue
                value = attrs[key]
                if key.startswith('aria-'):
                    for target in value.split(): self.assertIn(target, self.ids)
                    continue
                url = urlsplit(value)
                if url.scheme:
                    self.assertEqual(url.scheme, 'https')
                    self.assertNotIn(tag, ['script', 'img'], 'Runtime assets must be local')
                elif url.fragment and not url.path:
                    self.assertIn(unquote(url.fragment), self.ids)
                else:
                    self.assertFalse(value.startswith('/'), 'Local file viewing requires relative assets')
                    target = WEB / unquote(url.path)
                    self.assertTrue(target.is_file(), str(target))
                    self.assertTrue(target.resolve().is_relative_to(WEB))
        self.assertEqual((WEB / 'assets/icon.png').read_bytes(), (ROOT / 'docs/assets/cosmic-mail.png').read_bytes())

    def test_privacy_and_typography(self):
        policy = next(attrs['content'] for tag, attrs in self.page.tags if tag == 'meta' and attrs.get('http-equiv') == 'Content-Security-Policy')
        for directive in ["connect-src 'none'", "object-src 'none'", "base-uri 'none'", "form-action 'none'", "script-src 'self'"]:
            self.assertIn(directive, policy)
        self.assertNotRegex((WEB / 'styles.css').read_text(), r'letter-spacing\s*:\s*-')
        for _, attrs in self.page.tags:
            self.assertFalse(any(key.startswith('on') for key in attrs))
            self.assertNotIn('style', attrs)
        self.assertIn('<html lang="en">', self.source)

    def test_domain_and_release_links(self):
        self.assertEqual((WEB / 'CNAME').read_text().strip(), 'cmail.songming.org')
        root = ET.parse(WEB / 'sitemap.xml').getroot()
        self.assertEqual(root.find('.//{*}loc').text, 'https://cmail.songming.org/')
        self.assertIn('https://cmail.songming.org/sitemap.xml', (WEB / 'robots.txt').read_text())
        downloads = [attrs['href'] for tag, attrs in self.page.tags if tag == 'a' and 'download' in attrs]
        self.assertEqual(downloads, ['downloads/Cosmic-Mail.zip'] * 4)
        external = [attrs['href'] for tag, attrs in self.page.tags if tag == 'a' and attrs.get('href', '').startswith('https://github.com/')]
        self.assertEqual(len(external), 2)
        self.assertNotRegex(self.source, r'releases/download/[^/]+/')

    def test_download_integrity(self):
        info = json.loads((WEB / 'downloads/latest.json').read_text())
        archive = WEB / 'downloads' / info['file']
        self.assertEqual(info['version'], (ROOT / 'VERSION').read_text().strip())
        self.assertEqual(archive.stat().st_size, info['bytes'])
        self.assertEqual(hashlib.sha256(archive.read_bytes()).hexdigest(), info['sha256'])
        self.assertEqual((WEB / 'downloads/SHA256SUMS.txt').read_text(), info['sha256'] + '  Cosmic-Mail.zip\n')

if __name__ == '__main__': unittest.main()
