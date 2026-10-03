#!/usr/bin/env bash
# Execute each package() into an owned scratch tree and resolve all installed relative ES imports.
set -euo pipefail
cd "$(dirname "$0")/.."
repo=$PWD
box=$(mktemp -d "${TMPDIR:-/tmp}/flea-figure-package.XXXXXX")
trap 'rm -rf -- "$box"' EXIT
for name in root flea flea-git flea-bin; do
    (
        if [ "$name" = root ]; then
            . "$repo/PKGBUILD"
            startdir="$repo"
        else
            . "$repo/packaging/$name/PKGBUILD"
        fi
        printf '%s\n' "${depends[@]}" > "$box/$name.depends"
        printf '%s\n' "${license[@]}" > "$box/$name.licenses"
        srcdir="$box/$name/src"
        pkgdir="$box/$name/pkg"
        CARCH=x86_64
        mkdir -p "$srcdir/target/release"
        printf 'package binary fixture\n' > "$srcdir/target/release/flea"
        case "$name" in
            root|flea) tree="$srcdir/$pkgname-$pkgver" ;;
            flea-git) tree="$srcdir/$pkgname" ;;
            flea-bin) tree="$srcdir/$_pkgname-$pkgver-linux-$CARCH" ;;
        esac
        mkdir -p "$tree"
        for data in ui tools packaging shelf LICENSE; do
            ln -s "$repo/$data" "$tree/$data"
        done
        cp "$srcdir/target/release/flea" "$tree/flea"
        cd "$srcdir"
        package
    )
done
python3 - "$box" "$repo" <<'PY'
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
checks = 0
failures = 0
# Sample inputs: import { renderFigure } from "../js/FigureWorker.mjs"; await import("./math.mjs").
imports = re.compile(r'\b(?:from\s*|import\s*\(\s*|import\s*)["\'](\.[^"\']+)["\']')
for package in ("root", "flea", "flea-git", "flea-bin"):
    checks += 1
    dependencies = (root / f"{package}.depends").read_text().splitlines()
    if dependencies.count("quickjs-ng") != 1:
        failures += 1
        print(f"FAIL {package}: depends must declare quickjs-ng exactly once, matching the other PKGBUILDs")
    ui = root / package / "pkg/usr/share/flea/ui"
    modules = sorted(ui.glob("vendor/*.mjs")) + sorted(ui.glob("js/*.mjs"))
    required = ["js/FigureWorker.mjs", "vendor/figure-helper.mjs", "vendor/math.mjs", "vendor/mermaid.mjs"]
    for relative in required:
        checks += 1
        if not (ui / relative).is_file():
            failures += 1
            print(f"FAIL {package}: missing {relative}")
    checks += 1
    if not list(ui.glob("vendor/LICENSES/*")):
        failures += 1
        print(f"FAIL {package}: missing vendor/LICENSES")
    for module in modules:
        for relative in imports.findall(module.read_text()):
            checks += 1
            target = (module.parent / relative).resolve()
            valid = target.is_relative_to(ui.resolve()) and target.is_file()
            if not valid:
                failures += 1
                print(f"FAIL {package}: {module.relative_to(ui)} imports missing {relative}")
# Sample inputs: `  install -Dm644 ui/js/*.js ui/js/*.mjs -t "$pkgdir/usr/share/flea/ui/js"` in package(); `"$repo"/ui/js/*.mjs` in the tarball script.
repo = pathlib.Path(sys.argv[2])
body = re.search(r'^package\(\) \{\n(.*?)^\}', (repo / "packaging/flea-bin/PKGBUILD").read_text(), re.S | re.M).group(1)
installed = [token for line in body.splitlines() if line.split()[:1] == ["install"]
             for token in line.split()[1:] if not token.startswith(("-", '"$pkgdir'))]
staged = {token.replace('"', "").removeprefix("$repo/")
          for token in (repo / "packaging/flea-bin-tarball").read_text().split() if token.startswith('"$repo')}
checks += 1
if "ui/qmldir" not in installed:
    failures += 1
    print("FAIL flea-bin: no install path could be read from package()")
# The binary is the one path the tarball script stages from its own first argument.
for source in (path for path in installed if path != "flea"):
    checks += 1
    if source not in staged:
        failures += 1
        print(f"FAIL flea-bin: package() installs {source}, which packaging/flea-bin-tarball does not stage")
checks += 1
if (root / "root.licenses").read_text() != (root / "flea.licenses").read_text():
    failures += 1
    print("FAIL root: license identifiers differ from packaging/flea/PKGBUILD")
print(f"figure-package: {checks} check(s), {failures} failed")
sys.exit(bool(failures))
PY
