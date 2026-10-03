#!/usr/bin/env python3
import heapq
import unittest

from drag_read import DropReader, MAX_BODY, MIME_TYPES, READ_CHUNK, READ_TIMEOUT, RECEIVER_LIFETIME

COPY_ACTION = 1
MOVE_ACTION = 2
PING_INTERVAL = READ_TIMEOUT / 2


class Loop:
    PRIORITY_DEFAULT = 0

    def __init__(self):
        self.now = 0
        self.next_id = 0
        self.pending = []
        self.removed = set()

    def timeout_add_seconds(self, seconds, callback):
        self.next_id += 1
        heapq.heappush(self.pending, (self.now + seconds, self.next_id, callback))
        return self.next_id

    def source_remove(self, timer):
        self.removed.add(timer)

    def advance(self, seconds):
        end = self.now + seconds
        while self.pending and self.pending[0][0] <= end:
            when, timer, callback = heapq.heappop(self.pending)
            self.now = when
            if timer not in self.removed:
                callback()
        self.now = end


class Cancellable:
    cancelled = False

    def cancel(self):
        self.cancelled = True


class Bytes:
    def __init__(self, data):
        self.data = data

    def get_data(self):
        return self.data


class Stream:
    def __init__(self, loop, chunks):
        self.loop = loop
        self.chunks = list(chunks)
        self.requests = []
        self.pending = None

    def read_bytes_async(self, count, priority, cancellable, callback):
        self.requests.append((count, priority, cancellable))
        self.pending = callback
        data = self.chunks.pop(0) if self.chunks else b""
        if data is not None:
            self.loop.timeout_add_seconds(0, lambda: callback(self, data))

    def read_bytes_finish(self, result):
        if isinstance(result, Exception):
            raise result
        return Bytes(result)

    def read_bytes(self, *_args):
        raise AssertionError("synchronous reads block the main loop")


class Drop:
    def __init__(self, loop, stream, offer_pending=False):
        self.loop = loop
        self.stream = stream
        self.offer_pending = offer_pending
        self.actions = []

    def read_async(self, mimes, priority, cancellable, callback):
        assert mimes == MIME_TYPES
        assert priority == self.loop.PRIORITY_DEFAULT
        assert not cancellable.cancelled
        if not self.offer_pending:
            self.loop.timeout_add_seconds(0, lambda: callback(self, None))

    def read_finish(self, _result):
        return self.stream, MIME_TYPES[0]

    def finish(self, action):
        self.actions.append(action)


class ReadCheck(unittest.TestCase):
    def reader(self, chunks, action=COPY_ACTION, offer_pending=False):
        self.loop = Loop()
        self.stream = Stream(self.loop, chunks)
        self.drop = Drop(self.loop, self.stream, offer_pending)
        self.log = []
        self.quits = []
        self.cancellable = Cancellable()
        reader = DropReader(self.drop, action, self.log.append,
                            lambda: self.quits.append(True), self.loop, self.cancellable)
        reader.start()
        return reader

    def ended(self, action=COPY_ACTION):
        self.assertEqual(self.drop.actions, [action])
        self.assertEqual(self.quits, [True])
        self.assertTrue(self.cancellable.cancelled)

    def test_body_uses_async_chunks_and_preserves_log_and_move_finish(self):
        self.reader([b"file:///", b"fixture.txt\r\n", b""], MOVE_ACTION)
        self.assertEqual(self.log, [])
        self.loop.advance(READ_TIMEOUT)
        self.assertEqual(self.log, ["mime=text/uri-list", "body<<", "file:///fixture.txt\r\n", ">>"])
        self.assertTrue(all(count == READ_CHUNK and priority == self.loop.PRIORITY_DEFAULT
                            and cancellable is self.cancellable
                            for count, priority, cancellable in self.stream.requests))
        self.ended(MOVE_ACTION)

    def test_stalled_stream_keeps_loop_responsive_and_times_out_once(self):
        self.reader([None])
        pings = []
        self.loop.timeout_add_seconds(PING_INTERVAL, lambda: pings.append(True))
        self.loop.advance(PING_INTERVAL)
        self.assertEqual(pings, [True])
        self.assertEqual(self.log, [])
        self.assertFalse(self.cancellable.cancelled)
        self.loop.advance(READ_TIMEOUT - PING_INTERVAL)
        self.assertEqual(self.log, [f"read-error=timeout after {READ_TIMEOUT} s"])
        self.ended()
        self.stream.pending(self.stream, RuntimeError("cancelled"))
        self.loop.advance(RECEIVER_LIFETIME)
        self.assertEqual(self.log, [f"read-error=timeout after {READ_TIMEOUT} s"])
        self.ended()

    def test_pending_mime_negotiation_has_the_same_bound(self):
        self.reader([], offer_pending=True)
        self.loop.advance(READ_TIMEOUT)
        self.assertEqual(self.log, [f"read-error=timeout after {READ_TIMEOUT} s"])
        self.ended()

    def test_over_cap_never_logs_a_partial_body(self):
        reader = self.reader([b"x" * READ_CHUNK] * (MAX_BODY // READ_CHUNK) + [b"x"])
        self.loop.advance(READ_TIMEOUT)
        self.assertEqual(self.log, ["read-error=drop body exceeds 1 MiB"])
        self.assertLessEqual(sum(map(len, reader.chunks)), MAX_BODY)
        self.ended()

    def test_exact_cap_is_accepted(self):
        self.reader([b"x" * READ_CHUNK] * (MAX_BODY // READ_CHUNK))
        self.loop.advance(READ_TIMEOUT)
        self.assertEqual(self.log, ["mime=text/uri-list", "body<<", "x" * MAX_BODY, ">>"])
        self.ended()

    def test_read_error_quits_and_removes_the_deadline(self):
        self.reader([RuntimeError("source failed")])
        self.loop.advance(RECEIVER_LIFETIME)
        self.assertEqual(self.log, ["read-error=source failed"])
        self.ended()

    def test_read_deadline_precedes_lifetime(self):
        self.assertGreater(READ_TIMEOUT, 0)
        self.assertLess(READ_TIMEOUT, RECEIVER_LIFETIME)


if __name__ == "__main__":
    unittest.main(verbosity=2)
