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
        result = subprocess.run([sys.executable, '-c', program, str(Path(gates.__file__).parent), str(self.root)],
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

    def test_duplicate_member_pane_alias_reports_both_lines(self):
        self.write('ui/Pane.qml', 'import QtQuick\nFocusScope {\n'
                   '    readonly property alias wire: wire\n'
                   '    readonly property alias wire: wire\n}\n')
        self.assertEqual(gates.qml_duplicate_member(self.root, ['ui/Pane.qml']),
                         (1, ['ui/Pane.qml:4: wire declared again (first at 3)']))

    def test_duplicate_member_all_declaration_kinds(self):
        declarations = ('property int value: 0', 'readonly property int value: 0',
                        'default property list<QtObject> value', 'required property int value',
                        'required readonly property int value', 'property alias value: root.width',
                        'signal value()', 'signal value', 'function value() {}', 'id: root')
        for declaration in declarations:
            with self.subTest(declaration=declaration):
                self.write('tests/Decl.qml', 'QtObject {\n' + declaration + '\n' + declaration + '\n}\n')
                name = 'id' if declaration.startswith('id:') else 'value'
                self.assertEqual(gates.qml_duplicate_member(self.root, ['tests/Decl.qml']),
                                 (1, [f'tests/Decl.qml:3: {name} declared again (first at 2)']))

    def test_duplicate_member_cross_kind_collision(self):
        self.write('ui/A.qml', 'Item {\nproperty int value: 0\nsignal value()\nfunction value() {}\n}\n')
        self.assertEqual(gates.qml_duplicate_member(self.root, ['ui/A.qml']),
                         (1, ['ui/A.qml:3: value declared again (first at 2)',
                              'ui/A.qml:4: value declared again (first at 2)']))

    def test_duplicate_member_identifier_names_are_not_truncated(self):
        for name in ('value$', '$value', '_value', 'value1'):
            with self.subTest(name=name):
                self.write('ui/Names.qml', f'Item {{\nproperty int {name}: 0\nproperty int {name}: 1\n}}\n')
                self.write('ui/Names.js', f'function {name}() {{}}\nfunction {name}() {{}}\n')
                self.assertEqual(gates.qml_duplicate_member(self.root, ['ui/Names.qml', 'ui/Names.js']),
                                 (2, [f'ui/Names.qml:3: {name} declared again (first at 2)',
                                      f'ui/Names.js:2: {name} declared again (first at 1)']))

    def test_duplicate_member_id_attribute_cannot_be_assigned_twice(self):
        self.write('ui/Ids.qml', 'QtObject { id: first; id: second }\n')
        self.assertEqual(gates.qml_duplicate_member(self.root, ['ui/Ids.qml']),
                         (1, ['ui/Ids.qml:1: id declared again (first at 1)']))

    def test_duplicate_member_sibling_objects_pass(self):
        self.write('tests/Siblings.qml', 'Item {\n'
                   'QtObject { id: first; property int value: 0; signal done(); function run() {} }\n'
                   'QtObject { id: second; property int value: 0; signal done(); function run() {} }\n}\n')
        self.assertEqual(gates.qml_duplicate_member(self.root, ['tests/Siblings.qml']), (1, []))

    def test_duplicate_member_nested_object_can_redeclare_parent(self):
        self.write('ui/Nested.qml', 'Item { id: root; property int value: 0; function run() {}\n'
                   'QtObject { id: child; property int value: 1; function run() {} }\n}\n')
        self.assertEqual(gates.qml_duplicate_member(self.root, ['ui/Nested.qml']), (1, []))
        self.write('ui/Nested.qml', 'Item { property int value: 0\n'
                   'QtObject { property int value: 1 }\nproperty int value: 2\n}\n')
        self.assertEqual(gates.qml_duplicate_member(self.root, ['ui/Nested.qml']),
                         (1, ['ui/Nested.qml:3: value declared again (first at 1)']))

    def test_duplicate_member_inline_object_is_checked(self):
        self.write('ui/Inline.qml', 'Item { QtObject { id: x; property int value: 0; signal done() } }\n')
        self.assertEqual(gates.qml_duplicate_member(self.root, ['ui/Inline.qml']), (1, []))
        self.write('ui/Inline.qml', 'Item { QtObject { id: x; property int value: 0; property int value: 1 } }\n')
        self.assertEqual(gates.qml_duplicate_member(self.root, ['ui/Inline.qml']),
                         (1, ['ui/Inline.qml:1: value declared again (first at 1)']))

    def test_duplicate_member_strings_comments_and_regex_keep_scopes(self):
        bindings = ('property string text: "} Item { property int value: 1"',
                    "property string text: '{ signal value(); }'",
                    'property var text: `} QtObject { function value() {} ${ {value: 1} }`',
                    'property var text: `outer ${ `inner } {` } end`',
                    'property var text: `outer ${ /* comment */ /}/.test("}") } end`',
                    'property var text: `outer ${ (() => { if ("(") /}/.test("}") })() } end`',
                    'property var pattern: /[{}]\\/function value\\(\\)/',
                    'property var pattern: /* comment */ /}/',
                    'property var pattern: true || /{/.test("x")',
                    'property var pattern: 1 + /{/.source.length',
                    '// } QtObject { property int value: 1',
                    '/* } QtObject { property int value: 1; id: fake */')
        for binding in bindings:
            with self.subTest(binding=binding):
                source = 'Item {\nproperty int value: 0\n' + binding + '\n'
                self.write('ui/Literals.qml', source + '}\n')
                self.assertEqual(gates.qml_duplicate_member(self.root, ['ui/Literals.qml']), (1, []))
                self.write('ui/Literals.qml', source + 'property int value: 1\n}\n')
                self.assertEqual(gates.qml_duplicate_member(self.root, ['ui/Literals.qml']),
                                 (1, ['ui/Literals.qml:4: value declared again (first at 2)']))

    def test_duplicate_member_function_body_literal_is_not_a_member(self):
        self.write('ui/Body.qml', 'Item {\nproperty int value: 0\nfunction run() {\n'
                   'var object = {value: 1, id: "local", nested: {value: 2}}\n'
                   'function value() { return object }\n}\n}\n')
        self.assertEqual(gates.qml_duplicate_member(self.root, ['ui/Body.qml']), (1, []))

    def test_duplicate_member_function_regex_does_not_change_scopes(self):
        self.write('ui/Regex.qml', 'Item {\nfunction run() { if (true) /{/.test("x"); }\n'
                   'property int wire: 0\nproperty int wire: 1\n}\n')
        self.assertEqual(gates.qml_duplicate_member(self.root, ['ui/Regex.qml']),
                         (1, ['ui/Regex.qml:4: wire declared again (first at 3)']))

    def test_duplicate_member_typed_function_body_is_not_an_object(self):
        self.write('ui/Typed.qml', 'Item {\nfunction run(): QQ.QtObject {\n'
                   'function wire() {}\nfunction wire() {}\nreturn {wire: 1}\n}\n'
                   'property int wire: 0\nproperty int wire: 1\n}\n')
        self.assertEqual(gates.qml_duplicate_member(self.root, ['ui/Typed.qml']),
                         (1, ['ui/Typed.qml:8: wire declared again (first at 7)']))

    def test_duplicate_member_binding_expressions_are_not_objects(self):
        self.write('ui/Bindings.qml', 'Item {\nproperty int value: 0\nfunction callback() {}\n'
                   'property var first: function callback() { return {value: 1} }\n'
                   'property var second:\nfunction callback() { return {value: 2} }\n'
                   'property var third: (function callback() { return {value: 3} })()\n'
                   'onWidthChanged: { function callback() {}; var object = {value: 4} }\n}\n')
        self.assertEqual(gates.qml_duplicate_member(self.root, ['ui/Bindings.qml']), (1, []))

    def test_duplicate_member_qualified_and_bound_objects(self):
        self.write('ui/Qualified.qml', 'QQ.Item { property int value: 0\n'
                   'property QtObject child: QQ.QtObject { property int value: 1 }\n'
                   'data: [QQ.QtObject { property int value: 2 },\n'
                   'QQ.QtObject { property int value: 3; property int value: 4 }]\n'
                   'component Inner: QQ.QtObject { property int value: 5 }\n}\n')
        self.assertEqual(gates.qml_duplicate_member(self.root, ['ui/Qualified.qml']),
                         (1, ['ui/Qualified.qml:4: value declared again (first at 4)']))

    def test_duplicate_member_comments_between_declaration_tokens(self):
        self.write('ui/Comment.qml', 'QtObject {\nproperty /* } */ int value: 0\n'
                   'readonly /* { */ property int value: 1\n}\n')
        self.assertEqual(gates.qml_duplicate_member(self.root, ['ui/Comment.qml']),
                         (1, ['ui/Comment.qml:3: value declared again (first at 2)']))

    def test_duplicate_member_js_twin_plain_and_pragma_library(self):
        for pragma in ('', '.pragma library\n'):
            with self.subTest(pragma=pragma):
                self.write('ui/js/Twin.js', pragma + 'function wire() {}\nfunction wire() {}\n')
                first = 2 if pragma else 1
                self.assertEqual(gates.qml_duplicate_member(self.root, ['ui/js/Twin.js']),
                                 (1, [f'ui/js/Twin.js:{first + 1}: wire declared again (first at {first})']))

    def test_duplicate_member_js_only_file_scope_declarations(self):
        source = ('function wire() { function wire() {}; return {wire: 1} }\n'
                  'var one = function wire() {}\nvar two =\nfunction wire() {}\n'
                  'var object = {wire: function wire() {}}\n'
                  'if (true) { function wire() {} }\n')
        self.write('ui/Plain.js', source)
        self.assertEqual(gates.qml_duplicate_member(self.root, ['ui/Plain.js']), (1, []))
        self.write('ui/Plain.js', source + 'function wire() {}\n')
        self.assertEqual(gates.qml_duplicate_member(self.root, ['ui/Plain.js']),
                         (1, ['ui/Plain.js:7: wire declared again (first at 1)']))

    def test_duplicate_member_filters_paths_and_skips_missing_files(self):
        files = ('ui/A.qml', 'tests/nested/A.qml', 'ui/js/A.js', 'ui/Plain.js',
                 'tests/js/A.js', 'elsewhere/A.qml', 'ui/A.txt')
        for file in files:
            self.write(file, 'Item { property int value: 0; property int value: 1 }\n'
                       if file.endswith('.qml') else 'function value() {}\nfunction value() {}\n')
        count, errors = gates.qml_duplicate_member(self.root, ['ui/Missing.qml', *files])
        self.assertEqual(count, 4)
        self.assertEqual({error.split(':')[0] for error in errors}, set(files[:4]))

    def test_duplicate_member_cli_uses_tracked_inventory_and_formats_diagnostic(self):
        self.write('ui/Pane.qml', 'Item {\nproperty alias wire: root.width\nproperty alias wire: root.width\n}\n')
        output = io.StringIO()
        with mock.patch.object(sys, 'argv', ['staticgates.py', '--gate', 'qml-duplicate-member',
                                            '--root', str(self.root)]):
            with mock.patch.object(gates, 'inventory', return_value=['ui/Pane.qml']) as inventory:
                with contextlib.redirect_stdout(output):
                    result = gates.main()
        self.assertEqual(result, 1)
        inventory.assert_any_call(self.root, tracked=True)
        self.assertEqual(output.getvalue(), 'STATICGATE qml-duplicate-member FAIL '
                         'ui/Pane.qml:3: wire declared again (first at 2)\nSTATICGATES FAIL gates=1\n')


if __name__ == '__main__':
    unittest.main(verbosity=2)
