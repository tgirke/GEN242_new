#!/usr/bin/env python3
"""
qmd2rmd.py -- Convert Quarto .qmd files back to R Markdown .Rmd format
Usage:
    python3 qmd2rmd.py input.qmd                        # auto output name
    python3 qmd2rmd.py input.qmd output.Rmd             # explicit output name
    python3 qmd2rmd.py input.qmd --interactive          # step-by-step review
    python3 qmd2rmd.py input.qmd output.Rmd --interactive

What this script does (content is never changed, only formatting):
    1.  Replace Quarto YAML front matter with Rmd front matter
    2.  Convert #| chunk options back to inline chunk header options
    3.  Convert Quarto figure syntax back to <center><img> HTML
    4.  Convert **Step N.** labels back to numbered list items with indented chunks
    5.  Update relative .qmd links back to absolute old-site URLs

Note on compatibility:
    This script only reverses the mechanical changes made by rmd2qmd.py.
    Avoid using Quarto-specific features (callout blocks, cross-references,
    layout divs) in .qmd files if you need round-trip compatibility.
"""

import re
import sys
import os

# ── Helpers ───────────────────────────────────────────────────────────────────

def show_diff(label, before, after):
    if before == after:
        print(f"  [{label}] No changes.")
        return
    before_lines = before.splitlines()
    after_lines  = after.splitlines()
    print(f"\n  [{label}] BEFORE ({len(before_lines)} lines) -> AFTER ({len(after_lines)} lines)")
    shown = 0
    for i, (b, a) in enumerate(zip(before_lines, after_lines)):
        if b != a and shown < 20:
            print(f"    - {b[:120]}")
            print(f"    + {a[:120]}")
            shown += 1
    if len(after_lines) != len(before_lines):
        print(f"    ... (line count changed by {len(after_lines)-len(before_lines)})")

def ask(label, before, after, interactive):
    if not interactive:
        return after
    if before == after:
        return after
    show_diff(label, before, after)
    while True:
        ans = input("  Apply this change? [y/n/q] ").strip().lower()
        if ans == 'y':   return after
        elif ans == 'n': return before
        elif ans == 'q':
            print("Quitting.")
            sys.exit(0)

# ── Step 1: Replace Quarto YAML with Rmd YAML + BiocStyle setup chunk ─────────

def replace_yaml(content, interactive, output_path=''):
    yaml_match = re.match(r'^---\n(.*?)\n---\n', content, re.DOTALL)
    if not yaml_match:
        print("  [YAML] WARNING: Could not find YAML front matter.")
        return content

    old_yaml_block = yaml_match.group(0)
    yaml_body      = yaml_match.group(1)

    title_m = re.search(r'^title:\s*["\']?(.+?)["\']?\s*$', yaml_body, re.MULTILINE)
    title   = title_m.group(1).strip() if title_m else "Untitled"

    author_m = re.search(r'^author:\s*["\']?(.+?)["\']?\s*$', yaml_body, re.MULTILINE)
    author   = author_m.group(1).strip() if author_m else "Thomas Girke"

    output_base = os.path.basename(output_path) if output_path else "output.Rmd"
    output_r    = os.path.splitext(output_base)[0] + '.R'
    tut_name    = os.path.splitext(output_base)[0].replace('_index', '').replace('_', '')

    new_yaml = (
        '---\n'
        'title: "' + title + '"\n'
        'author: "Author: ' + author + '"\n'
        'date: "Last update: `r format(Sys.time(), \'%d %B, %Y\')`"\n'
        'output:\n'
        '  html_document:\n'
        '    toc: true\n'
        '    toc_float:\n'
        '        collapsed: true\n'
        '        smooth_scroll: true\n'
        '    toc_depth: 3\n'
        '    fig_caption: yes\n'
        '    code_folding: show\n'
        '    number_sections: true\n'
        'fontsize: 14pt\n'
        'bibliography: bibtex.bib\n'
        'weight: 4\n'
        'type: docs\n'
        '---\n'
        '\n'
        '<!---\n'
        '- Compile from command-line\n'
        'Rscript -e "rmarkdown::render(\'' + output_base + '\', c(\'html_document\'), clean=FALSE)"\n'
        '-->\n'
        '\n'
        '```{r style, echo = FALSE, results = \'asis\'}\n'
        'BiocStyle::markdown()\n'
        'options(width=100, max.print=1000)\n'
        'knitr::opts_chunk$set(\n'
        '    eval=as.logical(Sys.getenv("KNITR_EVAL", "TRUE")),\n'
        '    cache=as.logical(Sys.getenv("KNITR_CACHE", "TRUE")),\n'
        '    warning=FALSE, message=FALSE)\n'
        '```\n'
        '\n'
        '<div style="text-align: right">\n'
        'Source code downloads: &nbsp; &nbsp;\n'
        '[ [.Rmd](https://raw.githubusercontent.com/tgirke/GEN242//main/content/en/tutorials/'
        + tut_name + '/' + output_base + ') ] &nbsp; &nbsp;\n'
        '[ [.R](https://raw.githubusercontent.com/tgirke/GEN242//main/content/en/tutorials/'
        + tut_name + '/' + output_r + ') ]\n'
        '</div>\n'
    )

    new_content = content.replace(old_yaml_block, new_yaml, 1)
    return ask("YAML front matter", content, new_content, interactive)

