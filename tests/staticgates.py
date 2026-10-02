#!/usr/bin/env python3
# Source-level checks use only the standard library and qmllint's JSON diagnostic IDs.
import argparse
import collections
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import tarfile

GATES = ('conflict-marker', 'fused-line', 'paneprops', 'del-printable', 'qml-undeclared-read')
SUFFIXES = {'.rs', '.qml', '.js', '.sh'}


def inventory(root, tracked=False):
    args = ['git', '-C', str(root), 'ls-files', '-z']
    if not tracked:
        args += ['--cached', '--others', '--exclude-standard']
    result = subprocess.run(args, capture_output=True)
    if result.returncode == 0:
        return sorted(set(p for p in result.stdout.decode().split('\0') if p))
    # The CI lane exports Git's tree to /work/flea and mounts its authoritative tar at /in/tree.tar.
    archive = Path(os.environ.get('FLEA_SOURCE_ARCHIVE', '/in/tree.tar'))
    if not archive.is_file():
        raise ValueError('source inventory requires Git or FLEA_SOURCE_ARCHIVE (CI uses /in/tree.tar)')
    with tarfile.open(archive) as source:
        paths = {member.name for member in source.getmembers() if member.isfile() or member.issym()}
    if any(Path(path).is_absolute() or '..' in Path(path).parts for path in paths):
        raise ValueError('source archive contains a path outside its root')
    return sorted(paths)


def masked(source, suffix):
    # Keep offsets and newlines so diagnostics always point at the original source.
    out = list(source)
    i = 0
    while i < len(source):
        start = i
        raw = re.match(r'r(\#*)"', source[i:]) if suffix == '.rs' else None
        if raw:
            end = source.find('"' + raw[1], i + len(raw[0]))
            i = len(source) if end < 0 else end + 1 + len(raw[1])
        elif source.startswith('//', i) and suffix != '.sh' or source[i] == '#' and suffix == '.sh' and (i == 0 or source[i - 1].isspace()):
            i = source.find('\n', i)
            if i < 0:
                i = len(source)
        elif source.startswith('/*', i) and suffix != '.sh':
            depth = 1
            i += 2
            while i < len(source) and depth:
                if suffix == '.rs' and source.startswith('/*', i):
                    depth += 1
                    i += 2
                elif source.startswith('*/', i):
                    depth -= 1
                    i += 2
                else:
                    i += 1
        elif source[i] in '"\'`' and not (suffix == '.rs' and source[i] == "'" and not re.match(r"'(?:\\.|[^'\\\n])'", source[i:])):
            quote = source[i]
            i += 1
            while i < len(source):
                if source[i] == '\\':
                    i += 2
                elif source[i] == quote:
                    i += 1
                    break
                else:
                    i += 1
        elif source[i] == '/' and suffix in ('.js', '.qml') and re.search(r'(?:^|[=(,:!\[{};?]|\breturn)\s*$', source[:i]):
            # A regex literal is data, including its character classes and escaped slashes.
            i += 1
            bracket = False
            while i < len(source) and source[i] != '\n':
                if source[i] == '\\':
                    i += 2
                elif source[i] == '/' and not bracket:
                    i += 1
                    while i < len(source) and source[i].isalpha():
                        i += 1
                    break
                else:
                    if source[i] == '[':
                        bracket = True
                    elif source[i] == ']':
                        bracket = False
                    i += 1
        else:
            i += 1
            continue
        for at in range(start, min(i, len(source))):
            if source[at] != '\n':
                out[at] = '~'
    text = ''.join(out)
    if suffix == '.sh':
        # Literal heredoc bodies are fixture data or child-script strings, not shell tokens.
        lines = text.splitlines(keepends=True)
        originals = source.splitlines(keepends=True)
        until = None
        for n, line in enumerate(originals):
            if until is not None:
                lines[n] = re.sub(r'[^\n]', '~', line)
                if line.strip() == until:
                    until = None
            else:
                match = re.search(r'<<-?\s*[\'"]?(\w+)[\'"]?', line)
                if match and '<<<' not in line:
                    until = match[1]
        text = ''.join(lines)
    return text


def member_code(source, suffix):
    code = list(masked(source, suffix))
    # Quoted object keys and constant bracket members are declarations/accesses, not string payloads.
    for m in re.finditer(r'([\'"])([A-Za-z_$][\w$]*)\1\s*:', source):
        if re.search(r'[,{]\s*$', ''.join(code[:m.start()])):
            code[m.start():m.start() + len(m[2]) + 2] = ' ' + m[2] + ' '
    for m in re.finditer(r'\b([\w.]+)\[\s*([\'"])([A-Za-z_$][\w$]*)\2\s*\]', source):
        if ''.join(code[m.start():m.start() + len(m[1])]) == m[1]:
            replacement = m[1] + '.' + m[3]
            code[m.start():m.end()] = replacement.ljust(m.end() - m.start())
    return ''.join(code)


