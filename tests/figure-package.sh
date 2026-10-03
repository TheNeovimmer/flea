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
import shlex
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
# Sample input: `install -Dm644 "$repo"/ui/js/*.js "$repo"/ui/js/*.mjs -t "$root/ui/js"` gives (["$repo/ui/js/*.js", "$repo/ui/js/*.mjs"], "$root/ui/js", True).
def install_statements(text):
    statements = []
    for line in re.sub(r"\\\n\s*", " ", text).splitlines():
        if line.split()[:1] != ["install"]:
            continue
        words = shlex.split(line, comments=True)
        sources, destination, directory, args = [], None, False, words[1:]
        while args:
            word = args.pop(0)
            if word == "-t":
                destination, directory = args.pop(0), True
            elif not word.startswith("-"):
                sources.append(word)
        if destination is None:
            destination = sources.pop()
        statements.append((sources, destination, directory))
    return statements

# A path the tarball script stages, relative to its $root: the -t directory plus the source's basename pattern, or the file named last.
def staged_paths(text):
    staged = set()
    for sources, destination, directory in install_statements(text):
        if destination != "$root" and not destination.startswith("$root/"):
            continue
        relative = destination.removeprefix("$root").strip("/")
        if not directory:
            staged.add(relative)
        else:
            staged.update(f"{relative}/{source.rsplit('/', 1)[1]}".lstrip("/") for source in sources if source.startswith("$repo/"))
    return staged

repo = pathlib.Path(sys.argv[2])
body = re.search(r'^package\(\) \{\n(.*?)^\}', (repo / "packaging/flea-bin/PKGBUILD").read_text(), re.S | re.M).group(1)
required = [source for sources, _, _ in install_statements(body) for source in sources]
tarball = (repo / "packaging/flea-bin-tarball").read_text()
checks += 1
if "ui/qmldir" not in required:
    failures += 1
    print("FAIL flea-bin: no install path could be read from package()")
staged = staged_paths(tarball)
# The binary is staged from the script's first argument to $root/flea, so package()'s flea is asserted like any other path.
for source in required:
    checks += 1
    if source not in staged:
        failures += 1
        print(f"FAIL flea-bin: package() installs {source}, which packaging/flea-bin-tarball does not stage there")
# Red controls: a doctored copy of the script text must report exactly the path it broke, and nothing else.
vendor = 'install -Dm644 "$repo"/ui/vendor/*.mjs -t "$root/ui/vendor"'
controls = [
    ("vendor modules staged in ui/js", tarball.replace(vendor, vendor.replace("$root/ui/vendor", "$root/ui/js")), "ui/vendor/*.mjs"),
    ("ui/js/*.mjs token deleted", tarball.replace(' "$repo"/ui/js/*.mjs', "", 1), "ui/js/*.mjs"),
    ("vendor install turned into a comment", tarball.replace(vendor, "# " + vendor), "ui/vendor/*.mjs"),
]
for label, doctored, expected in controls:
    checks += 1
    reported = [source for source in required if source not in staged_paths(doctored)]
    if doctored == tarball or reported != [expected]:
        failures += 1
        print(f"FAIL control {label}: reported {reported}, want only {expected}")
    else:
        print(f"control {label}: reported only {expected}, as a broken script must")
checks += 1
if (root / "root.licenses").read_text() != (root / "flea.licenses").read_text():
    failures += 1
    print("FAIL root: license identifiers differ from packaging/flea/PKGBUILD")
print(f"figure-package: {checks} check(s), {failures} failed")
sys.exit(bool(failures))
PY
