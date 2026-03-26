#!/usr/bin/env python3
"""
check_packages.py — Find all R packages used in .qmd/.Rmd files and check
which ones are missing from .github/workflows/publish.yml

Detects packages from:
  - library(pkg) / require(pkg) calls
  - pkg::function() and pkg:::function() namespace calls
  - BiocManager::install() and install.packages() calls in tutorial text

Usage:
    python3 scripts/check_packages.py          # check tutorials only
    python3 scripts/check_packages.py --all    # include slides and assignments

Run from repo root.
"""

import re
import os
import glob
import sys

# Base R packages and placeholder names that don't need installing
IGNORE = {
    "base", "utils", "stats", "methods", "graphics", "grDevices",
    "datasets", "tools", "compiler", "grid", "parallel",
    "R", "r", "pkg", "pkg1", "pkg2", "my_library",
    "my_library1", "my_library2",
}

def extract_packages(chunk_content):
    packages = set()

    # library(pkg), library("pkg"), library('pkg')
    lib_pat = re.compile(
        r'(?:library|require)\s*\(\s*["\']?([A-Za-z][A-Za-z0-9._]*)["\']?\s*\)'
    )
    packages.update(lib_pat.findall(chunk_content))

    # pkg::function() and pkg:::function()
    ns_pat = re.compile(r'\b([A-Za-z][A-Za-z0-9._]*):{2,3}[A-Za-z_.]')
    packages.update(ns_pat.findall(chunk_content))

    # BiocManager::install(c("pkg1", "pkg2")) and install.packages(c(...))
    inst_pat = re.compile(
        r'(?:BiocManager::install|install\.packages)\s*\(\s*c\s*\((.*?)\)',
        re.DOTALL
    )
    for match in inst_pat.findall(chunk_content):
        packages.update(re.findall(r'["\']([A-Za-z][A-Za-z0-9._]*)["\']', match))

    return packages - IGNORE

def main():
    check_all = '--all' in sys.argv

    patterns = ["tutorials/**/*.qmd", "tutorials/**/*.Rmd"]
    if check_all:
        patterns += ["slides/**/*.qmd", "assignments/**/*.qmd"]

    source_files = sorted(set(
        f for p in patterns for f in glob.glob(p, recursive=True)
    ))

    if not source_files:
        print("No files found. Run from repo root.")
        sys.exit(1)

    found_packages = set()
    pkg_sources = {}
    pkg_how = {}

    for filepath in source_files:
        with open(filepath, encoding='utf-8', errors='ignore') as f:
            content = f.read()

        # Extract only code chunk content
        chunks = re.findall(r'```\{[rR][^}]*\}(.*?)```', content, re.DOTALL)
        chunk_content = '\n'.join(chunks)

        pkgs = extract_packages(chunk_content)
        fname = os.path.basename(filepath)

        for pkg in pkgs:
            found_packages.add(pkg)
            pkg_sources.setdefault(pkg, set()).add(fname)
            if re.search(r'(?:library|require)\s*\(\s*["\']?' + re.escape(pkg), chunk_content):
                pkg_how.setdefault(pkg, set()).add('library()')
            if re.search(re.escape(pkg) + r':{2,3}', chunk_content):
                pkg_how.setdefault(pkg, set()).add('pkg::')

    try:
        with open(".github/workflows/publish.yml") as f:
            workflow = f.read()
    except FileNotFoundError:
        print("publish.yml not found. Run from repo root.")
        sys.exit(1)

    installed = set(re.findall(r'"([A-Za-z][A-Za-z0-9._]*)"', workflow)) - IGNORE
    missing = found_packages - installed

    print(f"\nFiles scanned:               {len(source_files)}")
    print(f"Packages found in tutorials: {len(found_packages)}")
    print(f"Already in publish.yml:      {len(found_packages & installed)}")
    print(f"Missing from publish.yml:    {len(missing)}")

    if missing:
        print("\n===== MISSING PACKAGES =====")
        print(f"  {'Package':<35} {'How used':<20} Files")
        print("  " + "-" * 75)
        for pkg in sorted(missing):
            how   = ", ".join(sorted(pkg_how.get(pkg, {"?"})))
            files = ", ".join(sorted(pkg_sources.get(pkg, set())))
            print(f"  {pkg:<35} {how:<20} {files}")

        print("\n===== PASTE INTO publish.yml =====")
        for pkg in sorted(missing):
            print(f'              "{pkg}",')
    else:
        print("\n===== ALL PACKAGES PRESENT IN publish.yml =====")
    print()

if __name__ == '__main__':
    main()
