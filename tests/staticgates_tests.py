#!/usr/bin/env python3
# Regression checks exercise the static gates without changing the real tree.
import ast
import contextlib
import inspect
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile
import unittest
from unittest import mock

import staticgates as gates

# A function expression stays indented here; the column-0 house style keeps column 0 for declarations.
DUPDECL_FIXTURES = {
    'F1-opacity': ('ui/A.qml', 'Item { Behavior on opacity { property int value: 0; property int value: 1 } }\n', 'Duplicate property name'),
    'F1-x': ('ui/A.qml', 'Item { Behavior on x { property int wire: 0; property int wire: 1 } }\n', 'Duplicate property name'),
    'F2-increment': ('ui/A.js', 'function wire() {}\nvar counter = 0\ncounter++\nfunction wire() {}\n', 'wire declared again (first at 1)'),
    'F2-decrement': ('ui/A.js', 'function wire() {}\nvar counter = 0\ncounter--\nfunction wire() {}\n', 'wire declared again (first at 1)'),
    'F3-object-division': ('ui/A.qml', 'Item {\nfunction first() { var x = {} / 2; } function wire() { return /x/; }\nfunction wire() {}\n}\n', 'Duplicate method name'),
    'F3-template-return': ('ui/A.qml', 'Item {\nproperty int wire: 0\nproperty string text: `${({return:10}).return / 2}/s`\nproperty int wire: 1\n}\n', 'Duplicate property name'),
    'F3-ratio-return': ('ui/Ratio.js', 'function wire() {}\nvar ratio = ({return: 4}).return / 2;\nfunction wire() {}', 'wire declared again (first at 1)'),
    'F4-binding-return': ('ui/A.qml', 'Item {\nproperty int wire: 0\nproperty var result: ({return:10}).return\nproperty int wire: 1\n}\n', 'Duplicate property name'),
    'F5-void': ('ui/Plain.js', 'function wire() {}\nvoid\n    function wire() {}()\n', None),
    'F5-typeof': ('ui/Plain.js', 'function wire() {}\nvar type = typeof\n    function wire() {}\n', None),
}


# The qmllint command places its JSON output before the requested source paths.
QMLLINT_JSON_ARGUMENT = 2
QMLLINT_FIRST_FILE_ARGUMENT = 3


