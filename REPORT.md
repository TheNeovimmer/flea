# stage8 merge 10 (mdfast into the stage), uncommitted, nothing staged by me

Waiting on GM: nothing. Decision for the controller: the two timing flakes below (quicklook-firstframe, preview-hunt) under the 21-suite run.

## Conflicts
- ui/PreviewMarkdown.qml: stage's `figuresArmed` (`shownView`) kept; mdfast's `warmBlocks`, `hasFigures`, `themeProbe`, `warmRequest`, `onWarmRequestChanged` kept (lines 73-97); added `display: true` to the probe (line 86). 566 lines.
- tests/run-all.sh: stage's line plus `figure-warm figure-store` after `markdown-figures-render`.
- tests/markdown-figures.sh: stage's three-path spaced loop plus mdfast's quickjs-only `figure-bytecode` block (lines 167-171).
- tools/flea-file-budget: `ui/PreviewMarkdown.qml 566` (wc -l: stage 542 + 24). AGENTS.md "File budget" paragraph added after the merge-8 record.
- tests/staticgates-unqualified.tsv: stage's side, then tsv-fails.py: quickshell-missing applied 16 (local log), quickshell-present applied 16 (container log). No fallback reason written, no stop.
- Other files merged clean; 0 conflict markers, `git diff --check` 0.

## Probe against placed figure (ui/MarkdownBlockView.qml:120-137 vs ui/PreviewMarkdown.qml:81-95)
bgHex hexOf(Theme.color.background), fgHex inkHex, accentHex, mutedHex, surfaceHex, fontFamily Theme.font.family, bodyPx root.bodyPx (view.preview.* is this pane), display true: identical sources.
Not mirrored on purpose: kind (themeOfKind sets it), source, fallbackColor, inView, askArmed (none enter the theme or key).
Probe armed through `figuresArmed` (`shownView`), same as the placed figures.

## Semantic checks
- figure-store case "the warm query names exactly the keys the placed figures put" (tests/figure-store.qml:165) passes through MarkdownBlockView; no probe fix needed.
- s8md Components vs warm path: figureBlock is the only MarkdownFigure placement for blocks; nested quote/list blocks render no figure, so top-level `warmBlocks` covers every placed block figure. No mdfast hunk sat in a moved Component (its diff touches only the pane and MarkdownFigure).
- blockcost limits unchanged and pass: the probe lives in the pane, not the figure block, so the figure kind gains no object.
- qlopen prepared parse vs warmRequest: both parse paths (worker `landed`, sync/prepared at 379-392) set `blockList` and `appliedSeq`, `blocksReady` gates the warm; quicklook-firstframe and figure-warm pass.
- Note (pre-existing in mdfast, not changed): `landed` writes `appliedSeq` before `blockList`, so a warm may briefly see the old list; the next `warmRequest` change corrects it.

## Gates (logs .superpowers/038-out/s8f-*)
- cargo test --release --locked figure: exit 0, 52 passed 0 failed.
- node tests/figure-worker.mjs: exit 0, 21 checks 0 failed.
- tests/staticgates.sh (local): exit 0, gates=6 PASS. budget tool: exit 0. git diff --check: 0.
- qs-suite, 21 suites: run 1 exit 1, run 2 exit 1; every suite ok except one timing flake each (s8f-gates-run1.log, s8f-gates.log):
  run 1 quicklook-firstframe capped leg ("stage 1 stalled", 60s watchdog) and preview-hunt "text-size chord got=14 expected=16";
  run 2 quicklook-firstframe order leg (step 9, the 1 MB b-big move, 20s watchdog). 
  Reruns: quicklook-firstframe + preview-hunt together exit 0 (9 legs, 30 phases); quicklook-firstframe solo twice more exit 0 (9 legs 0 failed).
  Not verified: whether the stage tip alone shows the same flake under the 21-suite load (no second worktree allowed). The fixtures hold no figure, so the merge adds only three inert bindings there.
- All other suites ok on both runs: staticgates, js, budget, markdown-render/html/blockcost/security/spec/lazy/linearity/memory/nest/figures/figures-render, figure-warm 10, figure-store, figure-package 82, preview-colwork 205, startup-objects 1.
