import sys
import json
from http.server import HTTPServer, BaseHTTPRequestHandler

PORT = 5055

class WeatherHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path == '/execute':
            content_length = int(self.headers.get('Content-Length', 0))
            body = self.rfile.read(content_length).decode('utf-8')
            try:
                data = json.loads(body) if body else {}
            except Exception:
                data = {}

            args = data.get('arguments', {})
            city = args.get('city', 'غير محدد')

            response_data = {
                "status": "success",
                "city": city,
                "temperature": "29°C",
                "condition": "مشمس ومعتدل مع رياح خفيفة",
                "humidity": "42%",
                "sidecar": "Khwarizmi Python Weather Sidecar v1.0.0"
            }

            self.send_response(200)
            self.send_header('Content-Type', 'application/json; charset=utf-8')
            self.end_headers()
            self.wfile.write(json.dumps(response_data, ensure_ascii=False).encode('utf-8'))
        else:
            self.send_response(404)
            self.end_headers()

    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps({"status": "healthy", "service": "mock_weather"}).encode('utf-8'))

    def log_message(self, format, *args):
        # طباعة في stdout ليتم رصدها وتسجيلها في SidecarProcessManager
        sys.stdout.write(f"[WeatherSidecar] {format % args}\n")
        sys.stdout.flush()

if __name__ == '__main__':
    print(f"[WeatherSidecar] Starting Python Sidecar on port {PORT}...", flush=True)
    server = HTTPServer(('127.0.0.1', PORT), WeatherHandler)
    server.serve_forever()