# ── Step 2: Convert #| options back to inline chunk options ───────────────────

OPTION_MAP_REVERSE = {
    'eval':       'eval',
    'echo':       'echo',
    'message':    'message',
    'warning':    'warning',
    'cache':      'cache',
    'fig-cap':    'fig.cap',
    'fig-width':  'fig.width',
    'fig-height': 'fig.height',
    'fig-align':  'fig.align',
    'out-width':  'out.width',
    'results':    'results',
    'include':    'include',
    'tidy':       'tidy',
    'comment':    'comment',
    'collapse':   'collapse',
}

def convert_chunks(content, interactive):
    lines = content.splitlines(keepends=True)
    new_lines = []
    i = 0
    chunk_open = re.compile(r'^```\{(\w+)(\s+[\w.]+)?\}')

    while i < len(lines):
        line = lines[i]
        m = chunk_open.match(line.rstrip())

        if m:
            engine = m.group(1)
            name   = (m.group(2) or '').strip()

            # Collect #| lines immediately after the header
            pipe_opts = []
            j = i + 1
            while j < len(lines) and lines[j].startswith('#|'):
                pipe_opts.append(lines[j].rstrip())
                j += 1

            # Build inline options
            inline_opts = []
            for opt in pipe_opts:
                om = re.match(r'^#\|\s*([\w-]+):\s*(.+)', opt)
                if om:
                    key = om.group(1).strip()
                    val = om.group(2).strip()
                    rmd_key = OPTION_MAP_REVERSE.get(key, key)
                    val = val.replace('true', 'TRUE').replace('false', 'FALSE')
                    inline_opts.append(rmd_key + '=' + val)

            # bash -> sh
            if engine == 'bash':
                engine = 'sh'

            parts = [engine]
            if name:
                parts.append(name)
            if inline_opts:
                parts.extend(inline_opts)
            new_header = '```{' + ', '.join(parts) + '}\n'

            new_lines.append(new_header)
            i = j  # skip the #| lines
        else:
            new_lines.append(line)
            i += 1

    new_content = ''.join(new_lines)
    return ask("Convert chunk options to inline style", content, new_content, interactive)

# ── Step 3: Convert Quarto figure syntax back to <center><img> ───────────────

def convert_images(content, interactive):
    def replace_fig(m):
        caption = m.group(1)
        src     = m.group(2)
        src = re.sub(r'^images/', '../images/', src)
        result = '<center><img title="' + caption + '" src="' + src + '"/></center>\n'
        if caption:
            result += '<center> ' + caption + '</center>'
        return result

    pattern = re.compile(
        r'!\[([^\]]*)\]\(([^)]+)\)\{[^}]*fig-align[^}]*\}'
    )
    new_content = pattern.sub(replace_fig, content)
    return ask("Convert figure syntax", content, new_content, interactive)

# ── Step 4: Convert **Step N.** labels back to numbered list items ────────────

