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


if __name__ == '__main__':
    unittest.main(verbosity=2)
