import base64
import http.client
import itertools
from http.server import ThreadingHTTPServer
import threading
import unittest

from scripts.live_ios_screen import handler_for


FRAME = b"\x89PNG\r\n\x1a\nfixture"


class LiveScreenTest(unittest.TestCase):
    def setUp(self):
        frames = itertools.count()
        self.server = ThreadingHTTPServer(
            ("127.0.0.1", 0), handler_for(lambda: FRAME + str(next(frames)).encode("ascii"))
        )
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()

    def request(self, method, path):
        connection = http.client.HTTPConnection(
            "127.0.0.1", self.server.server_address[1], timeout=3
        )
        connection.request(method, path)
        response = connection.getresponse()
        result = response.status, response.getheader("Cache-Control"), response.read()
        connection.close()
        return result

    def test_preview_is_read_only(self):
        connection = http.client.HTTPConnection(
            "127.0.0.1", self.server.server_address[1], timeout=3
        )
        connection.request("GET", "/")
        response = connection.getresponse()
        self.assertEqual(response.status, 200)
        self.assertEqual(response.getheader("Cache-Control"), "no-store")
        self.assertEqual(response.getheader("Content-Type"), "text/html; charset=utf-8")
        frames = []
        try:
            while len(frames) < 2:
                line = response.fp.readline()
                self.assertTrue(line)
                if b"data:image/png;base64," in line:
                    encoded = line.split(b"data:image/png;base64,", 1)[1].split(b'"', 1)[0]
                    frames.append(base64.b64decode(encoded, validate=True))
            self.assertTrue(all(frame.startswith(FRAME) for frame in frames))
            self.assertNotEqual(frames[0], frames[1], "Live preview must deliver changing frames")
        finally:
            response.close()
            connection.close()
        self.assertTrue(self.request("GET", "/frame.png?t=1")[2].startswith(b"\x89PNG"))
        self.assertEqual(self.request("GET", "/health")[0], 200)
        for method in ("POST", "PUT", "PATCH", "DELETE"):
            self.assertEqual(self.request(method, "/frame.png")[0], 405)
        self.assertEqual(self.request("GET", "/control")[0], 404)


if __name__ == "__main__":
    unittest.main()
