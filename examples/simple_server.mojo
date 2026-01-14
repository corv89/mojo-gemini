"""Simple Gemini server example.

Serves a basic Gemini site with a few pages.

Build and run:
    ./build.sh examples/simple_server.mojo simple_server
    DYLD_LIBRARY_PATH=/Users/corv/Src/.venv/lib/python3.12/site-packages/modular/lib ./simple_server

Test with:
    - simple_client to gemini://localhost:1965/
    - Or use a Gemini browser like Lagrange or Amfora

Note: Requires server certificate. Generate with:
    openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
        -keyout server.key -out server.crt -days 365 -nodes \
        -subj "/CN=localhost"
"""

from mojo_gemini import GeminiServer, GeminiRequest, Status


fn handler(mut req: GeminiRequest) raises:
    """Handle incoming Gemini requests."""
    var path = req.path()

    print("Request:", req.raw_url)

    if path == "/" or path == "/index.gmi":
        var content = String(
            """# Welcome to Mojo Gemini Server

This is a simple Gemini server written in Mojo.

## Links

=> /about About this server
=> /search Search example (input demo)
=> /hello?world Query string example

## External Links

=> gemini://geminiprotocol.net/ Gemini Protocol Homepage
=> gemini://geminispace.info/ Gemini Space
"""
        )
        req.respond_success("text/gemini", content)

    elif path == "/about":
        var content = String(
            """# About

This server is powered by:
* mojo-gemini - Gemini protocol library for Mojo
* mojo-tls - TLS 1.3 bindings for Mojo
* mbedTLS 4.0.0

=> / Back to home
"""
        )
        req.respond_success("text/gemini", content)

    elif path == "/search":
        var query = req.query()
        if len(query) == 0:
            req.respond_input("Enter your search query:")
        else:
            var content = "# Search Results\n\nYou searched for: " + query + "\n\n=> /search Search again\n=> / Home"
            req.respond_success("text/gemini", content)

    elif path == "/hello":
        var query = req.query()
        var content = "# Hello\n\nQuery string: " + (query if len(query) > 0 else "(none)") + "\n\n=> / Home"
        req.respond_success("text/gemini", content)

    elif path == "/redirect":
        req.respond_redirect("/")

    else:
        req.respond_not_found("Page not found: " + path)


fn main() raises:
    var cert_path = "server.crt"
    var key_path = "server.key"
    var port = 1965

    print("Starting Gemini server...")
    print("Certificate:", cert_path)
    print("Key:", key_path)
    print("Port:", port)
    print()

    var server = GeminiServer.bind(cert_path, key_path, "0.0.0.0", port)

    print("Listening on gemini://localhost:" + String(port) + "/")
    print("Press Ctrl+C to stop")
    print()

    server.serve[handler]()
