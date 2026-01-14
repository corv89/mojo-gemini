# mojo-gemini

A Gemini protocol implementation for Mojo, providing both client and server libraries.

## Overview

[Gemini](https://geminiprotocol.net/) is a lightweight internet protocol that sits between Gopher and HTTP. It uses TLS for transport security and a simple request/response model.

This library provides:
- **GeminiClient** - Make requests to Gemini servers
- **GeminiServer** - Serve Gemini content over TLS
- **PreforkServer** - Multi-process server for concurrent request handling

Built on [mojo-tls](https://github.com/anthropics/mojo-tls) for TLS 1.3 support via mbedTLS.

## Requirements

- Mojo (tested with latest nightly)
- mojo-tls library (must be built first)
- mbedTLS 4.0.0: `brew install mbedtls` (macOS) or `apt install libmbedtls-dev` (Linux)

## Building

The build script auto-detects paths for mojo-tls, mbedTLS, and the Mojo compiler. Place mojo-tls as a sibling directory or set environment variables:

```bash
# Recommended directory structure:
# parent/
#   mojo-tls/    # Clone and build first
#   mojo-gemini/ # This project

# Build client example
./build.sh examples/simple_client.mojo simple_client

# Build server example
./build.sh examples/simple_server.mojo simple_server

# Show detected paths (for debugging)
./build.sh -v examples/simple_client.mojo simple_client
```

### Environment Variables

Override auto-detection by setting these environment variables:

| Variable | Description |
|----------|-------------|
| `MOJO_TLS_PATH` | Path to mojo-tls source directory |
| `MBEDTLS_LIB` | Path to mbedTLS library directory |
| `MOJO_BIN` | Path to mojo compiler |
| `MOJO_RUNTIME_LIB` | Path to Mojo runtime libraries |

### Running

Run binaries with the Mojo runtime library path (shown after build):
```bash
DYLD_LIBRARY_PATH=/path/to/modular/lib ./simple_client
```

## Usage

### Client Example

```mojo
from mojo_gemini import GeminiClient, status_description

fn main() raises:
    var client = GeminiClient()
    var response = client.request("gemini://geminiprotocol.net/")

    print("Status:", response.status.code, "-", status_description(response.status))

    if response.is_success():
        print("Content type:", response.mime_type())
        print(response.body())
    elif response.is_redirect():
        print("Redirect to:", response.meta)
    elif response.is_input():
        print("Server requests input:", response.meta)
    else:
        print("Error:", response.meta)
```

The client automatically:
- Follows redirects (up to 5 by default)
- Accepts self-signed certificates (TOFU model)
- Handles all Gemini status codes

### Server Example

```mojo
from mojo_gemini import GeminiServer, GeminiRequest

fn handler(mut req: GeminiRequest) raises:
    var path = req.path()

    if path == "/" or path == "/index.gmi":
        req.respond_success("text/gemini", "# Welcome!\n\n=> /about About")
    elif path == "/about":
        req.respond_success("text/gemini", "# About\n\nPowered by mojo-gemini")
    elif path == "/search":
        if len(req.query()) == 0:
            req.respond_input("Enter search query:")
        else:
            req.respond_success("text/gemini", "Results for: " + req.query())
    else:
        req.respond_not_found()

fn main() raises:
    var server = GeminiServer.bind("server.crt", "server.key", "0.0.0.0", 1965)
    print("Listening on gemini://localhost:1965/")
    server.serve[handler]()
```

### Response Methods

The `GeminiRequest` object provides several response methods:

```mojo
# Success with content
req.respond_success("text/gemini", content)
req.respond_success_bytes("image/png", data_ptr, length)

# Input requests
req.respond_input("Enter your name:")
req.respond_sensitive_input("Enter password:")

# Redirects
req.respond_redirect("/new-location")
req.respond_redirect("/permanent", permanent=True)

# Errors
req.respond_not_found()
req.respond_not_found("Custom message")
req.respond_error("Permanent error")
req.respond_temp_error("Try again later")

# Generic response
req.respond(Status(51), "Not found")
```

## Certificate Generation

The server requires a TLS certificate. For development/testing, generate a self-signed certificate:

```bash
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
    -keyout server.key -out server.crt -days 365 -nodes \
    -subj "/CN=localhost"
```

For production, use a certificate from a CA or Let's Encrypt.

## Status Codes

Gemini uses two-digit status codes organized by category:

| Range | Category | Description |
|-------|----------|-------------|
| 10-19 | Input | Server requests user input |
| 20-29 | Success | Request succeeded, content follows |
| 30-39 | Redirect | Resource moved, follow URL in meta |
| 40-49 | Temporary Failure | Retry later |
| 50-59 | Permanent Failure | Do not retry |
| 60-69 | Client Certificate | Authentication required |

Common codes:
- `10` INPUT - Prompt user for input
- `11` SENSITIVE INPUT - Prompt for password (masked)
- `20` SUCCESS - Content follows
- `30` TEMPORARY REDIRECT
- `31` PERMANENT REDIRECT
- `40` TEMPORARY FAILURE
- `44` SLOW DOWN - Rate limiting
- `51` NOT FOUND
- `52` GONE - Permanently removed
- `60` CLIENT CERTIFICATE REQUIRED

## Client Certificate Authentication

Gemini supports identity-based authentication using client certificates. The certificate's SHA-256 fingerprint serves as a persistent user identity.

### Server-Side Authentication

```mojo
from mojo_gemini import GeminiServer, GeminiRequest

fn handler(mut req: GeminiRequest) raises:
    if req.path() == "/private":
        # Require a client certificate
        if not req.has_client_cert():
            req.respond_cert_required("Please present a certificate")
            return

        # Get the certificate fingerprint (64-char hex string)
        var fingerprint = req.client_cert_fingerprint()

        # Optionally verify against a known fingerprint
        if req.verify_client_cert("abc123..."):
            req.respond_success("text/gemini", "# Welcome, trusted user!")
        else:
            req.respond_cert_unauthorized("Unknown certificate")
        return

    req.respond_success("text/gemini", "# Public page")

fn main() raises:
    # Use "optional" to request but not require client certs
    # Use "required" to reject connections without certificates
    var server = GeminiServer.bind_with_client_auth(
        "server.crt", "server.key",
        client_auth="optional"
    )
    server.serve[handler]()
```

### Client-Side Certificate

```mojo
from mojo_gemini import GeminiClient

fn main() raises:
    var client = GeminiClient()
    client.set_client_certificate("client.crt", "client.key")

    var response = client.request("gemini://example.com/private")
    # Server will see client's certificate fingerprint
```

### Certificate Response Methods

```mojo
req.respond_cert_required("Please present a certificate")      # Status 60
req.respond_cert_unauthorized("Certificate not authorized")    # Status 61
req.respond_cert_invalid("Certificate is malformed")           # Status 62
```

### Generating Client Certificates

```bash
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
    -keyout client.key -out client.crt -days 365 -nodes \
    -subj "/CN=username"
```

## Prefork Server

For concurrent request handling, use `PreforkServer` which spawns multiple worker processes. Each worker binds to the same port using `SO_REUSEPORT`, and the kernel distributes connections across workers.

```mojo
from mojo_gemini import GeminiRequest
from mojo_gemini.prefork import PreforkServer
from mojo_gemini._ffi.process import getpid

fn handler(mut req: GeminiRequest) raises:
    var content = "# Hello from worker " + String(getpid())
    req.respond_success("text/gemini", content)

fn main() raises:
    var server = PreforkServer[handler](
        cert_path="server.crt",
        key_path="server.key",
        num_workers=4,  # Spawn 4 worker processes
    )
    server.serve()
```

Benefits:
- **Concurrent handling** - Multiple requests served simultaneously
- **No thundering herd** - Each worker has its own accept queue
- **Crash isolation** - One worker crash doesn't affect others
- **Simple model** - Each worker uses blocking I/O (no async complexity)

The master process monitors workers and exits when all workers die. For automatic restarts, use an external process manager (systemd, supervisord).

## Known Limitations

- **Blocking I/O** - Individual connections use blocking I/O (no async). Use `PreforkServer` for concurrent handling across multiple worker processes.
- **No percent-encoding** - URLs are not automatically encoded/decoded. Pass pre-encoded URLs if needed.
- **No streaming writes** - Server responses must fit in memory; no chunked transfer.

## Project Structure

```
mojo-gemini/
├── mojo_gemini/
│   ├── __init__.mojo      # Public exports
│   ├── protocol.mojo      # Constants (port 1965, limits)
│   ├── status.mojo        # Status codes
│   ├── url.mojo           # URL parsing
│   ├── client.mojo        # GeminiClient
│   ├── response.mojo      # Client response handling
│   ├── server.mojo        # GeminiServer
│   ├── request.mojo       # Server request handling
│   ├── prefork.mojo       # PreforkServer for multi-process serving
│   ├── mime.mojo          # MIME type detection
│   └── _ffi/              # FFI bindings for POSIX APIs
│       ├── process.mojo   # fork, waitpid, getpid, _exit
│       └── signal.mojo    # Signal constants
├── examples/
│   ├── simple_client.mojo
│   ├── simple_server.mojo
│   ├── client_auth_server.mojo
│   └── prefork_server.mojo
├── build.sh
└── README.md
```

## License

Apache 2.0
