MAX_BODY = 1024 * 1024
READ_CHUNK = 65536
READ_TIMEOUT = 5
RECEIVER_LIFETIME = 90
MIME_TYPES = ["text/uri-list", "text/plain"]


class DropReader:
    def __init__(self, drop, action, write, quit_app, loop, cancellable):
        self.drop = drop
        self.action = action
        self.write = write
        self.quit_app = quit_app
        self.loop = loop
        self.cancellable = cancellable
        self.chunks = []
        self.total = 0
        self.done = False
        self.timer = None

    def start(self):
        self.timer = self.loop.timeout_add_seconds(READ_TIMEOUT, self.on_timeout)
        try:
            self.drop.read_async(MIME_TYPES, self.loop.PRIORITY_DEFAULT,
                                 self.cancellable, self.on_read)
        except Exception as error:
            self.finish(error)

    def on_read(self, drop, result):
        if self.done:
            return
        try:
            self.stream, self.mime = drop.read_finish(result)
            self.read_next()
        except Exception as error:
            self.finish(error)

    def read_next(self):
        self.stream.read_bytes_async(READ_CHUNK, self.loop.PRIORITY_DEFAULT,
                                     self.cancellable, self.on_chunk)

    def on_chunk(self, stream, result):
        if self.done:
            return
        try:
            data = stream.read_bytes_finish(result).get_data()
            if not data:
                self.finish()
                return
            self.total += len(data)
            if self.total > MAX_BODY:
                raise ValueError("drop body exceeds 1 MiB")
            self.chunks.append(data)
            self.read_next()
        except Exception as error:
            self.finish(error)

    def on_timeout(self):
        self.timer = None
        self.finish(f"timeout after {READ_TIMEOUT} s")
        return False

    def finish(self, error=None):
        if self.done:
            return
        self.done = True
        if self.timer is not None:
            self.loop.source_remove(self.timer)
            self.timer = None
        self.cancellable.cancel()
        if error is None:
            self.write(f"mime={self.mime}")
            self.write("body<<")
            self.write(b"".join(self.chunks).decode("utf-8", "replace"))
            self.write(">>")
        else:
            self.write(f"read-error={error}")
        try:
            self.drop.finish(self.action)
        finally:
            self.quit_app()
