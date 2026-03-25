# GEN242 — Site Administration Guide

Internal documentation for site maintenance and content migration.  
Live site: <https://girke.bioinformatics.ucr.edu/GEN242/>

---

## Table of Contents

- [Repository structure](#repository-structure)
- [One-time local setup](#one-time-local-setup)
- [Daily workflow](#daily-workflow)
- [Migrating a tutorial from the old site](#migrating-a-tutorial-from-the-old-site)
- [Converting a .qmd back to .Rmd](#converting-a-qmd-back-to-rmd)
- [Adding a new page to the navigation](#adding-a-new-page-to-the-navigation)
- [GitHub Actions and deployment](#github-actions-and-deployment)
- [R package cache](#r-package-cache)
- [Troubleshooting](#troubleshooting)
- [Google Search Console and SEO](#google-search-console-and-seo)

---

## Repository structure

```
GEN242_new/
├── _quarto.yml                  # site config: navbar, sidebars, theme, execution
├── index.qmd                    # homepage
├── assets/
│   ├── logo_gen242.png          # navbar logo
│   ├── custom.scss              # minimal CSS overrides (light mode)
│   └── custom-dark.scss         # minimal CSS overrides (dark mode)
├── overview/
│   ├── introduction.qmd
│   ├── syllabus.qmd
│   └── other.qmd
├── schedule/index.qmd
├── slides/
│   ├── index.qmd                # slides landing page
│   ├── slides_01.qmd            # individual slide pages (sidebar: slides)
│   └── ...
├── tutorials/
│   ├── index.qmd                # tutorials landing page
│   ├── rbasics/
│   │   ├── rbasics_index.qmd    # main tutorial file (sidebar: tutorials)
│   │   └── images/              # images used by this tutorial
│   └── ...
├── assignments/
│   ├── index.qmd
│   ├── homework/
│   │   ├── hw01/index.qmd
│   │   └── ...
│   └── projects/index.qmd
├── links/index.qmd
├── scripts/
│   ├── rmd2qmd.py               # conversion script: .Rmd -> .qmd
│   └── qmd2rmd.py               # conversion script: .qmd -> .Rmd
├── _freeze/                     # Quarto freeze cache — COMMIT THIS
├── .github/
│   └── workflows/
│       └── publish.yml          # GitHub Actions build + deploy pipeline
└── docs/                        # rendered site — served by GitHub Pages
```

---

## One-time local setup

### 1. Install Quarto

Download and install from <https://quarto.org/docs/get-started/>.  
Verify:
```bash
quarto --version
```

### 2. Install R and required packages

Install R 4.5 from <https://cran.r-project.org/>.  
Then install all required packages from the R console:

```r
# CRAN packages
install.packages(c(
  "BiocManager", "knitr", "rmarkdown", "DT", "dplyr",
  "ggplot2", "tidyverse", "reticulate", "htmlwidgets", "plotly",
  "tidyr", "stringr", "tibble", "purrr", "readr",
  "RSQLite", "dbplyr", "ggrepel", "pheatmap", "RColorBrewer"
))

# Bioconductor packages
BiocManager::install(version = "3.22")
BiocManager::install(c(
  "GenomicRanges", "GenomicFeatures", "GenomicAlignments",
  "Biostrings", "IRanges", "S4Vectors",
  "DESeq2", "edgeR", "limma", "BiocParallel",
  "AnnotationDbi", "org.Hs.eg.db", "org.At.tair.db",
  "TxDb.Athaliana.BioMart.plantsmart28",
  "BSgenome.Athaliana.TAIR.TAIR9",
  "systemPipeR", "systemPipeRdata",
  "SingleCellExperiment", "scuttle",
  "ChIPseeker", "DiffBind",
  "VariantAnnotation", "VariantFiltering"
))
```

### 3. Clone the repository

```bash
git clone git@github.com:tgirke/GEN242_new.git
cd GEN242_new
```

### 4. Verify local preview works

```bash
quarto preview --no-browser
```

Open <http://localhost:5675/> in your browser. The site live-reloads when you save any `.qmd` file.

> **Note for ChromeOS/Linux container users:** `quarto preview` (without `--no-browser`) will crash due to missing display drivers. Always use `--no-browser` and open the URL in Chrome manually. Add this alias to `~/.bashrc` for convenience:
> ```bash
> alias qp='quarto preview --no-browser'
> ```

---

## Daily workflow

### Editing a single page

```bash
# Start preview server
quarto preview --no-browser

# Edit the file in your editor — page auto-refreshes in browser
nvim tutorials/rbasics/rbasics_index.qmd

# When happy, commit and push to deploy
git add tutorials/rbasics/rbasics_index.qmd
git add _freeze/                          # always include freeze cache updates
git commit -m "Update rbasics tutorial"
git push origin main
```

### Rendering a single page (without the full preview server)

```bash
quarto render tutorials/rbasics/rbasics_index.qmd
```

### Full site render

```bash
quarto render
```

This writes all output to `docs/`. Only needed occasionally — GitHub Actions handles full builds automatically on every push.

### Checking for broken links

Quarto warns about unresolved links during render. Warnings like:
```
WARN: Unable to resolve link target: tutorials/rbasics/index.qmd
```
mean a sidebar or navbar entry in `_quarto.yml` points to a file that doesn't exist yet. These are harmless for stub pages but should be fixed as you migrate content.

---

## Migrating a tutorial from the old site

This is the main task for porting content from the old Hugo/GEN242 site.

### Step 1 — Convert the .Rmd file

Use the conversion script in `scripts/rmd2qmd.py`. It handles all mechanical formatting changes without touching content.

```bash
python3 scripts/rmd2qmd.py \
  /path/to/old/Rbasics.Rmd \
  tutorials/rbasics/rbasics_index.qmd \
  --repo https://github.com/tgirke/GEN242_new
```

**What the script does automatically:**
1. Replaces Hugo YAML front matter with Quarto front matter
2. Removes the compile-from-command-line HTML comment
3. Removes the `BiocStyle::markdown()` setup chunk
4. Removes the Hugo source download `<div>`
5. De-indents code chunks inside numbered lists (fixes Quarto `:::` wrapping)
6. Converts chunk headers: `eval=FALSE` → `#| eval: false` style
7. Converts `<center><img>` tags to Quarto `![](images/...)` syntax
8. Inserts blank lines before code chunks (required by Quarto)
9. Updates known internal links to relative `.qmd` paths

**Interactive mode** (review each change before applying):
```bash
python3 scripts/rmd2qmd.py Rbasics.Rmd tutorials/rbasics/rbasics_index.qmd \
  --repo https://github.com/tgirke/GEN242_new --interactive
```

### Step 2 — Copy images

Each tutorial's images live in its own `images/` subdirectory:

```bash
cp -r /path/to/old/content/en/tutorials/rbasics/images \
      tutorials/rbasics/images
```

### Step 3 — Update _quarto.yml sidebar entry

The sidebar in `_quarto.yml` needs to point to the new file. Find the T3 entry and update the `href`:

```yaml
- text: "T3 — Introduction to R"
  href: tutorials/rbasics/rbasics_index.qmd
```

### Step 4 — Test locally

```bash
quarto render tutorials/rbasics/rbasics_index.qmd
# or
quarto preview --no-browser
```

Check for:
- No `:::` artifacts in the rendered HTML
- Images loading correctly
- Code chunks executing without errors
- Download .qmd link in the right margin works

### Step 5 — Commit and push

Step-wise
```bash
FOLDER="rbasics" && 
git add "tutorials/$FOLDER/" && 
git add _freeze/ && 
git add _quarto.yml && 
git commit -m "Migrate $FOLDER tutorial" && 
git push origin main
```

Single line
```bash
FOLDER="rbasics"; git add "tutorials/$FOLDER/"; git add _freeze/; git add _quarto.yml; git commit -m "Migrate $FOLDER tutorial"; git push origin main
```

GitHub Actions will build and deploy automatically. Monitor progress at:  
<https://github.com/tgirke/GEN242_new/actions>


### Internal link map

When the script updates internal links (Step 9), it uses this map.
**Extend this map in `rmd2qmd.py` as you migrate more tutorials:**

| Old Hugo URL | New relative path |
|---|---|
| `.../tutorials/rbasics/rbasics/` | `../rbasics/rbasics_index.qmd` |
| `.../tutorials/rprogramming/rprogramming/` | `../rprogramming/index.qmd` |
| `.../tutorials/dplyr/dplyr/` | `../dplyr/index.qmd` |
| `.../tutorials/linux/linux/` | `../linux/index.qmd` |
| `.../tutorials/rmarkdown/rmarkdown/` | `../rmarkdown/index.qmd` |
| `.../tutorials/rgraphics/rgraphics/` | `../rgraphics/index.qmd` |
| `.../assignments/homework/hw03/hw03/` | `../../assignments/homework/hw03/index.qmd` |

---

## Converting a .qmd back to .Rmd

Use `scripts/qmd2rmd.py` to convert a Quarto `.qmd` file back to R Markdown `.Rmd` format.
This is useful when you need to run content through Bioconductor tools or workflows that
require the standard knitr/rmarkdown toolchain.

```bash
# Auto-named output (rbasics_index.qmd -> Rbasics.Rmd)
python3 scripts/qmd2rmd.py tutorials/rbasics/rbasics_index.qmd

# Explicit output name
python3 scripts/qmd2rmd.py tutorials/rbasics/rbasics_index.qmd Rbasics.Rmd

# Interactive mode — review each change before applying
python3 scripts/qmd2rmd.py tutorials/rbasics/rbasics_index.qmd Rbasics.Rmd --interactive
```

**What the script reverses automatically:**

| `rmd2qmd.py` did | `qmd2rmd.py` reverses |
|---|---|
| Quarto YAML front matter | Restores Rmd YAML + BiocStyle chunk |
| `#\| eval: false` options | Restores `eval=FALSE` inline options |
| `bash` chunks | Restores `sh` chunks |
| `![](images/x.png)` figures | Restores `<center><img src="../images/x.png"/>` |
| `**Step N.**` bold labels | Restores indented numbered list items |
| Relative `.qmd` links | Restores absolute old-site URLs |

**Important:** This conversion is lossless only if you avoided Quarto-specific features
(callout blocks `:::`, cross-references `@fig-xxx`, layout divs) during authoring.
If you stuck to plain markdown and standard chunk options, the round-trip is clean.

Run with `--interactive` the first time for each file to spot any edge cases before
committing the output.


---

## Adding a new page to the navigation

### Add a page to the Tutorials sidebar

1. Create the file: `tutorials/mytutorial/mytutorial_index.qmd`
2. Add `sidebar: tutorials` to its YAML front matter
3. Add an entry to `_quarto.yml` under the appropriate section:

```yaml
- text: "T99 — My New Tutorial"
  href: tutorials/mytutorial/mytutorial_index.qmd
```

### Add a page with multiple parts

Multiple `.qmd` files can live in the same directory:

```
tutorials/rbasics/
├── rbasics_index.qmd      # Part 1 — listed in sidebar
├── rbasics2.qmd           # Part 2 — listed in sidebar
└── images/
```

Each file needs its own sidebar entry in `_quarto.yml` and `sidebar: tutorials` in its front matter.

---

## GitHub Actions and deployment

Every push to `main` triggers `.github/workflows/publish.yml` which:

1. Sets up R 4.5 and installs all packages (skipped on cache hit — usually ~30s)
2. Sets up Python 3.11
3. Installs Quarto 1.5.56
4. Renders the full site (`quarto render`)
5. Deploys `docs/` to GitHub Pages

**Build times:**
- Cache hit (normal push): ~2-3 minutes
- Cache miss (after changing `publish.yml`): ~10-12 minutes

**Cache invalidation:** The R package cache key is based on `publish.yml`. Any change to that file triggers a full reinstall. This is intentional — if you add a new package to the install list, the cache refreshes.

**Watching a build:**  
Go to <https://github.com/tgirke/GEN242_new/actions>, click the running workflow, expand any step to see live output.

---

## R package cache

Two caches are committed to this repository:

**`_freeze/`** — Quarto's execution cache. Stores which chunks need re-executing.  
With `freeze: auto` in `_quarto.yml`, only files whose source has changed re-execute on the next render. Always commit this directory.

**`tutorials/*/rbasics_index_cache/`** — knitr's chunk cache. Stores R objects from executed chunks so they don't re-run unnecessarily. Always commit these directories.

To force a single page to re-execute from scratch:
```bash
quarto render tutorials/rbasics/rbasics_index.qmd --cache-refresh
```

To force the full site to re-execute:
```bash
rm -rf _freeze/
quarto render
```

---

## Troubleshooting

### `:::` artifacts appearing in rendered HTML

A code chunk is inside a numbered list without proper separation. The `rmd2qmd.py` script handles this automatically. If you see it in a manually edited file, either:
- Convert the numbered list item to a `**Step N.**` bold label
- Or ensure the code chunk is not indented inside the list

### Blank lines before code chunks

Quarto requires a blank line between prose and a code chunk. The script inserts these automatically. If you add content manually and see rendering issues, check that every ` ``` ` opener has a blank line above it.

### Images not loading (404)

Images must be in `images/` within the same tutorial directory and referenced as `images/filename.png` — not `../images/` (the old Hugo convention). The script converts these paths automatically.


### Build fails with `path for html_dependency not found: /home/yourname/R/...`

This error means a locally-generated knitr chunk cache or Quarto freeze cache was
committed to the repo with hardcoded local paths. GitHub Actions can't find those
paths on the runner.

Fix by clearing both caches for the affected tutorial and letting GitHub Actions
re-execute it from scratch:

```bash
rm -rf tutorials/sometutorial/sometutorial_cache/
rm -rf _freeze/tutorials/sometutorial/
git add tutorials/sometutorial/
git commit -m "Clear caches for sometutorial to fix hardcoded local paths"
git push origin main
```

Replace `sometutorial` with the actual tutorial directory name. The next Actions run
will re-execute the tutorial cleanly using the runner's own R library paths and save
a new cache that works on all machines.

### Build fails with missing R package

Add the package to the appropriate install step in `.github/workflows/publish.yml`, then push. The cache will miss once (full reinstall) and then be fast again on subsequent pushes.

### GitHub Pages shows old content

GitHub Pages can take 1-2 minutes to update after a successful deploy. Check the Actions tab to confirm the deploy step succeeded, then hard-refresh the browser (`Ctrl+Shift+R`).

### `quarto preview` crashes on ChromeOS

Use `quarto preview --no-browser` and open `http://localhost:5675/` in Chrome manually.

---

## Google Search Console and SEO

Follow these steps to make the site discoverable in Google searches.

### Step 1 — Verify ownership of the root domain

Only needs to be done once for `https://girke.bioinformatics.ucr.edu/`. All
project sites (GEN242, etc.) inherit verification automatically.

1. Go to [search.google.com/search-console](https://search.google.com/search-console)
2. Click **Add property** → choose **URL prefix**
3. Enter `https://girke.bioinformatics.ucr.edu/`
4. Choose **HTML tag** as the verification method
5. Copy the `content="..."` value from the meta tag shown
6. Add it to `_quarto.yml` of the root site (`tgirke.github.io`) under `format: html:`:

```yaml
format:
  html:
    include-in-header:
      text: |
        <meta name="google-site-verification" content="YOUR_VERIFICATION_CODE">
```

7. Commit and push, wait for GitHub Actions to deploy
8. Click **Verify** in Search Console

### Step 2 — Submit sitemaps

Quarto automatically generates a `sitemap.xml` for every site. Submit it for
each property in Search Console:

1. In Search Console select the property
2. Go to **Sitemaps** in the left menu
3. Enter `sitemap.xml` and click **Submit**

Sitemap URLs:
- Root site: `https://girke.bioinformatics.ucr.edu/sitemap.xml`
- GEN242: `https://girke.bioinformatics.ucr.edu/GEN242/sitemap.xml`

### Step 3 — Add project sites to Search Console

For project repos like GEN242, just add a new URL prefix property:

1. Click **Add property** → **URL prefix**
2. Enter `https://girke.bioinformatics.ucr.edu/GEN242/`
3. Search Console will verify automatically since the root domain is already verified
4. Submit the sitemap as in Step 2

### Step 4 — Add Open Graph metadata (recommended)

Add to `_quarto.yml` of each site for better search engine and social media previews:

```yaml
website:
  open-graph: true
  twitter-card: true
```

### Notes

- Google typically starts indexing within a few days to a couple of weeks after sitemap submission
- Monitor indexing progress in Search Console under **Pages**
- The verification meta tag must stay in `_quarto.yml` permanently — removing it loses verification
