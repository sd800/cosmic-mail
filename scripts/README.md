# Development scripts

Run commands from the project root.

| Folder | Purpose |
| --- | --- |
| `build/` | Universal app builds, native bundle metadata, signing, and release packaging. |
| `checks/` | The Swift test entry point. |
| `assets/` | Native icon artwork generation. |
| `fixtures/` | Synthetic messages, archives, and mail-review fixtures. |
| `update/` | Generated HTML entity reference data. |

```sh
./scripts/checks/test.sh
./scripts/build/build.sh
python3 scripts/fixtures/make-fixtures.py
```

The build entry calls its bundle/packaging helpers and the icon source from their categorized paths. Fixtures belong in ignored `test-dist/`. See [technical design](../docs/TECHNICAL.md) and [QA](../docs/QA.md) for the corresponding procedures.
