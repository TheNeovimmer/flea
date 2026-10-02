#!/bin/bash
# Rebuilds ui/vendor/math.mjs and ui/vendor/mermaid.mjs from the pinned npm
# packages byte for byte. Needs npm and network once (npm ci), so the
# controller runs this, not the bounded unit: this lane has neither.
set -u
cd "$(dirname "$0")" || exit 1

[ -f package.json ] || { echo "vendor-js: no package.json beside this script"; exit 1; }
npm ci || exit 1

# One exact command per bundle. Flags: --bundle (single file), --format=esm
# (the helper imports it), --platform=neutral (no node shims; the helper
# runs under quickjs-ng, not node), --target=es2017 (the pinned build target),
# --minify (the shipped files are minified). Entry files name the export
# surface: texToSvg(source, display) and mermaidToSvg(source, bg, fg).
npx esbuild math-entry.mjs --bundle --format=esm --platform=neutral --target=es2017 --minify --outfile=math-bundle.mjs || exit 1
npx esbuild mermaid-entry.mjs --bundle --format=esm --platform=neutral --target=es2017 --minify --outfile=mermaid-bundle.mjs || exit 1

# The proof is byte equality, not eyeballing: a flag drift changes bytes.
cmp math-bundle.mjs ../ui/vendor/math.mjs || { echo "vendor-js: math.mjs differs, copy the rebuilt file over ui/vendor/math.mjs"; exit 1; }
cmp mermaid-bundle.mjs ../ui/vendor/mermaid.mjs || { echo "vendor-js: mermaid.mjs differs, copy the rebuilt file over ui/vendor/mermaid.mjs"; exit 1; }
echo "vendor-js: both bundles reproduce byte for byte"
