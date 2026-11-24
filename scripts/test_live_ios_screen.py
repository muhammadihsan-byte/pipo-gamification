import base64
import http.client
from http.server import ThreadingHTTPServer
import threading
import unittest

from scripts.live_ios_screen import handler_for


FRAME = b"\x89PNG\r\n\x1a\nfixture"


class LiveScreenTest(unittest.TestCase):
    def setUp(self):
        self.server = ThreadingHTTPServer(
            ("127.0.0.1", 0), handler_for(lambda: FRAME)
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
        frames = 0
        while frames < 2:
            line = response.fp.readline()
            self.assertTrue(line)
            if b"data:image/png;base64," in line:
                self.assertIn(base64.b64encode(FRAME), line)
                frames += 1
        connection.close()
        self.assertTrue(self.request("GET", "/frame.png?t=1")[2].startswith(b"\x89PNG"))
        self.assertEqual(self.request("GET", "/health")[0], 200)
        for method in ("POST", "PUT", "PATCH", "DELETE"):
            self.assertEqual(self.request(method, "/frame.png")[0], 405)
        self.assertEqual(self.request("GET", "/control")[0], 404)


if __name__ == "__main__":
    unittest.main()
