# GEN242 — Quarto site migration guide

## Local preview

```bash
# Install Quarto: https://quarto.org/docs/get-started/
# Use: sudo dpkg -i quarto-<version>.deb
#      quarto --version
git clone https://github.com/tgirke/GEN242 && cd GEN242

quarto preview --no-browser # live-reloads in browser on every save; not --no-browser only needed on ChromeOS
quarto preview tutorials/<path_to_file>.qmd --no-browser # renders only specific qmd
quarto render     # full build → writes to /docs
```

Commit to github

```bash
git add .
git status    # review
git commit -m "some message"
git push origin main
```

---

## Project structure

```
GEN242/
├── _quarto.yml                 ← site config (navbar, sidebars, theme, execution)
├── index.qmd                   ← homepage
├── assets/
│   ├── custom.scss             ← minimal overrides on top of cosmo
│   ├── custom-dark.scss        ← dark-mode overrides
│   └── logo.png                ← replace with your own discrete logo
├── overview/
│   ├── introduction.qmd
│   ├── syllabus.qmd
│   └── other.qmd
├── schedule/index.qmd
├── slides/
│   ├── index.qmd               ← slides landing page
│   ├── slides_01.qmd           ← add `sidebar: slides` in front matter
│   └── ...
├── tutorials/
│   ├── index.qmd               ← tutorials landing page
│   ├── rbasics/index.qmd       ← add `sidebar: tutorials` in front matter
│   └── ...
├── assignments/
│   ├── index.qmd
│   ├── homework/hw01/index.qmd ← add `sidebar: assignments` in front matter
│   └── ...
├── links/index.qmd
├── _freeze/                    ← COMMIT THIS — cached chunk outputs
└── docs/                       ← rendered site (served by GitHub Pages)
```

---

## How the sidebar activates

Each content page declares which sidebar it belongs to in its YAML front matter:

```yaml
---
title: "RNA-Seq Workflow (T8)"
sidebar: tutorials          # matches id: tutorials in _quarto.yml
---
```

That's it. No other wiring needed. The page gets the full Tutorials sidebar with
all sections, and its entry is highlighted automatically.

---

## Migrating .Rmd files

Rename `.Rmd` → `.qmd` and update the YAML front matter:

**Hugo (old)**
```yaml
---
title: "Introduction to R"
type: tutorials
weight: 3
slug: rbasics
---
```

**Quarto (new)**
```yaml
---
title: "Introduction to R (T3)"
date: last-modified
sidebar: tutorials
---
```

Remove: `type`, `weight`, `slug`, any `output:` block.  
All R code chunks work as-is. Hugo shortcodes need replacing with Quarto
equivalents (callouts, cross-references, divs) — this is the main manual step.

---

## Freeze strategy

`freeze: auto` in `_quarto.yml` caches rendered outputs in `_freeze/`.
Commit that directory so GitHub Actions CI never re-executes unchanged pages.

Force a single page to re-execute:
```bash
quarto render tutorials/sprnaseq/index.qmd --cache-refresh
```

---

## GitHub Pages (one-time setup)

1. Push repo to GitHub
2. **Settings → Pages → Source → GitHub Actions**
3. Push to `main` — `.github/workflows/publish.yml` builds and deploys automatically
4. Optionally set a custom domain in the Pages settings

---

## Logo

Replace `assets/logo.png` with your own image.
The `.scss` keeps it 28 px tall and slightly muted — visually discrete,
not competing with content.