def location(file, text, at):
    return f'{file}:{text.count(chr(10), 0, at) + 1}'


def conflict_marker(root, files):
    errors = []
    scanned = 0
    for file in files:
        path = root / file
        if not path.is_file() or path.is_symlink():
            continue
        data = path.read_bytes()
        if b'\0' in data:
            continue
        try:
            source = data.decode('utf-8', errors='replace')
        except UnicodeDecodeError:
            continue
        scanned += 1
        for n, line in enumerate(source.splitlines(), 1):
            if re.fullmatch(r'(?:<<<<<<< .*|=======|>>>>>>> .*|\|\|\|\|\|\|\| .*)', line):
                errors.append(f'{file}:{n}: unresolved conflict marker')
    return scanned, errors


def fused_line(root, files):
    errors = []
    scanned = 0
    for file in files:
        path = root / file
        if path.suffix not in SUFFIXES or not path.is_file():
            continue
        scanned += 1
        code = masked(path.read_text(), path.suffix)
        for m in re.finditer(r'(?<=[^\s~]) {4,}(?=[^\s~])', code):
            errors.append(f'{location(file, code, m.start())}: fused code gap ({len(m[0])} spaces)')
    return scanned, errors


def pane_members(root):
    code = masked((root / 'ui/Pane.qml').read_text(), '.qml')
    depth, depths = 0, []
    for char in code:
        depths.append(depth)
        depth += (char == '{') - (char == '}')
    declarations = r'\bproperty\s+\w+\s+(\w+)\s*:|\b(?:function|signal)\s+(\w+)\s*\('
    members = {m[1] or m[2] for m in re.finditer(declarations, code) if depths[m.start()] == 1}
    # FocusScope inherits Item; these names come from QtQuick's shipped qmltypes, not a hand list.
    qmltypes = Path('/usr/lib/x86_64-linux-gnu/qt6/qml/QtQuick/plugins.qmltypes')
    if not qmltypes.exists():
        qmltypes = Path('/usr/lib/qt6/qml/QtQuick/plugins.qmltypes')
    types = qmltypes.read_text()
    types += (qmltypes.parent.parent / 'builtins.qmltypes').read_text()
    for name in ('QQuickItem', 'QQuickFocusScope', 'QObject'):
        for match in re.finditer(r'Component\s*\{\s*\n\s*file:.*?\n\s*name: "' + name + '"', types):
            start = types.rfind('Component', 0, match.end())
            end = types.find('\n    Component', match.end())
            block = types[start:end if end >= 0 else len(types)]
            members.update(re.findall(r'(?:Property|Method|Signal)\s*\{\s*name: "(\w+)"', block))
    return members


def pane_references(code, file, members):
    refs = set()
    # QML Pane instances and properties are explicit; SettingsPanel's id pane is a SettingsPane.
    refs.update(re.findall(r'(?:Flea\.)?Pane\s*\{\s*id:\s*(\w+)', code))
    refs.update(re.findall(r'property\s+(?:var|Item|Pane)\s+(\w*[Pp]ane)\b', code))
    if file == 'ui/Pane.qml':
        refs.add('root')
    if file.endswith('.js'):
        refs.add('pane')
        # Root/p are conventional JS argument names; distinctive Pane accesses identify their role.
        for ref in set(re.findall(r'\b(\w+)\.(?:filterQuery|focusView|listInFlight|searchMode|selectionVersion|recentMode)\b', code)):
            refs.add(ref)
    refs.update(re.findall(r'\b(?:root\.)?(?:pane|currentPane|primaryPane|railPane|editPane)\b', code))
    for m in re.finditer(r'\b([\w.]+)\.(?:pane|currentPane|primaryPane|railPane|editPane)\b', code):
        refs.add(m[0])
    if file == 'ui/SettingsPanel.qml':
        refs.discard('pane')
    # Aliases retain their Pane role, including member references such as root.pane and holder.pane.
    for _ in range(8):
        before = set(refs)
        for m in re.finditer(r'\b(?:var|let|const)\s+(\w+)\s*=\s*([^\n;]+)', code):
            expression = m[2].split('?', 1)[-1]
            if any(re.search(r'(?<![\w.])' + re.escape(ref) + r'(?![\w.])', expression) for ref in refs):
                if re.fullmatch(r'[\w.\s|&?:]+', m[2].strip()):
                    refs.add(m[1])
        if refs == before:
            break
    return refs


