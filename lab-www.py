"""The lab's test "website": serves /opt/colitu-lab/www on port 24080.

If LAB_CC is set (e.g. "cubic"), it is applied to the listening socket and inherited by every
accepted connection. That way the website can behave like a typical server running Linux's
default congestion control even when the host itself uses BBR.
"""
import functools
import http.server
import os
import socket

CC = os.environ.get('LAB_CC', '')


class Server(http.server.ThreadingHTTPServer):
    def server_bind(self):
        if CC:
            self.socket.setsockopt(socket.IPPROTO_TCP, socket.TCP_CONGESTION, CC.encode())
        super().server_bind()


class Quiet(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *args):
        pass


handler = functools.partial(Quiet, directory='/opt/colitu-lab/www')
Server(('0.0.0.0', 24080), handler).serve_forever()
