# Markdown conformance fixtures

Inputs of `tests/markdown-spec.sh` (the harness is `tests/markdown-spec.qml`). They are vendored unchanged so the run needs no network.

| File | What it is | Licence |
| --- | --- | --- |
| `commonmark-0.31.2-spec.json` | All 652 examples of the CommonMark 0.31.2 spec (`spec.json` from https://spec.commonmark.org/0.31.2/) | CC BY-SA 4.0, copyright John MacFarlane and the CommonMark contributors: https://creativecommons.org/licenses/by-sa/4.0/ |
| `gfm-spec.txt` | The GitHub Flavored Markdown spec 0.29 (cmark-gfm `test/spec.txt`); the harness reads its table, strikethrough, autolink, tagfilter and disabled task list examples | The spec text is CC BY-SA 4.0 (its front matter says so); the cmark-gfm code that carries it is BSD-2-Clause, see below |
| `cmark-gfm-COPYING` | cmark-gfm's `COPYING`: the BSD-2-Clause notice for cmark-gfm and the notices of the code it bundles | as written in the file |

The examples are test data only: nothing here is compiled into Flea, and no example text is shown to a user. Keep both notices if a file is copied elsewhere.

To refresh a file, replace it with the upstream copy of the same version and run `tests/markdown-spec.sh`: a section that drops below its recorded count fails the run, and an example that now draws as the spec's HTML while a rule names it fails as stale.