def arguments(code, start, end):
    values = []
    depth = 0
    at = start
    for i in range(start, end):
        if code[i] in '({[':
            depth += 1
        elif code[i] in ')}]':
            depth -= 1
        elif code[i] == ',' and depth == 0:
            values.append(code[at:i].strip())
            at = i + 1
    values.append(code[at:end].strip())
    return values


def pane_flow(root, files, members):
    sources, scopes, imports, functions, calls = {}, {}, {}, {}, []
    for file in files:
        path = root / file
        if path.suffix not in ('.js', '.qml') or not file.startswith(('ui/', 'tests/js/')):
            continue
        source = path.read_text()
        code = member_code(source, path.suffix)
        sources[file] = code
        imports[file] = {alias: str((path.parent / name).resolve().relative_to(root))
                         for name, alias in re.findall(r'import\s+"([^"\n]+\.js)"\s+as\s+(\w+)', source)}
        top = {'start': 0, 'end': len(code), 'params': [], 'refs': set(), 'returns': False}
        if path.suffix == '.qml':
            top['refs'] = pane_references(code, file, members)
        scopes[file] = [top]
        for m in re.finditer(r'\bfunction\s*(\w*)\s*\(([^)]*)\)\s*(?::\s*\w+\s*)?\{', code):
            end = closing(code, m.end() - 1, '{', '}')
            scope = {'start': m.end(), 'end': end, 'params': [a.strip().split(':')[0] for a in m[2].split(',')],
                     'refs': set(), 'returns': False}
            scopes[file].append(scope)
            if m[1]:
                functions[(file, m[1])] = scope
        for scope in scopes[file]:
            if scope is top:
                continue
            body = list(code[scope['start']:scope['end']])
            for child in scopes[file]:
                if scope['start'] < child['start'] < child['end'] < scope['end']:
                    body[child['start'] - scope['start']:child['end'] - scope['start']] = '~' * (child['end'] - child['start'])
            body = ''.join(body)
            scope['body'] = body
            scope['refs'] = pane_references(body, file, members)
            scope['refs'] = {ref for ref in scope['refs'] if ref in scope['params'] or re.search(r'(?<![\w.])' + re.escape(ref) + r'(?!\w)', body)}
            scope['returns'] = bool(re.search(r'\breturn\s+(' + '|'.join(re.escape(r) for r in scope['refs']) + r')\s*(?:;|$)', body)) if scope['refs'] else False
            scope['returns'] |= bool(re.search(r'\breturn\s*\{', body) and stub_objects(body))
            if re.search(r'function\s+(?:\w*[Pp]ane\w*|root)\s*\(', code[max(0, scope['start'] - 100):scope['start']]):
                returned = re.search(r'\breturn\s+(\w+)\s*$', body)
                if returned:
                    scope['returns'] = True
                    scope['refs'].add(returned[1])
        for m in re.finditer(r'\b(\w+)(?:\.(\w+))?\s*\(', code):
            if re.search(r'function\s*$', code[:m.start()]):
                continue
            target = (imports[file].get(m[1]), m[2]) if m[2] else (file, m[1])
            end = closing(code, m.end() - 1, '(', ')')
            assignment = re.search(r'\b(?:var|let|const)\s+(\w+)\s*=\s*$', code[:m.start()])
            calls.append((file, m.start(), target, arguments(code, m.end(), end), assignment[1] if assignment else None))

    def at(file, offset):
        candidates = [scope for scope in scopes[file] if scope['start'] <= offset <= scope['end']]
        return min(candidates, key=lambda scope: scope['end'] - scope['start'])

    def references(file, offset):
        result = set()
        for scope in sorted(scopes[file], key=lambda scope: scope['start']):
            if scope['start'] <= offset <= scope['end']:
                result.difference_update(scope['params'])
                result.update(scope['refs'])
        return result

    # Pane roles flow through scoped function arguments and factory results, never through child objects.
    for _ in range(len(sources)):
        changed = False
        for file, offset, target, values, assignment in calls:
            if target not in functions:
                continue
            local = at(file, offset)
            dest = functions[target]
            known = references(file, offset)
            if assignment and dest['returns'] and assignment not in local['refs']:
                local['refs'].add(assignment)
                changed = True
            for value, parameter in zip(values, dest['params']):
                if value in ('null', 'undefined', 'true', 'false') or not re.fullmatch(r'[A-Za-z_$][\w$]*(?:\.[A-Za-z_$][\w$]*)*', value):
                    continue
                if value in known and parameter not in dest['refs'] and not (file.startswith('tests/') and target[0].startswith('ui/')):
                    dest['refs'].add(parameter)
                    changed = True
                if parameter in dest['refs'] and value not in known:
                    local['refs'].add(value)
                    changed = True
        for file, entries in scopes.items():
            for scope in entries[1:]:
                known = references(file, scope['start'])
                for m in re.finditer(r'\b(?:var|let|const)\s+(\w+)\s*=\s*([\w.]+)\s*(?:;|$)', scope['body'], re.MULTILINE):
                    if m[2] in known and m[1] not in scope['refs']:
                        scope['refs'].add(m[1])
                        changed = True
        if not changed:
            break
    return sources, references


