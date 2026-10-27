"""serve.py [port]: the pause menu's page with stub.js put in before app.js, for looking at it in a browser
(http://127.0.0.1:8767/; ?screen=settings|brief|stats|players|report, ?map=1 (&pad=1, &h=<heading>), ?bg=<picture>)."""
import http.server
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
HTML = os.path.join(os.path.dirname(HERE), 'html')


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *a, **k):
        super().__init__(*a, directory=HTML, **k)

    def end_headers(self):
        self.send_header('Cache-Control', 'no-store')
        super().end_headers()

    def do_GET(self):
        path = self.path.split('?')[0]
        if path in ('/', '/index.html'):
            with open(os.path.join(HTML, 'index.html'), encoding='utf-8') as f:
                page = f.read().replace('<script src="app.js">', '<script src="/stub.js"></script><script src="app.js">')
            body = page.encode('utf-8')
        elif path == '/stub.js':
            with open(os.path.join(HERE, 'stub.js'), 'rb') as f:
                body = f.read()
        else:
            return super().do_GET()
        self.send_response(200)
        self.send_header('Content-Type', 'text/html; charset=utf-8' if path != '/stub.js' else 'text/javascript')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)


port = int(sys.argv[1]) if len(sys.argv) > 1 else 8767
http.server.ThreadingHTTPServer(('127.0.0.1', port), Handler).serve_forever()
