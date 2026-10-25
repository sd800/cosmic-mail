# Cosmic Mail website

The English product website for https://cmail.songming.org/.

## Local viewing

Double-click `index.html`. HTML, CSS, JavaScript, the app icon, and the interactive product illustration are local files. There are no packages to install, build steps, external fonts, analytics, or runtime data requests. The sky-blue palette follows the system appearance automatically. All typography uses system fonts with normal or positive letter spacing.

The preview contains illustrative email at example.org, not real messages or a live mail reader. Its copy buttons act only on that example. The single download link opens the repository's latest release, so a website update does not pin a superseded installer. Other calls to action remain inside the page; the footer retains one source-repository link.

## Deployment

`.github/workflows/website.yml` validates the site and publishes the allowlisted web assets to GitHub Pages on main-branch changes to this directory. It can also run manually. Only the deployment job receives Pages write and OIDC permissions. Actions are pinned to official commit IDs; checkout does not retain credentials. The workflow never changes repository settings.

Select **GitHub Actions** as the Pages source in repository Settings, set the custom domain to `cmail.songming.org`, and configure the corresponding DNS record. Then run **Deploy Cosmic Mail website** if no new website commit is pending. Before Pages is enabled with the Actions source, the workflow completes validation and skips deployment. `CNAME` records the intended domain; repository Settings remains authoritative for Actions deployments.

`web/VERSION` identifies website revisions independently of the installed app's root `VERSION`. Website-only changes do not require an app build or a new app download.

## Maintenance

Run `python3 -B -m unittest discover -s test -p 'website_test.py'` and `node --check web/site.js`. After layout or interaction changes, check local file opening in light/dark appearance, keyboard tab selection, copying, anchored navigation, reduced motion, and a narrow viewport. Reuse browser checks under ignored `test-dist/website` without saving private data or full logs.

The installation section below Download walks through the release asset, ZIP extraction, Applications, an initial open attempt, macOS Privacy & Security approval, and optional email-link setup. Keep approval limited to Cosmic Mail, without Terminal commands or global security changes. Apple’s linked guidance is the reference for current macOS terminology.