def paneprops(root, files, sample=False):
    members = pane_members(root)
    errors = []
    scanned = 0
    allowances = {} if sample else stub_allowances()
    used = set()
    sources, references = pane_flow(root, files, members)
    for file in files:
        path = root / file
        if path.suffix not in ('.js', '.qml') or not file.startswith(('ui/', 'tests/js/')):
            continue
        scanned += 1
        code = sources[file]
        for m in re.finditer(r'\b([\w.]+)\.(\w+)\s*(?:=(?!=)|\+=|-=|\*=|/=|\+\+|--)', code):
            if m[1] not in references(file, m.start()) or m[2] in members:
                continue
            key = (file, m[2])
            if key in allowances and file.startswith('tests/js/'):
                used.add(key)
            else:
                errors.append(f'{location(file, code, m.start())}: {m[1]}.{m[2]} absent from Pane/FocusScope')
        if file.startswith('tests/js/'):
            # Object-literal fields in Pane factories count even when production only reads them.
            for start, end in stub_objects(code):
                for field, at in literal_fields(code, start, end):
                    if field in members:
                        continue
                    key = (file, field)
                    if key in allowances:
                        used.add(key)
                    else:
                        errors.append(f'{location(file, code, at)}: stub field {field} absent from Pane/FocusScope')
    for key in allowances.keys() - used:
        errors.append(f'{key[0]}: stale stub instrumentation allowance {key[1]}')
    return scanned, sorted(set(errors))


def literal_fields(code, start, end):
    depth = 0
    previous = '{'
    for m in re.finditer(r'[{}(),?:]|[A-Za-z_$][\w$]*|[^\s~]', code[start:end]):
        token = m[0]
        if depth == 0 and previous in ('{', ',') and re.fullmatch(r'[A-Za-z_$][\w$]*', token):
            if re.match(r'\s*:', code[start + m.end():end]):
                yield token, start + m.start()
        if token in '{(':
            depth += 1
        elif token in '})':
            depth -= 1
        if depth == 0:
            previous = token


def stub_objects(code):
    spans, owners = [], []
    for m in re.finditer(r'function\s*(\w*)\s*\([^)]*\)\s*\{', code):
        owners.append((m.end(), closing(code, m.end() - 1, '{', '}'), m[1]))
    for m in re.finditer(r'\{', code):
        prefix = code[:m.start()]
        if not re.search(r'(?:=|return|\(|,)\s*$', prefix):
            continue
        end = closing(code, m.start(), '{', '}')
        fields = {name for name, _ in literal_fields(code, m.end(), end)}
        containing = [owner for owner in owners if owner[0] <= m.start() < owner[1]]
        owner = min(containing, key=lambda entry: entry[1] - entry[0]) if containing else None
        factory = owner and re.search(r'[Pp]ane|^root$', owner[2]) and re.search(r'(?:return|\b(?:var|let|const)\s+\w+\s*=)\s*$', prefix)
        if factory or len(fields & {'cursorIndex', 'focusView', 'filterQuery', 'searchMode', 'listInFlight', 'recentMode', 'rowFor', 'pendingSelect'}) >= 2:
            spans.append((m.end(), end))
    return spans


def closing(code, start, left, right):
    depth = 0
    for i in range(start, len(code)):
        if code[i] == left:
            depth += 1
        elif code[i] == right:
            depth -= 1
            if depth == 0:
                return i
    return len(code)


