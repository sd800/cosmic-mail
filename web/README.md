# Cosmic Mail website

The English product website for https://cmail.songming.org/.

## Local viewing

Double-click `index.html`. HTML, CSS, JavaScript, the app icon, and the interactive product illustration are local files. There are no packages to install, build steps, external fonts, analytics, or runtime data requests. The sky-blue palette follows the system appearance automatically. All typography uses system fonts with normal or positive letter spacing.

The preview contains illustrative email at example.org, not real messages or a live mail reader. Its copy buttons act only on that example. All three app buttons download downloads/Cosmic-Mail.zip directly from the website. The archive is byte-identical to the verified app release; scripts/package.py refreshes it and its version/checksum metadata with every app package. The header and footer provide source-repository links.

## Deployment

`.github/workflows/website.yml` validates the site and publishes the allowlisted web assets to GitHub Pages on main-branch changes to this directory. It can also run manually. Only the deployment job receives Pages write and OIDC permissions. Actions are pinned to official commit IDs; checkout does not retain credentials. The workflow never changes repository settings.

Select **GitHub Actions** as the Pages source in repository Settings, set the custom domain to `cmail.songming.org`, and configure the corresponding DNS record. Then run **Deploy Cosmic Mail website** if no new website commit is pending. Before Pages is enabled with the Actions source, the workflow completes validation and skips deployment. `CNAME` records the intended domain; repository Settings remains authoritative for Actions deployments.

`web/VERSION` identifies website revisions independently of the installed app's root `VERSION`. Website-only changes do not require an app build or a new app download.

## Maintenance

Run `python3 -B -m unittest discover -s test -p 'website_test.py'` and `node --check web/site.js`. After layout or interaction changes, check local file opening in light/dark appearance, keyboard tab selection, copying, anchored navigation, reduced motion, and a narrow viewport. Reuse browser checks under ignored `test-dist/website` without saving private data or full logs.

The installation section below Download uses three open columns consistent with the site layout, covering ZIP extraction, Applications, an initial open attempt, and macOS Privacy & Security approval. First-launch help and optional email-link setup use the same disclosure style as the FAQ. Keep approval limited to Cosmic Mail, without Terminal commands or global security changes. Apple’s linked guidance is the reference for current macOS terminology.

HTTP/HTTPS visits to /index.html, /index, and /index/ return to the root address while retaining query parameters and fragments. The index/ directory supplies a static alias for extensionless requests; redirect.js normalizes navigation before page rendering. File URLs retain normal local opening.
