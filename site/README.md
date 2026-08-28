# Murmur project page

Source for the GitHub Pages site at `https://jvr0x.github.io/murmur/`.

Plain HTML, CSS and a few lines of vanilla JS. No framework, no bundler, no build step,
no third-party scripts or fonts. GitHub Actions is not involved; Pages publishes this
folder directly.

## Files

| File | Purpose |
| --- | --- |
| `index.html` | The whole page. Copy lives here, with no templating. |
| `assets/styles.css` | All styling, including the responsive breakpoints. |
| `assets/app.js` | Scroll reveals and the hero's dictation-state animation. Optional: the page reads fully without it. |
| `assets/logo.png` | The app icon / wordmark, copied from `docs/murmur-logo.png`. |

## Preview locally

```sh
cd site
python3 -m http.server 8099       # then open http://localhost:8099/
```

## Layout breakpoints

- `980px` - hero and card grids collapse from two/three columns to one/two.
- `660px` - nav links are hidden (the GitHub button and brand remain), everything goes single column.

The hero's animated mock is disabled under `prefers-reduced-motion`, which leaves the
final sentence statically visible.

## Keep in sync with

Facts on the page are drawn from `README.md`, `PLANNING.md`, `TASK.md`, and the defaults in
`Sources/MurmurKit/Settings/AppConfig.swift`. When the default hotkey, ports, model names,
or a milestone changes, update `index.html` to match, and update the file counts in the
Architecture section.

## Deploy

Published from this `site/` folder on the `main` branch via the Pages REST API
(`build_type: legacy`). Re-running the deploy is only needed after changing the folder
name or the branch; pushes to `main` publish automatically.