def stub_allowances():
    # Only test observation fields belong here; production Pane writes can never use this list.
    return {
        ('tests/js/columns.js', 'refreshed'): 'Records refresh calls through stub methods.',
        ('tests/js/columns.js', 'said'): 'Records messages emitted by the stub message signal.',
        ('tests/js/columns.js', 'sent'): 'Records backend requests emitted by stub methods.',
        ('tests/js/columns.js', 'stuck'): 'Records the window offset held by a stub backend.',
        ('tests/js/ddtarget.js', 'askLog'): 'Records request rows and menu identities.',
        ('tests/js/ddtarget.js', 'asked'): 'Records request calls through stub methods.',
        ('tests/js/ddtarget.js', 'moved'): 'Records setCursor calls through stub methods.',
        ('tests/js/ddtarget.js', 'openedPath'): 'Records the path requested through open.',
        ('tests/js/ddtarget.js', 'sent'): 'Records backend requests emitted by stub methods.',
        ('tests/js/filter-cursor.js', 'said'): 'Records stub message emissions.',
        ('tests/js/filter-cursor.js', 'trashed'): 'Records backend.trash calls.',
        ('tests/js/filterfixture.js', 'contexts'): 'Records showRow or pointer dispatch context arguments.',
        ('tests/js/filterfixture.js', 'picked'): 'Stores the stub selection behind selection methods.',
        ('tests/js/filterfixture.js', 'scrolled'): 'Records the row requested through showRow.',
        ('tests/js/focus-forward.js', 'rowsRead'): 'Records rowFor inputs.',
        ('tests/js/focus-forward.js', 'said'): 'Records messages emitted by the stub message signal.',
        ('tests/js/focus-lines.js', 'picked'): 'Stores the stub selection behind selection methods.',
        ('tests/js/focus-lines.js', 'said'): 'Records messages emitted by the stub message signal.',
        ('tests/js/focus-lines.js', 'walked'): 'Records backend.search calls through stub methods.',
        ('tests/js/focus.js', 'acted'): 'Records act calls through stub methods.',
        ('tests/js/focus.js', 'asked'): 'Records request calls through stub methods.',
        ('tests/js/focus.js', 'cancelled'): 'Records cancel calls through stub methods.',
        ('tests/js/focus.js', 'climbed'): 'Records openParent calls through stub methods.',
        ('tests/js/focus.js', 'copied'): 'Records copy calls through stub methods.',
        ('tests/js/focus.js', 'hiddenAsked'): 'Records ejectHidden calls.',
        ('tests/js/focus.js', 'isError'): 'Records the error argument of the stub message signal.',
        ('tests/js/focus.js', 'linked'): 'Records pasteLink calls.',
        ('tests/js/focus.js', 'listed'): 'Records openWithoutHistory arguments.',
        ('tests/js/focus.js', 'made'): 'Records backend.mkdir calls through stub methods.',
        ('tests/js/focus.js', 'openedCopyAs'): 'Records openCopyAsFlyout calls.',
        ('tests/js/focus.js', 'openedPasteAs'): 'Records openPasteAsFlyout calls.',
        ('tests/js/focus.js', 'pasted'): 'Records paste calls through stub methods.',
        ('tests/js/focus.js', 'retreated'): 'Records escapePressed calls through stub methods.',
        ('tests/js/focus.js', 'said'): 'Records messages emitted by the stub message signal.',
        ('tests/js/focus.js', 'started'): 'Records start calls through stub methods.',
        ('tests/js/foldersorts.js', 'forgotten'): 'Records backend.forgetSort calls.',
        ('tests/js/foldersorts.js', 'remembered'): 'Records backend.rememberSort calls.',
        ('tests/js/foldersorts.js', 'sent'): 'Records requests from stub backend methods.',
        ('tests/js/foldersorts.js', 'sorts'): 'Records backend.sort calls.',
        ('tests/js/marquee.js', 'contexts'): 'Records showRow or pointer dispatch context arguments.',
        ('tests/js/menu.js', 'said'): 'Records stub message emissions.',
        ('tests/js/nav.js', 'cancelled'): 'Records cancel calls through stub methods.',
        ('tests/js/nav.js', 'cleared'): 'Records clearSelection calls through stub methods.',
        ('tests/js/nav.js', 'refuses'): 'Injects a refusal in the stub backend.list method.',
        ('tests/js/nav.js', 'said'): 'Records messages emitted by the stub message signal.',
        ('tests/js/nav.js', 'sent'): 'Records backend requests emitted by stub methods.',
        ('tests/js/ops.js', 'asked'): 'Records request calls through stub methods.',
        ('tests/js/ops.js', 'permitted'): 'Records requested permission-dialog arguments.',
        ('tests/js/ops.js', 'said'): 'Records messages emitted by the stub message signal.',
        ('tests/js/ops.js', 'seen'): 'Records captured stub method arguments.',
        ('tests/js/pathbar.js', 'asked'): 'Records request calls through stub methods.',
        ('tests/js/placemenu.js', 'copied'): 'Records copy calls through stub methods.',
        ('tests/js/placemenu.js', 'said'): 'Records messages emitted by the stub message signal.',
        ('tests/js/placemenu.js', 'tabbed'): 'Records openNewTab calls.',
        ('tests/js/placemenu.js', 'terminal'): 'Records openTerminal arguments.',
        ('tests/js/previewkeys.js', 'closed'): 'Records preview.close calls through stub methods.',
        ('tests/js/previewkeys.js', 'played'): 'Records preview.play calls through stub methods.',
        ('tests/js/previewkeys.js', 'switched'): 'Records preview switch calls through stub methods.',
        ('tests/js/railkeys.js', 'said'): 'Records messages emitted by the stub message signal.',
        ('tests/js/recentmode.js', 'cancelled'): 'Records cancel calls through stub methods.',
        ('tests/js/recentmode.js', 'holds'): 'Records swap.hold requests.',
        ('tests/js/recentmode.js', 'listed'): 'Records list or open requests.',
        ('tests/js/recentmode.js', 'said'): 'Records messages emitted by the stub message signal.',
        ('tests/js/reclick.js', 'said'): 'Records messages emitted by the stub message signal.',
        ('tests/js/reclick.js', 'sent'): 'Records backend requests emitted by stub methods.',
        ('tests/js/reload.js', 'asked'): 'Records request calls through stub methods.',
        ('tests/js/reload.js', 'listed'): 'Records list or open requests.',
        ('tests/js/reload.js', 'refreshed'): 'Records refresh calls through stub methods.',
        ('tests/js/reload.js', 'said'): 'Records messages emitted by the stub message signal.',
        ('tests/js/reload.js', 'windowed'): 'Records requested backend windows.',
        ('tests/js/search.js', 'relisted'): 'Records openWithoutHistory inputs.',
        ('tests/js/search.js', 'sent'): 'Records backend requests emitted by stub methods.',
        ('tests/js/slowclick.js', 'cancelled'): 'Records cancel calls through stub methods.',
        ('tests/js/slowclick.js', 'did'): 'Records dispatch calls through stub methods.',
        ('tests/js/slowclick.js', 'picked'): 'Stores the stub selection behind selection methods.',
        ('tests/js/sort.js', 'cleared'): 'Records clearSelection calls through stub methods.',
        ('tests/js/sort.js', 'committed'): 'Records commitRename calls through stub methods.',
        ('tests/js/sort.js', 'cursor'): 'Records setCursor inputs, separate from runtime cursorIndex.',
        ('tests/js/sort.js', 'remembered'): 'Records backend.rememberSort requests.',
        ('tests/js/sort.js', 'said'): 'Records messages emitted by the stub message signal.',
        ('tests/js/sort.js', 'sent'): 'Records backend requests emitted by stub methods.',
        ('tests/js/status.js', 'picked'): 'Stores fixture selection behind selectedIndices.',
        ('tests/js/status.js', 'said'): 'Records stub message emissions.',
        ('tests/js/status.js', 'stampAtSay'): 'Records the trash stamp at the time the message signal fires.',
        ('tests/js/status.js', 'trashedIdx'): 'Records indices passed to backend.trash.',
        ('tests/js/swap.js', 'acted'): 'Records act calls through stub methods.',
        ('tests/js/swap.js', 'asked'): 'Records request calls through stub methods.',
        ('tests/js/swap.js', 'cleared'): 'Records clearSelection calls through stub methods.',
        ('tests/js/swap.js', 'dropped'): 'Records swap.drop calls.',
        ('tests/js/swap.js', 'droppedOut'): 'Records listInFlight at swap.drop time.',
        ('tests/js/swap.js', 'holds'): 'Records swap.hold requests.',
        ('tests/js/swap.js', 'said'): 'Records messages emitted by the stub message signal.',
        ('tests/js/swap.js', 'sent'): 'Records backend requests emitted by stub methods.',
        ('tests/js/tabrestore.js', 'land'): 'Records the callback used by pending tab restoration.',
        ('tests/js/tabs-switch.js', 'listed'): 'Records list or open requests.',
        ('tests/js/tabs-switch.js', 'preferenceHidden'): 'Simulates external ViewState.hidden in the stub listing.',
        ('tests/js/tabs-switch.js', 'sorted'): 'Records backend.sort calls.',
        ('tests/js/tabsfixture.js', 'clearedAtOnce'): 'Records openWithoutHistory clearAtOnce options.',
        ('tests/js/tabsfixture.js', 'listed'): 'Records list or open requests.',
        ('tests/js/tabsfixture.js', 'preferenceHidden'): 'Simulates the external ViewState.hidden preference during a stub listing.',
        ('tests/js/tabsfixture.js', 'said'): 'Records messages emitted by the stub message signal.',
        ('tests/js/tabsfixture.js', 'sorted'): 'Records backend.sort inputs.',
        ('tests/js/tabsfixture.js', 'windows'): 'Records backend.window inputs.',
        ('tests/js/tap.js', 'cancelled'): 'Records cancel calls through stub methods.',
        ('tests/js/tap.js', 'contexts'): 'Records showRow or pointer dispatch context arguments.',
        ('tests/js/tap.js', 'cursor'): 'Records setCursor inputs, separate from runtime cursorIndex.',
        ('tests/js/tap.js', 'did'): 'Records dispatch calls through stub methods.',
        ('tests/js/tap.js', 'picked'): 'Stores the stub selection behind selection methods.',
        ('tests/js/trash.js', 'said'): 'Records messages emitted by the stub message signal.',
        ('tests/js/trash.js', 'trashedIdx'): 'Records indices passed to backend.trash.',
        ('tests/js/watch.js', 'cleared'): 'Records clearSelection calls through stub methods.',
        ('tests/js/watch.js', 'contexts'): 'Records showRow or pointer dispatch context arguments.',
        ('tests/js/watch.js', 'cursorSetTo'): 'Records setCursor calls.',
        ('tests/js/watch.js', 'said'): 'Records messages emitted by the stub message signal.',
        ('tests/js/watch.js', 'selectedAt'): 'Records indices requested through selectOnly.',
        ('tests/js/watch.js', 'sent'): 'Records backend requests emitted by stub methods.',
        ('tests/js/watch.js', 'want'): 'Supplies a fixture-only selection sequence read by the stub selectedIndices method.',
    }


