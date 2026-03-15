#!/usr/bin/env python3
"""
rmd2qmd.py — Convert Hugo/R Markdown .Rmd files to Quarto .qmd format
Usage:
    python3 rmd2qmd.py input.Rmd                                      # auto output name
    python3 rmd2qmd.py input.Rmd output.qmd                           # explicit output name
    python3 rmd2qmd.py input.Rmd --interactive                        # step-by-step review
    python3 rmd2qmd.py input.Rmd output.qmd --interactive             # interactive + explicit
    python3 rmd2qmd.py input.Rmd output.qmd --repo https://github.com/tgirke/GEN242_new

What this script does (content is never changed, only formatting):
    1.  Replace YAML front matter
    2.  Remove compile-from-command-line HTML comment
    3.  Remove BiocStyle::markdown() setup chunk
    4.  Remove Hugo source download <div>
    5.  Convert chunk headers: options move to #| lines inside chunk
    6.  Convert <center><img ...> to Quarto ![](images/...) syntax
    7.  De-indent code chunks inside numbered lists, convert list items to
        bold Step labels (avoids Quarto ::: div wrapping)
    8.  Insert blank lines before code chunks
    9.  Update old site internal links to relative .qmd links
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

# ── Step 1: Replace YAML front matter ────────────────────────────────────────

def replace_yaml(content, interactive, output_path='', repo_url=''):
    yaml_match = re.match(r'^---\n(.*?)\n---\n', content, re.DOTALL)
    if not yaml_match:
        print("  [YAML] WARNING: Could not find YAML front matter.")
        return content

    old_yaml_block = yaml_match.group(0)
    yaml_body      = yaml_match.group(1)

    title_m = re.search(r'^title:\s*["\']?(.+?)["\']?\s*$', yaml_body, re.MULTILINE)
    title   = title_m.group(1).strip() if title_m else "Untitled"
    title   = re.sub(r'^Author:\s*', '', title)

    author_m = re.search(r'^author:\s*["\']?(.+?)["\']?\s*$', yaml_body, re.MULTILINE)
    author   = author_m.group(1).strip() if author_m else "Thomas Girke"
    author   = re.sub(r'^Author:\s*', '', author)

    output_base = os.path.basename(output_path) if output_path else "index.qmd"
    # Build download URLs: raw GitHub URLs if --repo given, else plain filenames
    if repo_url:
        raw_base = repo_url.rstrip('/')
        raw_base = raw_base.replace('https://github.com/', 'https://raw.githubusercontent.com/')
        rel_path = output_path.replace('\\', '/').lstrip('./')
        qmd_url  = raw_base + '/main/' + rel_path
    else:
        qmd_url = output_base

    # Build badge HTML block inserted right after YAML
    badge_block = (
        '\n'
        '<p align="right">\n'
        '  <a href="' + qmd_url + '">\n'
        '    <img src="https://img.shields.io/badge/Download-.qmd-blue?style=for-the-badge&logoColor=white" '
        'alt="Download qmd">\n'
        '  </a>\n'
        '</p>\n'
    )

    new_yaml = (
        '---\n'
        'title: "' + title + '"\n'
        'author: "' + author + '"\n'
        'date: last-modified\n'
        'sidebar: tutorials\n'
        '---\n'
        + badge_block
    )

    new_content = content.replace(old_yaml_block, new_yaml, 1)
    return ask("YAML front matter", content, new_content, interactive)

# ── Step 2: Remove compile comment ───────────────────────────────────────────

def remove_compile_comment(content, interactive):
    pattern = re.compile(r'<!---.*?-->\n?', re.DOTALL)
    new_content = pattern.sub('', content)
    return ask("Remove compile comment", content, new_content, interactive)

# ── Step 3: Remove BiocStyle::markdown() setup chunk ─────────────────────────

def remove_biocstyle(content, interactive):
    pattern = re.compile(
        r'```\{r style.*?\}.*?BiocStyle::markdown\(\).*?```\n?',
        re.DOTALL
    )
    new_content = pattern.sub('', content)
    return ask("Remove BiocStyle chunk", content, new_content, interactive)

# ── Step 4: Remove Hugo source download <div> ────────────────────────────────

def remove_hugo_div(content, interactive):
    pattern = re.compile(
        r'<div style="text-align: right".*?</div>\n?',
        re.DOTALL
    )
    new_content = pattern.sub('', content)
    return ask("Remove Hugo source div", content, new_content, interactive)

# ── Step 5: Convert chunk headers ────────────────────────────────────────────

OPTION_MAP = {
    'eval':       'eval',
    'echo':       'echo',
    'message':    'message',
    'messages':   'message',
    'warning':    'warning',
    'warnings':   'warning',
    'cache':      'cache',
    'fig.cap':    'fig-cap',
    'fig.width':  'fig-width',
    'fig.height': 'fig-height',
    'fig.align':  'fig-align',
    'out.width':  'out-width',
    'results':    'results',
    'include':    'include',
    'tidy':       'tidy',
    'comment':    'comment',
    'collapse':   'collapse',
}

def convert_chunk_header(header_line):
    header_line = re.sub(r'^\s*```\{sh\b', '```{bash', header_line)
    m = re.match(r'^```\{(\w+)\s*([\w.]*)\s*,?\s*(.*?)\}', header_line.strip())
    if not m:
        return header_line, []

    engine  = m.group(1)
    name    = m.group(2).strip()
    options = m.group(3).strip()

    new_header = '```{' + engine + ((' ' + name) if name else '') + '}'
    pipe_lines = []

    if options:
        pairs = re.findall(r'(\w+)\s*=\s*(".*?"|\'.*?\'|[^,]+)', options)
        for key, val in pairs:
            key = key.strip()
            val = val.strip().strip('"').strip("'")
            quarto_key = OPTION_MAP.get(key, key)
            val = val.replace('TRUE', 'true').replace('FALSE', 'false')
            if quarto_key == 'eval' and val == 'true':
                continue
            pipe_lines.append('#| ' + quarto_key + ': ' + val)

    return new_header, pipe_lines

def convert_chunks(content, interactive):
    lines = content.splitlines(keepends=True)
    new_lines = []
    chunk_pattern = re.compile(r'^\s*```\{[rR\w]')

    for line in lines:
        if chunk_pattern.match(line.rstrip()):
            new_header, pipe_lines = convert_chunk_header(line.strip())
            new_lines.append(new_header + '\n')
            for pl in pipe_lines:
                new_lines.append(pl + '\n')
        else:
            new_lines.append(line)

    new_content = ''.join(new_lines)
    return ask("Convert chunk headers", content, new_content, interactive)

# ── Step 6: Convert <center><img ...> to Quarto figure syntax ────────────────

def convert_images(content, interactive):
    def replace_img(m):
        full    = m.group(0)
        title_m = re.search(r'title=["\']([^"\']*)["\']', full)
        src_m   = re.search(r'src=["\']([^"\']*)["\']', full)
        title   = title_m.group(1) if title_m else ""
        src     = src_m.group(1)   if src_m   else ""
        src     = re.sub(r'^.*images/', 'images/', src)
        return '![' + title + '](' + src + '){fig-align="center"}'

    pattern = re.compile(
        r'<center>.*?<img\s[^>]*/?>.*?</center>\s*\n?(?:<center>[^<]*</center>\s*\n?)?',
        re.DOTALL | re.IGNORECASE
    )
    new_content = pattern.sub(replace_img, content)
    return ask("Convert <img> tags", content, new_content, interactive)

# ── Step 7: De-indent code chunks inside numbered lists ──────────────────────

def fix_indented_chunks(content, interactive):
    """
    Numbered list items containing indented code chunks cause Quarto to
    wrap them in ::: divs. This step:
      - Converts "N. Some text" list markers to "**Step N.** Some text"
      - Removes 4-space indentation from code chunks inside those items
    Only affects numbered list items that actually contain indented code chunks.
    """
    lines = content.splitlines(keepends=True)
    new_lines = []
    i = 0

    num_item  = re.compile(r'^(\d+)\.\s+(.*)')
    ind_chunk = re.compile(r'^    ```')

    while i < len(lines):
        line = lines[i]
        m = num_item.match(line)

        if m:
            num  = m.group(1)
            text = m.group(2).rstrip('\n')

            # Look ahead until next numbered item or section header,
            # checking if any indented code chunk exists in this block
            j = i + 1
            has_chunk = False
            while j < len(lines):
                l = lines[j]
                # Stop looking if we hit the next numbered item or header
                if num_item.match(l) or re.match(r'^#+\s', l):
                    break
                if ind_chunk.match(l):
                    has_chunk = True
                    break
                j += 1

            if has_chunk:
                new_lines.append('\n**Step ' + num + '.** ' + text + '\n')
                i += 1
                in_chunk = False
                while i < len(lines):
                    l = lines[i]
                    # Stop at next numbered item or section header (outside chunk)
                    if not in_chunk and (num_item.match(l) or re.match(r'^#+\s', l)):
                        break

                    if ind_chunk.match(l):
                        new_lines.append(l[4:])   # de-indent opening fence
                        in_chunk = True
                    elif in_chunk and l.strip().startswith('```'):
                        new_lines.append('```\n')  # closing fence — always unindented
                        in_chunk = False
                    elif in_chunk:
                        # de-indent body lines (remove up to 4 leading spaces)
                        new_lines.append(l[4:] if l.startswith('    ') else l)
                    else:
                        new_lines.append(l)
                    i += 1
            else:
                new_lines.append(line)
                i += 1
        else:
            new_lines.append(line)
            i += 1

    new_content = ''.join(new_lines)
    return ask("De-indent chunks in numbered lists", content, new_content, interactive)

# ── Step 8: Insert blank lines before code chunks ────────────────────────────

def insert_blank_lines(content, interactive):
    lines = content.splitlines(keepends=True)
    new_lines = []
    for i, line in enumerate(lines):
        if line.startswith('```') and i > 0:
            prev = lines[i-1]
            if (prev.strip() != '' and
                not prev.startswith('```') and
                not prev.startswith('#|') and
                not prev.startswith('---') and
                not prev.startswith(':::') and
                not prev.startswith('!') and
                not prev.startswith('|') and
                not prev.strip().startswith('-') and
                not prev.strip().startswith('*')):
                new_lines.append('\n')
        new_lines.append(line)

    new_content = ''.join(new_lines)
    return ask("Insert blank lines before chunks", content, new_content, interactive)

# ── Step 9: Update internal links ────────────────────────────────────────────

def update_links(content, interactive):
    link_map = {
        'https://girke.bioinformatics.ucr.edu/GEN242/tutorials/rbasics/rbasics/':           '../rbasics/rbasics_index.qmd',
        'https://girke.bioinformatics.ucr.edu/GEN242/tutorials/rprogramming/rprogramming/': '../rprogramming/index.qmd',
        'https://girke.bioinformatics.ucr.edu/GEN242/tutorials/dplyr/dplyr/':               '../dplyr/index.qmd',
        'https://girke.bioinformatics.ucr.edu/GEN242/tutorials/linux/linux/':               '../linux/index.qmd',
        'https://girke.bioinformatics.ucr.edu/GEN242/tutorials/rmarkdown/rmarkdown/':       '../rmarkdown/index.qmd',
        'https://girke.bioinformatics.ucr.edu/GEN242/tutorials/rgraphics/rgraphics/':       '../rgraphics/index.qmd',
        'https://girke.bioinformatics.ucr.edu/GEN242/assignments/homework/hw03/hw03/':      '../../assignments/homework/hw03/index.qmd',
    }
    new_content = content
    for old, new in link_map.items():
        new_content = new_content.replace(old, new)
    return ask("Update internal links", content, new_content, interactive)

# ── Main ──────────────────────────────────────────────────────────────────────

def convert(input_path, output_path, interactive, repo_url=''):
    with open(input_path, encoding='utf-8') as f:
        content = f.read()

    original_lines = len(content.splitlines())
    print(f"\nConverting: {input_path} ({original_lines} lines)")
    print(f"Output:     {output_path}")
    print(f"Mode:       {'interactive' if interactive else 'automatic'}\n")

    steps = [
        ("1. YAML front matter",                 lambda c, i: replace_yaml(c, i, output_path, repo_url)),
        ("2. Remove compile comment",             remove_compile_comment),
        ("3. Remove BiocStyle chunk",             remove_biocstyle),
        ("4. Remove Hugo source div",             remove_hugo_div),
        ("5. De-indent chunks in numbered lists", fix_indented_chunks),
        ("6. Convert chunk headers",              convert_chunks),
        ("7. Convert <img> tags",                 convert_images),
        ("8. Insert blank lines before chunks",   insert_blank_lines),
        ("9. Update internal links",              update_links),
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

    # Parse --repo <url>
    repo_url = ''
    if '--repo' in args:
        idx = args.index('--repo')
        if idx + 1 < len(args):
            repo_url = args[idx + 1]
            args = args[:idx] + args[idx+2:]
        else:
            print('Error: --repo requires a URL argument.')
            sys.exit(1)

    input_path = args[0]
    if len(args) >= 2:
        output_path = args[1]
    else:
        base = os.path.splitext(os.path.basename(input_path))[0].lower()
        output_path = base + '_index.qmd'

    if not os.path.exists(input_path):
        print(f"Error: {input_path} not found.")
        sys.exit(1)

    convert(input_path, output_path, interactive, repo_url)

if __name__ == '__main__':
    main()