class StaticGateTests(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory(prefix='staticgates-tests-')
        self.addCleanup(self.scratch.cleanup)
        self.root = Path(self.scratch.name)

    def write(self, file, source):
        path = self.root / file
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(source)
        return path

    def syntax(self, function):
        # Sample input: for _ in range(ALIAS_FIXPOINT_CAP): pass
        return ast.parse(inspect.getsource(function))

    @contextlib.contextmanager
    def qmllint(self):
        def run(command, **kwargs):
            data = {'files': [{'filename': file, 'warnings': []} for file in command[QMLLINT_FIRST_FILE_ARGUMENT:]]}
            Path(command[QMLLINT_JSON_ARGUMENT]).write_text(json.dumps(data))
            return subprocess.CompletedProcess(command, 0, stdout='', stderr='')

        with mock.patch.dict(os.environ, {'FLEA_QMLLINT': sys.executable}):
            with mock.patch.object(gates.subprocess, 'run', side_effect=run) as called:
                yield called

    def test_F3_alias_caps_are_named(self):
        for function in (gates.pane_references, gates.del_printable):
            with self.subTest(function=function.__name__):
                ranges = [node for node in ast.walk(self.syntax(function))
                          if isinstance(node, ast.Call) and isinstance(node.func, ast.Name)
                          and node.func.id == 'range']
                self.assertEqual(len(ranges), 1)
                self.assertIsInstance(ranges[0].args[0], ast.Name, 'alias cap is a bare literal')
                self.assertEqual(ranges[0].args[0].id, 'ALIAS_FIXPOINT_CAP')
                self.assertEqual(gates.ALIAS_FIXPOINT_CAP, 8)

    def test_F3_qmllint_timeout_is_named(self):
        keywords = [node for node in ast.walk(self.syntax(gates.qml_undeclared_read))
                    if isinstance(node, ast.keyword) and node.arg == 'timeout']
        self.assertEqual(len(keywords), 1)
        self.assertIsInstance(keywords[0].value, ast.Name, 'qmllint timeout is a bare literal')
        self.assertEqual(keywords[0].value.id, 'QMLLINT_TIMEOUT_SECONDS')
        self.assertEqual(gates.QMLLINT_TIMEOUT_SECONDS, 120)

    def test_F3_stderr_excerpt_is_named(self):
        slices = [node for node in ast.walk(self.syntax(gates.qml_undeclared_read))
                  if isinstance(node, ast.Subscript) and isinstance(node.value, ast.Attribute)
                  and node.value.attr == 'stderr']
        self.assertEqual(len(slices), 1)
        self.assertIsInstance(slices[0].slice.upper, ast.Name, 'stderr excerpt is a bare literal')
        self.assertEqual(slices[0].slice.upper.id, 'STDERR_EXCERPT_LENGTH')
        self.assertEqual(gates.STDERR_EXCERPT_LENGTH, 200)

    def test_F5_archive_inventory_without_git(self):
        archive = self.root / 'tree.tar'
        with tarfile.open(archive, 'w') as source:
            member = tarfile.TarInfo('sample.txt')
            source.addfile(member, io.BytesIO())
        empty_path = self.root / 'empty-path'
        empty_path.mkdir()
        program = ('import json, sys; from pathlib import Path; '
                   'sys.path.insert(0, sys.argv[1]); from staticgates import inventory; '
                   'print(json.dumps(inventory(Path(sys.argv[2]))))')
        result = subprocess.run([sys.executable, '-B', '-c', program, str(Path(gates.__file__).parent), str(self.root)],
                                env={**os.environ, 'PATH': str(empty_path), 'FLEA_SOURCE_ARCHIVE': str(archive)},
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), '["sample.txt"]')

    def test_F8_shell_single_quote_closes_after_literal_backslash(self):
        source = "printf 'a\\' ; x    y\n"
        file = self.write('sample.sh', source)
        syntax = subprocess.run(['/bin/bash', '-n', str(file)], capture_output=True, text=True)
        self.assertEqual(syntax.returncode, 0, syntax.stderr)
        self.assertEqual(gates.fused_line(self.root, ['sample.sh']),
                         (1, ['sample.sh:1: fused code gap (4 spaces)']))

    def test_F8_other_quotes_keep_escape_handling(self):
        for suffix, source in (('.sh', 'printf "a\\"    b" ; x    y\n'),
                               ('.sh', 'printf `a\\`    b` ; x    y\n'),
                               ('.js', "var text = 'a\\'    b'; x    y\n")):
            with self.subTest(suffix=suffix, source=source):
                file = 'control' + suffix
                self.write(file, source)
                self.assertEqual(gates.fused_line(self.root, [file]),
                                 (1, [f'{file}:1: fused code gap (4 spaces)']))

    def test_F10_parsers_have_sample_input_comments(self):
        lines = inspect.getsource(gates.qml_undeclared_read).splitlines()
        for parser in ('json.loads(', "line.split('\\t', 3)"):
            with self.subTest(parser=parser):
                index = next(i for i, line in enumerate(lines) if parser in line)
                self.assertIn('# Sample input:', lines[index - 1])

    def test_worker_announce_allows_only_the_counted_worker(self):
        self.write('ui/Bare.qml', 'Item { WorkerScript { source: "W.js" } }\n')
        self.write('ui/Said.qml', 'WorkerScript {\n    // WORKER_STARTED\n    Component.onCompleted: console.info(log, "WORKER_STARTED " + source)\n}\n')
        self.write('ui/Prose.qml', 'Item { // a WorkerScript { here\n    property string s: "WorkerScript {"\n}\n')
        self.write('ui/Named.qml', 'Item { CountedWorker { source: "W.js" } }\n')
        self.write('ui/CountedWorker.qml', 'WorkerScript {\n    Component.onCompleted: console.info(startLog, "WORKER_STARTED " + source)\n}\n')
        files = ['ui/Bare.qml', 'ui/Said.qml', 'ui/Prose.qml', 'ui/Named.qml', 'ui/CountedWorker.qml']
        self.assertEqual(gates.worker_announce(self.root, files),
                         (5, ['ui/Bare.qml:1: WorkerScript outside ui/CountedWorker.qml', 'ui/Said.qml:1: WorkerScript outside ui/CountedWorker.qml']))
        missing = 'ui/CountedWorker.qml:1: no console.info(startLog, "WORKER_STARTED " ...) call in code'
        for body in ('WorkerScript {\n}\n', 'WorkerScript {\n    // console.info(startLog, "WORKER_STARTED " + source)\n}\n',
                     'WorkerScript {\n    Component.onCompleted: console.info(startLog, "started " + source)\n}\n'):
            with self.subTest(body=body):
                self.write('ui/CountedWorker.qml', body)
                self.assertEqual(gates.worker_announce(self.root, ['ui/CountedWorker.qml']), (1, [missing]))
        self.write('ui/CountedWorker.qml', 'WorkerScript {\n    function a() { console.info(startLog, "other") }\n    Component.onCompleted: console.info(startLog, "WORKER_STARTED " + source)\n}\n')
        self.assertEqual(gates.worker_announce(self.root, ['ui/CountedWorker.qml']), (1, []))

    def test_F10_malformed_tsv_names_file_and_line(self):
        self.write('ui/A.qml', 'import QtQuick\nItem {}\n')
        for row in ('ui/A.qml\t1\tmissing_reason',
                    'ui/A.qml\tnot-a-number\tasker\tDeclared QML id.',
                    'ui/A.qml\t1\tasker\t'):
            with self.subTest(row=row):
                self.write('tests/staticgates-unqualified.tsv', '# profile quickshell-present\n' + row + '\n')
                output = io.StringIO()
                with self.qmllint(), mock.patch.object(sys, 'argv', ['staticgates.py', '--gate',
                                        'qml-undeclared-read', '--root', str(self.root)]):
                    with mock.patch.object(gates, 'inventory', return_value=['ui/A.qml']):
                        with contextlib.redirect_stdout(output):
                            result = gates.main()
                self.assertEqual(result, 1)
                self.assertIn('tests/staticgates-unqualified.tsv:2:', output.getvalue())

    def test_watch_mark_observer_is_scoped_and_must_be_used(self):
        self.write('tests/js/watch.js', 'function pane() { var p = {cursorIndex: 0}; p.marked = []; return p }\n')
        self.write('ui/js/Live.js', 'function run(pane) { pane.marked = [] }\n')
        key = ('tests/js/watch.js', 'marked')
        with (mock.patch.object(gates, 'pane_members', return_value={'cursorIndex'}),
              mock.patch.object(gates, 'stub_allowances', return_value={key: gates.stub_allowances()[key]})):
            self.assertEqual(gates.paneprops(self.root, ['tests/js/watch.js']), (1, []))
            count, errors = gates.paneprops(self.root, ['tests/js/watch.js', 'ui/js/Live.js'])
            self.assertEqual(count, 2)
            self.assertEqual(errors, ['ui/js/Live.js:1: pane.marked absent from Pane/FocusScope'])
            self.write('tests/js/watch.js', 'function pane() { return {cursorIndex: 0} }\n')
            self.assertEqual(gates.paneprops(self.root, ['tests/js/watch.js']),
                             (1, ['tests/js/watch.js: stale stub instrumentation allowance marked']))

    def test_F11_pane_flow_skips_missing_inventory_entry(self):
        self.write('ui/js/Live.js', 'function run(pane) { pane.cursorIndex = 0 }\n')
        sources, _ = gates.pane_flow(self.root, ['ui/js/Old.js', 'ui/js/Live.js'], {'cursorIndex'})
        self.assertEqual(set(sources), {'ui/js/Live.js'})

    def test_F11_paneprops_skips_missing_inventory_entry_and_checks_live_file(self):
        self.write('ui/js/Live.js', 'function run(pane) { pane.removedProperty = true }\n')
        with mock.patch.object(gates, 'pane_members', return_value={'cursorIndex'}):
            count, errors = gates.paneprops(self.root, ['ui/js/Old.js', 'ui/js/Live.js'], sample=True)
        self.assertEqual(count, 1)
        self.assertEqual(errors, ['ui/js/Live.js:1: pane.removedProperty absent from Pane/FocusScope'])

    def test_F11_del_printable_skips_missing_inventory_entry_and_checks_live_file(self):
        self.write('ui/js/Live.js', 'function key(event) { return event.text.length === 1 }\n')
        self.assertEqual(gates.del_printable(self.root, ['ui/js/Old.js', 'ui/js/Live.js']),
                         (1, ['ui/js/Live.js:1: printable event.text decision bypasses Input.isPrintable']))

    def test_F11_paneprops_skips_allowances_for_missing_test_files(self):
        with mock.patch.object(gates, 'pane_members', return_value={'cursorIndex'}):
            with mock.patch.object(gates, 'stub_allowances', return_value={('tests/js/Old.js', 'said'): 'Records messages.'}):
                self.assertEqual(gates.paneprops(self.root, ['tests/js/Old.js']), (0, []))

    def test_F11_qmllint_skips_missing_inventory_entry_and_allowance(self):
        self.write('ui/A.qml', 'import QtQuick\nItem {}\n')
        self.write('tests/staticgates-unqualified.tsv', '# profile quickshell-present\n'
                   'ui/Old.qml\t1\tasker\tDeclared QML id.\n')
        with self.qmllint() as called:
            self.assertEqual(gates.qml_undeclared_read(self.root, ['ui/Old.qml', 'ui/A.qml']), (1, []))
        self.assertEqual(called.call_args.args[0][QMLLINT_FIRST_FILE_ARGUMENT:], ['ui/A.qml'])

    def test_F11_qmllint_skips_inventory_with_only_missing_files(self):
        with mock.patch.dict(os.environ, {'FLEA_QMLLINT': str(self.root / 'unavailable')}):
            self.assertEqual(gates.qml_undeclared_read(self.root, ['ui/Old.qml'], sample=True), (0, []))

    def test_F12_markdown_setext_heading_passes(self):
        self.write('README.md', 'Install\n=======\n')
        self.assertEqual(gates.conflict_marker(self.root, ['README.md']), (1, []))

    def test_F12_conflict_separator_inside_span_is_rejected(self):
        self.write('README.md', '<<<<<<< left\nInstall\n=======\nSetup\n>>>>>>> right\n')
        self.assertEqual(gates.conflict_marker(self.root, ['README.md']),
                         (1, [f'README.md:{line}: unresolved conflict marker' for line in (1, 3, 5)]))

    def test_F12_separator_requires_complete_span_in_same_file(self):
        self.write('left.txt', '<<<<<<< left\n=======\n')
        self.write('README.md', 'Install\n=======\n>>>>>>> right\n')
        self.assertEqual(gates.conflict_marker(self.root, ['left.txt', 'README.md']),
                         (2, ['left.txt:1: unresolved conflict marker', 'README.md:3: unresolved conflict marker']))

    def test_F13_shell_ansi_c_and_plain_single_quotes(self):
        for source in ("printf $'it\\'s'; x    y\n", "printf 'a\\' ; x    y\n"):
            with self.subTest(source=source):
                file = self.write('sample.sh', source)
                syntax = subprocess.run(['/bin/bash', '-n', str(file)], capture_output=True, text=True)
                self.assertEqual(syntax.returncode, 0, syntax.stderr)
                self.assertEqual(gates.fused_line(self.root, ['sample.sh']),
                                 (1, ['sample.sh:1: fused code gap (4 spaces)']))

    def test_F14_shell_unquoted_escapes_do_not_hide_code(self):
        for source in (r"printf \$'a\' ; x    y", r"echo \' ; x    y",
                       r"printf \\$'it\'s'; x    y", r"printf \\\$'a\' ; x    y"):
            with self.subTest(source=source):
                file = self.write('sample.sh', source + '\n')
                syntax = subprocess.run(['/bin/bash', '-n', str(file)], capture_output=True, text=True)
                self.assertEqual(syntax.returncode, 0, syntax.stderr)
                self.assertEqual(gates.fused_line(self.root, ['sample.sh']),
                                 (1, ['sample.sh:1: fused code gap (4 spaces)']))

    def test_F15_shell_non_heredoc_openers_do_not_hide_code(self):
        for opener in ('echo "<<EOF"', '# <<EOF', '(( a << 2 ))', 'x=$(( a << 2 ))', 'cat <<<EOF'):
            with self.subTest(opener=opener):
                file = self.write('sample.sh', opener + '\nx    y\n')
                syntax = subprocess.run(['/bin/bash', '-n', str(file)], capture_output=True, text=True)
                self.assertEqual(syntax.returncode, 0, syntax.stderr)
                self.assertEqual(gates.fused_line(self.root, ['sample.sh']),
                                 (1, ['sample.sh:2: fused code gap (4 spaces)']))

    def test_F15_shell_nested_and_multiline_arithmetic_keeps_code_visible(self):
        for arithmetic in ('(( (a + 1) << 2 ))', 'x=$(( (a + 1) << 2 ))',
                           '((\n a << 2\n))', 'x=$((\n a << 2\n))'):
            with self.subTest(arithmetic=arithmetic):
                source = arithmetic + '\nx    y\n'
                file = self.write('sample.sh', source)
                syntax = subprocess.run(['/bin/bash', '-n', str(file)], capture_output=True, text=True)
                self.assertEqual(syntax.returncode, 0, syntax.stderr)
                self.assertEqual(gates.fused_line(self.root, ['sample.sh']),
                                 (1, [f'sample.sh:{source.count(chr(10))}: fused code gap (4 spaces)']))

    def test_F15_shell_real_heredoc_masks_only_its_body(self):
        for opener in ('cat <<EOF', "cat <<'EOF'", 'cat <<"EOF"', 'cat <<-EOF', "cat <<<EOF <<'EOF'",
                       "(( a << 2 )); cat <<'EOF'"):
            with self.subTest(opener=opener):
                file = self.write('sample.sh', opener + '\nx    y\nEOF\nx    y\n')
                syntax = subprocess.run(['/bin/bash', '-n', str(file)], capture_output=True, text=True)
                self.assertEqual(syntax.returncode, 0, syntax.stderr)
                self.assertEqual(gates.fused_line(self.root, ['sample.sh']),
                                 (1, ['sample.sh:4: fused code gap (4 spaces)']))

    def assert_qml_rejected(self, file, source, diagnostic):
        self.write(file, source)
        count, errors = gates.qml_duplicate_member(self.root, [file])
        self.assertEqual(count, 1)
        self.assertEqual(len(errors), 1, errors)
        self.assertIn(diagnostic, errors[0])
        self.assertTrue(errors[0].startswith(file + ':'), errors)
        # Sample input: ui/A.qml:4:18: error: Duplicate property name
        self.assertRegex(errors[0], r':\d+:\d+: error: ')

    def test_duplicate_member_review_fixtures(self):
        for name, (file, source, diagnostic) in DUPDECL_FIXTURES.items():
            with self.subTest(fixture=name):
                self.write(file, source)
                count, errors = gates.qml_duplicate_member(self.root, [file])
                self.assertEqual(count, 1)
                if diagnostic is None:
                    self.assertEqual(errors, [])
                else:
                    self.assertEqual(len(errors), 1, errors)
                    self.assertIn(diagnostic, errors[0])
                    self.assertTrue(errors[0].startswith(file + ':'), errors)

    def test_duplicate_member_historical_pane(self):
        fixture = Path(__file__).with_name('staticgates-pane-338b343f.qml.txt')
        self.assert_qml_rejected('ui/Pane.qml', fixture.read_text(), 'Duplicate alias name')

    def test_duplicate_member_qt_declaration_kinds_and_ids(self):
        declarations = {
            'property int value: 0': 'Duplicate property name',
            'readonly property int value: 0': 'Duplicate property name',
            'default property list<QtObject> value': 'Duplicate property name',
            'required property int value': 'Duplicate property name',
            'property alias value: root.width': 'Duplicate alias name',
            'signal value()': 'Duplicate signal name',
            'function value() {}': 'Duplicate method name',
            'id: root': 'Property value set multiple times',
        }
        for declaration, diagnostic in declarations.items():
            with self.subTest(declaration=declaration):
                self.assert_qml_rejected('tests/Decl.qml',
                                         'QtObject {\n' + declaration + '\n' + declaration + '\n}\n', diagnostic)

    def test_duplicate_member_qt_sibling_and_nested_scopes_pass(self):
        self.write('ui/A.qml', 'Item { property int value: 0; function run() {}\n'
                   'QtObject { id: first; property int value: 1; signal done(); function run() {} }\n'
                   'QtObject { id: second; property int value: 2; signal done(); function run() {} }\n}\n')
        self.assertEqual(gates.qml_duplicate_member(self.root, ['ui/A.qml']), (1, []))

    def test_duplicate_member_qt_bound_and_inline_objects_are_checked(self):
        sources = ('QQ.Item { property QtObject child: QQ.QtObject { property int value: 0; property int value: 1 } }',
                   'Item { data: [QtObject { property int value: 0; property int value: 1 }] }',
                   'Item { component Inner: QtObject { property int value: 0; property int value: 1 } }')
        for source in sources:
            with self.subTest(source=source):
                self.assert_qml_rejected('ui/A.qml', source, 'Duplicate property name')

    def test_duplicate_member_qt_does_not_resolve_imports(self):
        self.write('ui/A.qml', 'import Absent.Module\nItem { property int value: 0 }\n')
        self.assertEqual(gates.qml_duplicate_member(self.root, ['ui/A.qml']), (1, []))
        self.assert_qml_rejected('ui/A.qml', 'import Absent.Module\n'
                                 'Item { property int value: 0; property int value: 1 }\n', 'Duplicate property name')

    def test_duplicate_member_js_declaration_kinds_and_names(self):
        for declaration in ('function value$() {}', 'var $value = 0', 'let _value = 0', 'const value1 = 0'):
            with self.subTest(declaration=declaration):
                name = declaration.split()[1].split('(')[0]
                self.write('ui/A.js', declaration + '\n' + declaration + '\n')
                self.assertEqual(gates.qml_duplicate_member(self.root, ['ui/A.js']),
                                 (1, [f'ui/A.js:2: {name} declared again (first at 1)']))
        self.write('ui/A.js', 'function wire() {}\nvar wire = 0\n')
        self.assertEqual(gates.qml_duplicate_member(self.root, ['ui/A.js']),
                         (1, ['ui/A.js:2: wire declared again (first at 1)']))

    def test_duplicate_member_js_plain_and_pragma_library(self):
        for pragma in ('', '.pragma library\n'):
            with self.subTest(pragma=pragma):
                self.write('ui/js/Twin.js', pragma + 'function wire() {}\nfunction wire() {}\n')
                first = 2 if pragma else 1
                self.assertEqual(gates.qml_duplicate_member(self.root, ['ui/js/Twin.js']),
                                 (1, [f'ui/js/Twin.js:{first + 1}: wire declared again (first at {first})']))

    def test_duplicate_member_js_nested_and_expression_names_pass(self):
        source = ('function wire() { function wire() {}; return {wire: 1} }\n'
                  'var one = function wire() {}\nvar two =\n    function wire() {}\n'
                  'var object = {wire: function wire() {}}\n'
                  'if (true) { function wire() {} }\n')
        self.write('ui/Plain.js', source)
        self.assertEqual(gates.qml_duplicate_member(self.root, ['ui/Plain.js']), (1, []))
        self.write('ui/Plain.js', source + 'function wire() {}\n')
        self.assertEqual(gates.qml_duplicate_member(self.root, ['ui/Plain.js']),
                         (1, ['ui/Plain.js:7: wire declared again (first at 1)']))

    def test_duplicate_member_qmlcachegen_override_and_fallback(self):
        with mock.patch.dict(os.environ, {'FLEA_QMLCACHEGEN': sys.executable}):
            self.assertEqual(gates.qmlcachegen_binary(), sys.executable)
        with mock.patch.dict(os.environ, {'FLEA_QMLCACHEGEN': str(self.root / 'missing')}):
            with mock.patch.object(gates, 'QMLCACHEGEN_PATHS', (sys.executable,)):
                with self.assertRaisesRegex(ValueError, 'FLEA_QMLCACHEGEN is not an executable file: ' + str(self.root / 'missing')):
                    gates.qmlcachegen_binary()
        self.write('ui/plain.txt', 'not a compiler\n')
        with mock.patch.dict(os.environ, {'FLEA_QMLCACHEGEN': str(self.root / 'ui/plain.txt')}):
            with mock.patch.object(gates, 'QMLCACHEGEN_PATHS', (sys.executable,)):
                with self.assertRaisesRegex(ValueError, 'not an executable file'):
                    gates.qmlcachegen_binary()
        env = {k: v for k, v in os.environ.items() if k != 'FLEA_QMLCACHEGEN'}
        with mock.patch.dict(os.environ, env, clear=True):
            with mock.patch.object(gates, 'QMLCACHEGEN_PATHS', (str(self.root / 'absent'), sys.executable)):
                self.assertEqual(gates.qmlcachegen_binary(), sys.executable)

    def test_duplicate_member_missing_qmlcachegen_is_loud(self):
        override = str(self.root / 'override')
        fallback = str(self.root / 'fallback')
        env = {k: v for k, v in os.environ.items() if k != 'FLEA_QMLCACHEGEN'}
        with mock.patch.dict(os.environ, env, clear=True):
            with mock.patch.object(gates, 'QMLCACHEGEN_PATHS', (override, fallback)):
                with self.assertRaisesRegex(ValueError, 'qmlcachegen unavailable; tried: ' + override + ', ' + fallback):
                    gates.compile_qml(self.root, ['ui/A.qml'])
        self.assertEqual(gates.compile_qml(self.root, []), [])

    def test_duplicate_member_reports_each_compiler_error_line(self):
        self.write('ui/A.qml', 'Item {}\n')
        stderr = 'Error compiling qml file: ui/A.qml:4:18: error: Duplicate property name\nui/A.qml:6:18: error: Duplicate property name\n'
        with mock.patch.object(gates.subprocess, 'run', return_value=subprocess.CompletedProcess([], 1, '', stderr)):
            self.assertEqual(gates.compile_qml(self.root, ['ui/A.qml']),
                             ['ui/A.qml:4:18: error: Duplicate property name', 'ui/A.qml:6:18: error: Duplicate property name'])

    def test_duplicate_member_compiler_timeout_and_artifact_are_checked(self):
        self.write('ui/A.qml', 'Item {}\n')
        with mock.patch.object(gates.subprocess, 'run', side_effect=subprocess.TimeoutExpired('qmlcachegen', gates.QMLCACHEGEN_TIMEOUT_SECONDS)) as called:
            with self.assertRaises(subprocess.TimeoutExpired):
                gates.compile_qml(self.root, ['ui/A.qml'])
        self.assertEqual(called.call_args.kwargs['timeout'], gates.QMLCACHEGEN_TIMEOUT_SECONDS)
        with mock.patch.object(gates.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0, '', '')):
            self.assertEqual(gates.compile_qml(self.root, ['ui/A.qml']),
                             ['ui/A.qml: qmlcachegen returned success without bytecode'])

    def test_duplicate_member_filters_paths_and_skips_missing_files(self):
        files = ('ui/A.qml', 'tests/nested/A.qml', 'ui/js/A.js', 'ui/Plain.js',
                 'tests/js/A.js', 'elsewhere/A.qml', 'ui/A.txt')
        for file in files:
            self.write(file, 'Item { property int value: 0; property int value: 1 }\n'
                       if file.endswith('.qml') else 'function value() {}\nfunction value() {}\n')
        count, errors = gates.qml_duplicate_member(self.root, ['ui/Missing.qml', *files])
        self.assertEqual(count, 4)
        self.assertEqual({error.split(':')[0] for error in errors}, set(files[:4]))

    def test_duplicate_member_cli_uses_tracked_inventory_and_qt_diagnostic(self):
        self.write('ui/Pane.qml', 'Item {\nproperty alias wire: root.width\nproperty alias wire: root.width\n}\n')
        output = io.StringIO()
        with mock.patch.object(sys, 'argv', ['staticgates.py', '--gate', 'qml-duplicate-member',
                                            '--root', str(self.root)]):
            with mock.patch.object(gates, 'inventory', return_value=['ui/Pane.qml']) as inventory:
                with contextlib.redirect_stdout(output):
                    result = gates.main()
        self.assertEqual(result, 1)
        inventory.assert_any_call(self.root, tracked=True)
        self.assertIn('STATICGATE qml-duplicate-member FAIL ui/Pane.qml:3:', output.getvalue())
        self.assertIn('Duplicate alias name\nSTATICGATES FAIL gates=1\n', output.getvalue())


if __name__ == '__main__':
    unittest.main(verbosity=2)