def del_printable(root, files):
    errors = []
    scanned = 0
    for file in files:
        path = root / file
        if path.suffix not in ('.qml', '.js') or not file.startswith('ui/'):
            continue
        scanned += 1
        source = path.read_text()
        code = masked(source, path.suffix)
        aliases = {'event.text'}
        for _ in range(8):
            before = set(aliases)
            for m in re.finditer(r'\b(?:var|let|const)\s+(\w+)\s*=\s*([\w.]+)\b', code):
                if m[2] in aliases:
                    aliases.add(m[1])
            if aliases == before:
                break
        for alias in aliases:
            pattern = r'\b' + re.escape(alias) + r'(?:\.length\s*(?:===?|!==?|>=|<=|>|<)|\.(?:charCodeAt|codePointAt)\s*\(|\s*(?:>=|<=|>|<)(?!=))'
            for m in re.finditer(pattern, code):
                errors.append(f'{location(file, code, m.start())}: printable event.text decision bypasses Input.isPrintable')
        if 'Input.isPrintable' in code:
            imports = re.findall(r'import\s+"([^"\n]+)"\s+as\s+Input\b', source)
            if not any((path.parent / name).resolve() == root / 'ui/js/Input.js' for name in imports):
                errors.append(f'{file}: Input.isPrintable does not import the shared Input.js')
        for m in re.finditer(r'\b(?:[\w.]*\.)?isPrintable\s*\(\s*event\.text', code):
            if not m[0].startswith('Input.isPrintable'):
                errors.append(f'{location(file, code, m.start())}: printable decision uses a second helper')
    return scanned, sorted(set(errors))


