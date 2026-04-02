#!/usr/bin/env python3
"""
tutorial2slides.py — Convert a GEN242 tutorial .qmd file into a Quarto RevealJS .qmd

The input is the tutorial's .qmd source (not the rendered HTML), which is already
clean Markdown and requires no HTML parsing.

Usage:
    python tutorial2slides.py <input.qmd> [options]

Examples:
    python tutorial2slides.py tutorials/github/github.qmd
    python tutorial2slides.py tutorials/linux/linux.qmd --out slides/slides_05/linux_hpc_intro.qmd
    python tutorial2slides.py tutorials/github/github.qmd --title "GitHub Introduction" --max-h3 20

Options:
    --out FILE        Output .qmd path (default: <input_stem>_slides.qmd next to input)
    --title TEXT      Override slide deck title (default: taken from input front matter)
    --author TEXT     Override author (default: taken from input front matter)
    --subtitle TEXT   Subtitle line (default: "GEN242: Data Analysis in Genome Biology")
    --source-url URL  URL to link in footer (default: empty)
    --max-h3 INT      Max lines in an h3 block before it gets its own slide (default: 25)
    --no-scroll       Disable scrollable slides globally
"""

import re
import sys
import argparse
import textwrap
from pathlib import Path


# ── RevealJS front matter template ────────────────────────────────────────────
FRONTMATTER = """\
---
title: "{title}"
subtitle: "{subtitle}"
author: "{author}"
date: today
format:
  revealjs:
    theme: [default, revealjs_custom.scss]
    slide-number: true
    progress: true
    scrollable: true
    smaller: true
    highlight-style: github
    code-block-height: 400px
    transition: slide
    footer: "GEN242 · UC Riverside{footer_source}"
    logo: "https://girke.bioinformatics.ucr.edu/GEN242/assets/logo_gen242.png"
execute:
  echo: true
  eval: false
---
"""


# ── Parse YAML front matter from a .qmd file ─────────────────────────────────
def parse_frontmatter(text: str) -> tuple[dict, str]:
    """
    Returns (metadata_dict, body_text).
    Handles only the simple key: value pairs we care about.
    """
    meta = {}
    body = text
    if text.startswith("---"):
        end = text.find("\n---", 3)
        if end != -1:
            fm_block = text[3:end].strip()
            body = text[end + 4:].lstrip("\n")
            for line in fm_block.splitlines():
                m = re.match(r'^(\w[\w-]*):\s*"?([^"]*)"?\s*$', line)
                if m:
                    meta[m.group(1)] = m.group(2).strip()
    return meta, body


# ── Split body into top-level sections on ## headings ────────────────────────
def split_on_h2(body: str) -> list[dict]:
    """
    Returns a list of dicts: {heading, content}
    Each item covers one ## section including everything until the next ##.
    The preamble before the first ## (if any) is discarded.
    """
    sections = []
    # split on lines that start with exactly ## (not ### or ####)
    parts = re.split(r'(?m)^(?=## )', body)
    for part in parts:
        part = part.strip()
        if not part:
            continue
        m = re.match(r'^## (.+)', part)
        if m:
            heading = m.group(1).strip()
            content = part[m.end():].strip()
            sections.append({"heading": heading, "content": content})
        # preamble (no ## heading) is silently skipped
    return sections


# ── Count non-empty lines as a proxy for content volume ──────────────────────
def count_content_lines(text: str) -> int:
    return sum(1 for l in text.splitlines() if l.strip())


# ── Decide how to split an h2 section ────────────────────────────────────────
def split_section(heading: str, content: str, max_h3: int) -> list[dict]:
    """
    Short sections  → single slide, not scrollable.
    Long sections   → single scrollable slide (### become subheadings within it).
    This avoids fragmenting into many tiny slides, which is worse for lectures.
    """
    scrollable = count_content_lines(content) > max_h3
    return [{"heading": heading, "content": content, "scrollable": scrollable}]


# ── Clean heading: strip any existing Quarto attributes ──────────────────────
def clean_heading(h: str) -> str:
    return re.sub(r'\s*\{[^}]*\}', '', h).strip()


