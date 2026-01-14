"""Prefork Gemini server example.

Demonstrates a multi-process server using SO_REUSEPORT for concurrent
request handling. Each worker process handles requests independently.

Build and run:
    ./build.sh examples/prefork_server.mojo prefork_server
    DYLD_LIBRARY_PATH=/path/to/modular/lib ./prefork_server

Generate server certificate:
    openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
        -keyout server.key -out server.crt -days 365 -nodes \
        -subj "/CN=localhost"

Test with multiple concurrent requests:
    for i in {1..10}; do gmni gemini://localhost/ & done; wait
"""

from mojo_gemini import GeminiRequest
from mojo_gemini.prefork import PreforkServer
from mojo_gemini._ffi.process import getpid


fn handler(mut req: GeminiRequest) raises:
    """Handle incoming Gemini requests."""
    var path = req.path()
    var worker_pid = getpid()

    print("Worker [" + String(worker_pid) + "] handling: " + req.raw_url)

    if path == "/" or path == "/index.gmi":
        var content = String(
            """# Prefork Server Demo

This server uses multiple worker processes to handle requests concurrently.

You were served by worker PID: """
        )
        content += String(worker_pid)
        content += """

=> /about About this server
=> /echo?text Echo test (input required)

Try making multiple requests in parallel to see different workers respond!
"""
        req.respond_success("text/gemini", content)

    elif path == "/about":
        var content = String(
            """# About Prefork Server

This is a demonstration of mojo-gemini's prefork server architecture.

## How it works

1. Master process spawns N worker processes
2. Each worker binds to the same port using SO_REUSEPORT
3. Kernel distributes connections across workers
4. Each worker handles requests independently

## Benefits

- Concurrent request handling
- No thundering herd (each worker has own accept queue)
- Simple, blocking I/O model (no async complexity)
- Crash isolation (one worker crash doesn't affect others)

=> / Back to home
"""
        )
        req.respond_success("text/gemini", content)

    elif path == "/echo":
        var query = req.query()
        if len(query) == 0:
            req.respond_input("Enter text to echo:")
        else:
            var content = String("# Echo\n\nYou said: ")
            content += query
            content += "\n\nWorker PID: "
            content += String(worker_pid)
            content += "\n\n=> / Back to home\n"
            req.respond_success("text/gemini", content)

    else:
        req.respond_not_found("Page not found: " + path)


fn main() raises:
    var cert_path = "server.crt"
    var key_path = "server.key"
    var port = 1965
    var num_workers = 4

    print("Starting prefork Gemini server...")
    print("Certificate:", cert_path)
    print("Key:", key_path)
    print("Port:", port)
    print("Workers:", num_workers)
    print()

    var server = PreforkServer[handler](
        cert_path=cert_path,
        key_path=key_path,
        port=port,
        num_workers=num_workers,
    )

    print("Press Ctrl+C to stop")
    print()

    server.serve()