def qml_undeclared_read(root, files, sample=False):
    qml = [f for f in files if f.startswith('ui/') and f.endswith('.qml')]
    binary = os.environ.get('FLEA_QMLLINT', '/usr/lib/qt6/bin/qmllint')
    if not Path(binary).is_file() or not os.access(binary, os.X_OK):
        return len(qml), [f'qmllint unavailable: {binary}']
    with tempfile.TemporaryDirectory(prefix='staticgates-qmllint-') as scratch:
        out = Path(scratch) / 'diagnostics.json'
        result = subprocess.run([binary, '--json', str(out), *qml], cwd=root, capture_output=True, text=True, timeout=120)
        if not out.exists():
            return len(qml), [f'qmllint returned {result.returncode} without JSON: {result.stderr[:200]}']
        try:
            data = json.loads(out.read_text())
            reported = {str((root / f['filename']).resolve().relative_to(root)) for f in data['files']}
        except (ValueError, KeyError) as error:
            return len(qml), [f'qmllint returned invalid JSON: {error}']
        if reported != set(qml):
            return len(qml), ['qmllint did not report every requested file']
        current = collections.Counter()
        for file in data['files']:
            path = (root / file['filename']).resolve()
            lines = path.read_text().splitlines()
            for warning in file.get('warnings', []):
                if warning['id'] == 'unqualified':
                    n, column, size = warning['line'], warning['column'], warning['length']
                    name = lines[n - 1][column - 1:column - 1 + size]
                    current[(str(path.relative_to(root)), n, name)] += 1
        baseline = collections.Counter()
        if not sample:
            missing = any(w['id'] == 'import' and w['message'].startswith('Failed to import Quickshell.')
                          for file in data['files'] for w in file.get('warnings', []))
            profile = 'quickshell-missing' if missing else 'quickshell-present'
            active = False
            found = False
            for line in (root / 'tests/staticgates-unqualified.tsv').read_text().splitlines():
                if line.startswith('# profile '):
                    active = line == '# profile ' + profile
                    found |= active
                    continue
                if not line or line.startswith('#') or not active:
                    continue
                file, n, name, reason = line.split('\t', 3)
                if not reason.strip():
                    return len(qml), ['unqualified baseline entry lacks a reason']
                baseline[(file, int(n), name)] += 1
            if not found:
                return len(qml), [f'no unqualified baseline for import profile {profile}']
        errors = [f'{f}:{n}: new unqualified read {name}' for f, n, name in (current - baseline).elements()]
        errors += [f'{f}:{n}: stale unqualified allowance {name}' for f, n, name in (baseline - current).elements()]
        return len(qml), errors