# ── Render one slide ──────────────────────────────────────────────────────────
def render_slide(heading: str, content: str, scrollable: bool) -> str:
    attrs = "{.scrollable}" if scrollable else ""
    slide_head = f"## {clean_heading(heading)} {attrs}".strip()

    # strip redundant {.class} attributes already on ### / #### lines
    content = re.sub(r'(?m)^(#{3,6} .+?)\s*\{[^}]*\}', r'\1', content)
    # collapse excessive blank lines
    content = re.sub(r'\n{3,}', '\n\n', content)

    return f"{slide_head}\n\n{content.strip()}"


# ── Main conversion ───────────────────────────────────────────────────────────
def convert(input_path: Path,
            title: str = None,
            subtitle: str = "",
            author: str = "",
            source_url: str = "",
            max_h3: int = 25) -> str:

    raw = input_path.read_text(encoding="utf-8")
    meta, body = parse_frontmatter(raw)

    # CLI args override front matter values
    resolved_title  = title  or meta.get("title",  input_path.stem.replace("_", " ").title())
    resolved_author = author or meta.get("author", "Thomas Girke")
    resolved_sub    = subtitle or "GEN242: Data Analysis in Genome Biology"
    footer_source   = f" · [Tutorial source]({source_url})" if source_url else ""

    fm = FRONTMATTER.format(
        title=resolved_title,
        subtitle=resolved_sub,
        author=resolved_author,
        footer_source=footer_source,
    )

    # strip existing RevealJS slide separators from the source body
    body = re.sub(r"(?m)^---\s*$", "", body)

    sections = split_on_h2(body)
    print(f"  Found {len(sections)} sections (##)")

    slides = []
    for sec in sections:
        slides.extend(split_section(sec["heading"], sec["content"], max_h3))

    print(f"  Generated {len(slides)} slides")

    rendered = [render_slide(s["heading"], s["content"], s["scrollable"])
                for s in slides]

    joined = "\n\n---\n\n".join(rendered)
    # collapse any accidental double separators left by the input source
    joined = re.sub(r'(\n---\n)\n---\n', r'\1', joined)
    return fm + "\n" + joined + "\n"


# ── CLI ───────────────────────────────────────────────────────────────────────
def main():
    parser = argparse.ArgumentParser(
        description="Convert a GEN242 tutorial .qmd to a Quarto RevealJS deck",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=textwrap.dedent("""
        Examples:
          python tutorial2slides.py tutorials/github/github.qmd

          python tutorial2slides.py tutorials/linux/linux.qmd \\
              --out slides/slides_05/linux_hpc_intro.qmd \\
              --source-url https://girke.bioinformatics.ucr.edu/GEN242/tutorials/linux/linux.html
        """)
    )
    parser.add_argument("input",
                        help="Path to the tutorial .qmd source file")
    parser.add_argument("--out",
                        help="Output .qmd path (default: <stem>_slides.qmd beside input)")
    parser.add_argument("--title",
                        help="Override slide deck title")
    parser.add_argument("--subtitle",   default="",
                        help="Subtitle line")
    parser.add_argument("--author",     default="",
                        help="Override author name")
    parser.add_argument("--source-url", default="", dest="source_url",
                        help="Tutorial URL shown in the footer")
    parser.add_argument("--max-h3",     type=int, default=25, dest="max_h3",
                        help="Non-empty lines before a section becomes scrollable (default: 25)")
    args = parser.parse_args()

    input_path = Path(args.input)
    if not input_path.exists():
        sys.exit(f"File not found: {input_path}")

    out_path = Path(args.out) if args.out else \
               input_path.parent / f"{input_path.stem}_slides.qmd"

    print(f"Input:  {input_path}")
    print(f"Output: {out_path}")

    qmd = convert(
        input_path=input_path,
        title=args.title,
        subtitle=args.subtitle,
        author=args.author,
        source_url=args.source_url,
        max_h3=args.max_h3,
    )

    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(qmd, encoding="utf-8")
    print(f"Written: {out_path}  ({len(qmd.splitlines())} lines)")
    print()
    print("Next steps:")
    print(f"  1. Review and edit {out_path}")
    print(f"  2. quarto render {out_path}")
    print(f"  3. Embed the resulting .html in slides_NN.qmd via <iframe>")


if __name__ == "__main__":
    main()
