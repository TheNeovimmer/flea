#!/usr/bin/env python3
"""One Wayland drop target. Logs the offer and exits.

tests/drag.sh starts this beside Flea. It is not a file manager: it accepts the
drop, writes the MIME types, the uri-list body and the action mask, and quits.

Safety: the log path must be an absolute path inside a directory carrying the
.flea-test-sandbox marker (the run's own sandbox root or directly inside one).
Anything else is refused before GTK starts, so a bad argv cannot append to an
operator file. The drop body is capped at 1 MiB. Only this process quits.
"""
import os
import sys

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Gdk", "4.0")
from gi.repository import Gdk, GLib, Gtk

MARKER = ".flea-test-sandbox"
MAX_BODY = 1024 * 1024


def owned_log_path(argv):
    if len(argv) != 2 or not argv[1]:
        raise SystemExit("drag-receiver: one absolute log path is required")
    raw = argv[1]
    if not os.path.isabs(raw):
        raise SystemExit("drag-receiver: log path is not absolute")
    path = os.path.realpath(raw)
    parent = os.path.dirname(path)
    if not parent or not os.path.isdir(parent):
        raise SystemExit("drag-receiver: log directory does not exist")
    if not (os.path.isfile(os.path.join(parent, MARKER))
            or os.path.isfile(os.path.join(os.path.dirname(parent), MARKER))):
        raise SystemExit("drag-receiver: log path is outside a marked sandbox")
    return path


log_path = owned_log_path(sys.argv)


def write(text):
    with open(log_path, "a", encoding="utf-8") as handle:
        handle.write(text)
        if not text.endswith("\n"):
            handle.write("\n")


class Receiver(Gtk.Application):
    def __init__(self):
        super().__init__(application_id="com.thisisgm.FleaDragReceiver")

    def do_activate(self):
        window = Gtk.ApplicationWindow(application=self, title="flea-drag-receiver")
        window.set_default_size(420, 320)
        label = Gtk.Label(label="drop here")
        label.set_hexpand(True)
        label.set_vexpand(True)
        window.set_child(label)
        target = Gtk.DropTargetAsync.new(
            Gdk.ContentFormats.new(["text/uri-list", "text/plain"]),
            Gdk.DragAction.COPY | Gdk.DragAction.MOVE,
        )
        target.connect("drop", self.on_drop)
        label.add_controller(target)
        window.present()
        write("ready")

    def on_drop(self, _target, drop, _x, _y):
        formats = drop.get_formats()
        write(f"actions={int(drop.get_actions())}")
        write(f"formats={formats.to_string() if formats is not None else ''}")
        drop.read_async(
            ["text/uri-list", "text/plain"],
            GLib.PRIORITY_DEFAULT,
            None,
            self.on_read,
        )
        return True

    def on_read(self, drop, result):
        try:
            stream, mime = drop.read_finish(result)
            chunks = []
            total = 0
            while True:
                piece = stream.read_bytes(65536, None)
                data = piece.get_data()
                if not data:
                    break
                total += len(data)
                if total > MAX_BODY:
                    raise ValueError("drop body exceeds 1 MiB")
                chunks.append(data)
            body = b"".join(chunks).decode("utf-8", "replace")
            write(f"mime={mime}")
            write("body<<")
            write(body)
            write(">>")
        except Exception as error:
            write(f"read-error={error}")
        drop.finish(Gdk.DragAction.COPY)
        self.quit()


def main():
    app = Receiver()
    GLib.timeout_add_seconds(90, app.quit)
    raise SystemExit(app.run(None))


if __name__ == "__main__":
    main()
