"""A stand-in for the tax platform's service on every host: /health, and one log line per request."""
import logging
import socket
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

logging.basicConfig(filename='/var/log/revenue/app.log', level=logging.INFO,
                    format='%(asctime)s INFO %(message)s')


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        body = f'ok {socket.gethostname()}\n'.encode() if self.path == '/health' else b'not found\n'
        self.send_response(200 if self.path == '/health' else 404)
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        logging.info('%s %s', self.client_address[0], fmt % args)


ThreadingHTTPServer(('0.0.0.0', 8080), Handler).serve_forever()
