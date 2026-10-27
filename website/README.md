<!--
  Reel website: how it's built and deployed.
  Author: Alexius Academia
  Date: 2026-10-27
-->
# Reel website

Plain HTML and CSS, no build step. Live at https://reel.syncster.dev.

- **Deploys:** the Netlify project `reel` is linked to this repository with
  base folder `website`; every push to `main` publishes it.
- **Screenshots:** `assets/*.jpg|png` are copies of `docs/screenshots/`.
  After retaking those for the README, copy them here too.
- **Downloads:** the buttons read "Not released yet" until `downloads.json`
  has entries (`{"macos": {"version", "url", "size"}, "windows": {…}}`);
  `downloads.js` fills them in and counts presses of links into the
  `reel-releases` bucket (see `privacy.html`).
- **Preview locally:** `python3 -m http.server 8931 --directory website`.