def convert_step_labels(content, interactive):
    lines = content.splitlines(keepends=True)
    new_lines = []
    i = 0
    step_pat    = re.compile(r'^\*\*Step (\d+)\.\*\*\s+(.*)')
    chunk_open  = re.compile(r'^```\{')
    chunk_close = re.compile(r'^```\s*$')

    while i < len(lines):
        line = lines[i]
        m = step_pat.match(line.rstrip())

        if m:
            num  = m.group(1)
            text = m.group(2)
            new_lines.append(num + '. ' + text + '\n')
            i += 1

            in_chunk = False
            while i < len(lines):
                l = lines[i]
                if not in_chunk and (step_pat.match(l.rstrip()) or re.match(r'^#+\s', l)):
                    break
                if chunk_open.match(l):
                    new_lines.append('    ' + l)
                    in_chunk = True
                elif in_chunk and chunk_close.match(l):
                    new_lines.append('    ' + l)
                    in_chunk = False
                elif in_chunk:
                    new_lines.append('    ' + l)
                elif l.strip() == '':
                    new_lines.append(l)
                else:
                    new_lines.append('   ' + l)
                i += 1
        else:
            new_lines.append(line)
            i += 1

    new_content = ''.join(new_lines)
    return ask("Convert Step labels to numbered list", content, new_content, interactive)

# ── Step 5: Update relative .qmd links back to absolute old-site URLs ─────────

def update_links(content, interactive):
    link_map = {
        '../rbasics/rbasics_index.qmd':              'https://girke.bioinformatics.ucr.edu/GEN242/tutorials/rbasics/rbasics/',
        '../rprogramming/index.qmd':                 'https://girke.bioinformatics.ucr.edu/GEN242/tutorials/rprogramming/rprogramming/',
        '../dplyr/index.qmd':                        'https://girke.bioinformatics.ucr.edu/GEN242/tutorials/dplyr/dplyr/',
        '../linux/index.qmd':                        'https://girke.bioinformatics.ucr.edu/GEN242/tutorials/linux/linux/',
        '../rmarkdown/index.qmd':                    'https://girke.bioinformatics.ucr.edu/GEN242/tutorials/rmarkdown/rmarkdown/',
        '../rgraphics/index.qmd':                    'https://girke.bioinformatics.ucr.edu/GEN242/tutorials/rgraphics/rgraphics/',
        '../../assignments/homework/hw03/index.qmd': 'https://girke.bioinformatics.ucr.edu/GEN242/assignments/homework/hw03/hw03/',
    }
    new_content = content
    for old, new in link_map.items():
        new_content = new_content.replace(old, new)
    return ask("Update internal links", content, new_content, interactive)

# ── Main ──────────────────────────────────────────────────────────────────────

def convert(input_path, output_path, interactive):
    with open(input_path, encoding='utf-8') as f:
        content = f.read()

    original_lines = len(content.splitlines())
    print(f"\nConverting: {input_path} ({original_lines} lines)")
    print(f"Output:     {output_path}")
    print(f"Mode:       {'interactive' if interactive else 'automatic'}\n")

    steps = [
        ("1. YAML front matter",                    lambda c, i: replace_yaml(c, i, output_path)),
        ("2. Convert chunk options to inline style", convert_chunks),
        ("3. Convert figure syntax",                 convert_images),
        ("4. Convert Step labels to numbered list",  convert_step_labels),
        ("5. Update internal links",                 update_links),
    ]

    for label, fn in steps:
        print(f"Step {label}...")
        content = fn(content, interactive)

    with open(output_path, 'w', encoding='utf-8') as f:
        f.write(content)

    final_lines = len(content.splitlines())
    print(f"\nDone. {original_lines} -> {final_lines} lines. Written to {output_path}")

def main():
    args = sys.argv[1:]
    if not args or args[0] in ('-h', '--help'):
        print(__doc__)
        sys.exit(0)

    interactive = '--interactive' in args
    args = [a for a in args if a != '--interactive']

    input_path = args[0]
    if len(args) >= 2:
        output_path = args[1]
    else:
        base = os.path.splitext(os.path.basename(input_path))[0]
        base = re.sub(r'_index$', '', base)
        output_path = base + '.Rmd'

    if not os.path.exists(input_path):
        print(f"Error: {input_path} not found.")
        sys.exit(1)

    convert(input_path, output_path, interactive)

if __name__ == '__main__':
    main()
