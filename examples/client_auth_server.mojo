"""Client certificate authentication example.

Demonstrates identity-based access control using client certificates.
The Gemini protocol uses certificate fingerprints as persistent identities.

Build and run:
    ./build.sh examples/client_auth_server.mojo client_auth_server
    DYLD_LIBRARY_PATH=/path/to/modular/lib ./client_auth_server

Generate server certificate:
    openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
        -keyout server.key -out server.crt -days 365 -nodes \
        -subj "/CN=localhost"

Generate client certificate for testing:
    openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
        -keyout client.key -out client.crt -days 365 -nodes \
        -subj "/CN=testuser"

Test with a client that supports client certificates.
"""

from mojo_gemini import GeminiServer, GeminiRequest


fn handler(mut req: GeminiRequest) raises:
    """Handle incoming Gemini requests with client certificate checks."""
    var path = req.path()

    print("Request:", req.raw_url)

    if path == "/" or path == "/index.gmi":
        # Public page - show client cert status
        var content = String(
            """# Client Certificate Demo

This server demonstrates client certificate authentication.

## Your Certificate Status
"""
        )

        if req.has_client_cert():
            var fingerprint = req.client_cert_fingerprint()
            content += "\nYou have presented a certificate.\n"
            content += "Fingerprint: " + fingerprint + "\n"
        else:
            content += "\nNo client certificate presented.\n"

        content += """
## Pages

=> /public Public page (no cert required)
=> /private Private page (cert required)
=> /admin Admin page (shows fingerprint)
"""
        req.respond_success("text/gemini", content)

    elif path == "/public":
        # Public content - no certificate needed
        var content = String(
            """# Public Page

This page is accessible to everyone.

=> / Back to home
"""
        )
        req.respond_success("text/gemini", content)

    elif path == "/private":
        # Private content - requires any valid certificate
        if not req.has_client_cert():
            req.respond_cert_required("Please present a client certificate to access this page")
            return

        var fingerprint = req.client_cert_fingerprint()
        print("  Client cert fingerprint:", fingerprint)

        var content = String(
            """# Private Page

Welcome, authenticated user!

Your certificate fingerprint:
"""
        )
        content += fingerprint
        content += "\n\n=> / Back to home\n"
        req.respond_success("text/gemini", content)

    elif path == "/admin":
        # Admin content - requires specific certificate
        if not req.has_client_cert():
            req.respond_cert_required("Admin access requires a client certificate")
            return

        var fingerprint = req.client_cert_fingerprint()
        print("  Client cert fingerprint:", fingerprint)

        # Demo: show the fingerprint that could be used for authorization
        # In production, use verify_client_cert() against stored fingerprints
        var content = String(
            """# Admin Page

Welcome! Your certificate has been verified.

In production, you would check the fingerprint against authorized users:
```
if req.verify_client_cert("expected_fingerprint_here"):
    # Allow access
```

Your fingerprint (for configuration):
"""
        )
        content += fingerprint
        content += "\n\n=> / Back to home\n"
        req.respond_success("text/gemini", content)

    else:
        req.respond_not_found("Page not found: " + path)


fn main() raises:
    var cert_path = "server.crt"
    var key_path = "server.key"
    var port = 1965

    print("Starting Gemini server with client certificate support...")
    print("Certificate:", cert_path)
    print("Key:", key_path)
    print("Port:", port)
    print("Client auth: optional (requested but not required)")
    print()

    # Use bind_with_client_auth with "optional" to request but not require certs
    # Use "required" to reject connections without client certificates
    var server = GeminiServer.bind_with_client_auth(
        cert_path, key_path,
        client_auth="optional",
        address="0.0.0.0",
        port=port,
    )

    print("Listening on gemini://localhost:" + String(port) + "/")
    print("Press Ctrl+C to stop")
    print()

    server.serve[handler]()
