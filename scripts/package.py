#!/usr/bin/env python3
"""Package and verify a signed app outside workspace metadata synchronization."""
from pathlib import Path
import hashlib
import subprocess
import tempfile

root = Path(__file__).resolve().parent.parent
version = (root / 'VERSION').read_text().strip()
dist = root / 'dist'
name = f'Cosmic-Mail-{version}-universal.zip'
with tempfile.TemporaryDirectory(prefix='cosmic-mail-package-') as temporary:
    staging = Path(temporary)
    app = staging / 'Cosmic Mail.app'
    subprocess.run(['python3', str(root / 'scripts/bundle.py'), str(app), str(dist / 'CosmicMail')], check=True)
    subprocess.run(['codesign', '--force', '--sign', '-', '--options', 'runtime', '--entitlements',
                    str(root / 'Resources/CosmicMail.entitlements'), str(app)], check=True)
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    archive = staging / name
    subprocess.run(['ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', str(app), str(archive)], check=True)
    # Verify the actual distributable, not a bundle whose root Finder metadata can change later.
    unpacked = staging / 'verify'
    subprocess.run(['ditto', '-x', '-k', str(archive), str(unpacked)], check=True)
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(unpacked / app.name)], check=True)
    subprocess.run(['ditto', str(app), str(dist / app.name)], check=True)
    subprocess.run(['ditto', str(archive), str(dist / name)], check=True)
    with (dist / name).open('rb') as released:
        digest = hashlib.file_digest(released, 'sha256').hexdigest()
    (dist / 'SHA256SUMS.txt').write_text(f'{digest}  {name}\n')
print(f'Built and verified {name}')
