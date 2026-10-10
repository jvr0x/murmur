# Murmur project page

Source for the GitHub Pages site at <https://jvr0x.com/murmur/>.

Plain HTML, CSS and a few lines of vanilla JS. No framework, no bundler, no build step,
and no third-party scripts or analytics. The only outside resources come from the shared
jvr0x.com chrome: `/assets/chrome.css`, which imports JetBrains Mono from Google Fonts.

## Files

| File | Purpose |
| --- | --- |
| `index.html` | The whole page. All copy lives here, with no templating. |
| `assets/styles.css` | All styling, including the responsive breakpoints. |
| `assets/app.js` | Scroll reveals and the hero's dictation-state animation. Optional: the page reads in full without it. |
| `assets/logo.png` | The app mark, copied from `docs/murmur-logo.png`. |
| `/assets/chrome.css` | Not in this repo. The shared jvr0x.com header/footer styles, served root-relative from the jvr0x.github.io repo. |
| `README.md` | This file. On the published branch it becomes `BUILD.md` so it does not compete with `index.html`. |

## Shared jvr0x.com chrome

The blocks between `<!-- jx:header -->` / `<!-- /jx:header -->` and `<!-- jx:footer -->` /
`<!-- /jx:footer -->` in `index.html` are the site-wide header and footer. They are rewritten
from `partials/header.html` and `partials/footer.html` in jvr0x.github.io by its
`tools/build.py`, so do not hand-edit them here. Murmur's own section nav and footer sit
inside them and stay page-specific.

## Deploy

`site/` is the source; the `gh-pages` branch is a published copy of it. Push changes here,
then republish:

```sh
./Scripts/publish-site.sh      # copies site/ -> gh-pages and pushes it
```

The script resets `gh-pages` to the contents of `site/`, adds a `.nojekyll` marker so Pages
does not run Jekyll over the output, and renames this file to `BUILD.md`. To check the script
itself without publishing, run `./Scripts/tests/test-publish-site.sh` (it publishes into a
throwaway local repo, never the real `origin`). Pages rebuilds on each push; watch the build with:

```sh
gh api repos/jvr0x/murmur/pages/builds/latest --jq '.status'
```

A GitHub Actions workflow using `actions/deploy-pages` is the usual alternative, and gives a
logged run per publish, but committing it needs a token with the `workflow` scope.

## Preview locally

```sh
cd site
python3 -m http.server 8099       # then open http://localhost:8099/
```

`/assets/chrome.css` does not resolve on a local server, so the shared header and footer
render unstyled in a preview.

## Layout breakpoints

- `980px` - the hero goes single column; card and stat grids drop from three/four-up to two-up.
- `860px` - three-up card rows, the stat row and the pipeline steps go single column, so a third card never lands alone at half width.
- `660px` - nav links are hidden (the brand and GitHub button remain) and padding tightens.

The hero's animated mock is disabled under `prefers-reduced-motion`, which leaves the final
sentence statically visible instead.

## Keep in sync with

The facts on this page come from `README.md`, `PLANNING.md`, `TASK.md`, and the defaults in
`Sources/MurmurKit/Settings/AppConfig.swift`. If the default hotkey, ports, model names or a
milestone changes, update `index.html` to match, along with the file counts in the
Architecture section.