CHECKS = dict(zip(GATES, (conflict_marker, fused_line, paneprops, del_printable, qml_undeclared_read)))


def negative_controls(root):
    samples = {
        'conflict-marker': ('sample.txt', '<<<<<<< left\n'),
        'fused-line': ('sample.js', 'function broken() {    run() }\n'),
        'paneprops': ('ui/js/Sample.js', 'function broken(pane) { pane.removedProperty = true }\n'),
        'del-printable': ('ui/js/Sample.js', 'function key(event) { return event.text.length === 1 && event.text >= " " }\n'),
        'qml-undeclared-read': ('ui/Sample.qml', 'import QtQuick\nItem { function readRecent() { return asker } }\n'),
    }
    errors = []
    script = root / 'tests/staticgates.py'
    with tempfile.TemporaryDirectory(prefix='staticgates-controls-') as scratch:
        for gate, (file, text) in samples.items():
            sample = Path(scratch) / gate
            path = sample / file
            path.parent.mkdir(parents=True)
            path.write_text(text)
            if gate == 'paneprops':
                (sample / 'ui/Pane.qml').write_text('import QtQuick\nFocusScope { property int cursorIndex: 0 }\n')
            result = subprocess.run([sys.executable, str(script), '--gate', gate, '--sample', str(sample)], capture_output=True, text=True)
            diagnostic = next((line for line in result.stdout.splitlines() if line.startswith(f'STATICGATE {gate} FAIL ')), '')
            expected = {'conflict-marker': 'unresolved conflict marker', 'fused-line': 'fused code gap',
                        'paneprops': 'pane.removedProperty absent', 'del-printable': 'printable event.text decision',
                        'qml-undeclared-read': 'new unqualified read asker'}[gate]
            if result.returncode != 1 or expected not in diagnostic or 'STATICGATES FAIL gates=1' not in result.stdout:
                errors.append(f'{gate}: planted defect was not rejected: {result.stdout} {result.stderr}')
            else:
                print(f'STATICGATE {gate} RED exit=1 diagnostic={diagnostic}')
    return errors


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--gate', choices=GATES)
    parser.add_argument('--root', type=Path, default=Path.cwd())
    parser.add_argument('--sample', type=Path, help=argparse.SUPPRESS)
    args = parser.parse_args()
    root = (args.sample or args.root).resolve()
    try:
        files = sorted(str(p.relative_to(root)) for p in root.rglob('*') if p.is_file()) if args.sample else inventory(root)
    except (OSError, ValueError, tarfile.TarError) as error:
        print(f'STATICGATE inventory FAIL {error}')
        print('STATICGATES FAIL gates=5')
        return 1
    controls = [] if args.gate or args.sample else negative_controls(root)
    for error in controls:
        print(f'STATICGATE negative-control FAIL {error}')
    failed = len(controls)
    for name in ((args.gate,) if args.gate else GATES):
        selected = inventory(root, tracked=True) if name == 'conflict-marker' and not args.sample else files
        try:
            kwargs = {'sample': True} if args.sample and name in ('paneprops', 'qml-undeclared-read') else {}
            count, errors = CHECKS[name](root, selected, **kwargs)
        except (OSError, ValueError, subprocess.SubprocessError) as error:
            count, errors = 0, [str(error)]
        for error in errors:
            print(f'STATICGATE {name} FAIL {error}')
        if not errors:
            print(f'STATICGATE {name} PASS files={count}')
        failed += bool(errors)
    print(f'STATICGATES {"FAIL" if failed else "PASS"} gates={1 if args.gate else len(GATES)}')
    return int(bool(failed))


if __name__ == '__main__':
    raise SystemExit(main())
