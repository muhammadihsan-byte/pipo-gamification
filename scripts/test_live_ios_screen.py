import http.client
from http.server import ThreadingHTTPServer
import threading
import unittest

from scripts.live_ios_screen import handler_for


class LiveScreenTest(unittest.TestCase):
    def setUp(self):
        self.server = ThreadingHTTPServer(
            ("127.0.0.1", 0), handler_for(lambda: b"\x89PNG\r\n\x1a\nfixture")
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
        status, cache, page = self.request("GET", "/")
        self.assertEqual((status, cache), (200, "no-store"))
        self.assertIn(b"read-only live preview", page)
        self.assertTrue(self.request("GET", "/frame.png?t=1")[2].startswith(b"\x89PNG"))
        self.assertEqual(self.request("GET", "/health")[0], 200)
        for method in ("POST", "PUT", "PATCH", "DELETE"):
            self.assertEqual(self.request(method, "/frame.png")[0], 405)
        self.assertEqual(self.request("GET", "/control")[0], 404)


if __name__ == "__main__":
    unittest.main()
