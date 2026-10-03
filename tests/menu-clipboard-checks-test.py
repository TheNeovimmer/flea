#!/usr/bin/env python3
"""Exercise the menu clipboard oracle against real copied and moved files."""
import importlib.util
from pathlib import Path
import shutil
import tempfile
import unittest

HELPER_PATH = Path(__file__).with_name("menu-clipboard-checks.py")
SPEC = importlib.util.spec_from_file_location("clipboard_checks", HELPER_PATH)
CHECKS = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CHECKS)


class ClipboardFilesTest(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory()
        self.addCleanup(self.scratch.cleanup)
        self.source = Path(self.scratch.name) / "source"
        self.destination = Path(self.scratch.name) / "destination"
        self.source.mkdir()
        self.destination.mkdir()
        for name in CHECKS.SELECTED_NAMES:
            (self.source / name).write_text(name)
            shutil.copyfile(self.source / name, self.destination / name)

    def test_copy_retains_both_sources(self):
        CHECKS.files("copy", self.source, self.destination)

    def test_copy_rejects_both_sources_moved(self):
        for name in CHECKS.SELECTED_NAMES:
            (self.source / name).replace(self.destination / name)
        with self.assertRaisesRegex(ValueError, "alpha.txt.*Copy source"):
            CHECKS.files("copy", self.source, self.destination)

    def test_copy_requires_each_source(self):
        for name in CHECKS.SELECTED_NAMES:
            with self.subTest(name=name):
                (self.source / name).replace(self.destination / name)
                with self.assertRaisesRegex(ValueError, name + ".*Copy source"):
                    CHECKS.files("copy", self.source, self.destination)
                shutil.copyfile(self.destination / name, self.source / name)

    def test_cut_removes_both_sources(self):
        for name in CHECKS.SELECTED_NAMES:
            (self.source / name).replace(self.destination / name)
        CHECKS.files("cut", self.source, self.destination)

    def test_cut_rejects_each_retained_source(self):
        for name in CHECKS.SELECTED_NAMES:
            (self.source / name).unlink()
        for name in CHECKS.SELECTED_NAMES:
            with self.subTest(name=name):
                shutil.copyfile(self.destination / name, self.source / name)
                with self.assertRaisesRegex(ValueError, name + ".*Cut source"):
                    CHECKS.files("cut", self.source, self.destination)
                (self.source / name).unlink()

    def test_copy_requires_each_destination(self):
        for name in CHECKS.SELECTED_NAMES:
            with self.subTest(name=name):
                (self.destination / name).unlink()
                with self.assertRaisesRegex(ValueError, name + ".*destination file"):
                    CHECKS.files("copy", self.source, self.destination)
                shutil.copyfile(self.source / name, self.destination / name)

    def test_copy_rejects_symlink_destinations(self):
        for name in CHECKS.SELECTED_NAMES:
            with self.subTest(name=name):
                (self.destination / name).unlink()
                (self.destination / name).symlink_to(self.source / name)
                with self.assertRaisesRegex(ValueError, name + ".*destination file"):
                    CHECKS.files("copy", self.source, self.destination)
                (self.destination / name).unlink()
                shutil.copyfile(self.source / name, self.destination / name)


if __name__ == "__main__":
    unittest.main()
