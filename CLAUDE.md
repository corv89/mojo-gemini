# CLAUDE.md

This file provides guidance to Claude Code when working with this repository.

## Project Overview

mojo-gemini is a Gemini protocol implementation for Mojo, providing client and server libraries. It builds on mojo-tls for TLS 1.3 support.

## Build Commands

Build an example or test:
```bash
./build.sh examples/simple_client.mojo simple_client
./build.sh examples/simple_server.mojo simple_server

# Show detected paths
./build.sh -v examples/simple_client.mojo simple_client
```

Run the built binary (path shown after build):
```bash
DYLD_LIBRARY_PATH=/path/to/modular/lib ./simple_client
```

## Dependencies

- mojo-tls as sibling directory (`../mojo-tls`) or set `MOJO_TLS_PATH`
- mbedTLS 4.0.0: `brew install mbedtls` (macOS) or `apt install libmbedtls-dev` (Linux)

The build script auto-detects paths. Override with environment variables:
- `MOJO_TLS_PATH` - mojo-tls source directory
- `MBEDTLS_LIB` - mbedTLS library directory
- `MOJO_BIN` - mojo compiler
- `MOJO_RUNTIME_LIB` - Mojo runtime libraries

## Architecture

### Module Structure
- **`protocol.mojo`** - Constants (port 1965, URL limits, CRLF)
- **`status.mojo`** - Status codes enum (10-69 range)
- **`url.mojo`** - gemini:// URL parsing and manipulation
- **`response.mojo`** - Client response handling with body reading
- **`client.mojo`** - GeminiClient for making requests
- **`request.mojo`** - Server request handling with response methods
- **`server.mojo`** - GeminiServer for accepting connections
- **`mime.mojo`** - MIME type detection from file extensions

### Client API
```mojo
from mojo_gemini import GeminiClient

var client = GeminiClient()
var response = client.request("gemini://example.com/")

if response.is_success():
    print(response.body())
```

### Server API
```mojo
from mojo_gemini import GeminiServer, GeminiRequest

fn handler(mut req: GeminiRequest) raises:
    req.respond_success("text/gemini", "# Hello!")

var server = GeminiServer.bind("cert.pem", "key.pem")
server.serve[handler]()  # Note: function passed as type parameter
```

### Server with Client Auth
```mojo
from mojo_gemini import GeminiServer, GeminiRequest

fn handler(mut req: GeminiRequest) raises:
    if req.has_client_cert():
        var fingerprint = req.client_cert_fingerprint()
        # Use fingerprint as identity
    else:
        req.respond_cert_required()

# client_auth: "none", "optional", or "required"
var server = GeminiServer.bind_with_client_auth("cert.pem", "key.pem", client_auth="optional")
server.serve[handler]()
```

## Key Design Decisions

- **TOFU Model**: Client uses `set_verify_none()` to accept self-signed certificates
- **Sync-only**: No async support yet (mirrors mojo-tls patterns)
- **Handler Pattern**: Server uses callback function for request handling

## Status Codes

| Range | Category | Example |
|-------|----------|---------|
| 10-19 | Input | `Status.INPUT` (10), `Status.SENSITIVE_INPUT` (11) |
| 20-29 | Success | `Status.SUCCESS` (20) |
| 30-39 | Redirect | `Status.TEMP_REDIRECT` (30), `Status.REDIRECT` (31) |
| 40-49 | Temp Failure | `Status.TEMP_FAILURE` (40), `Status.SLOW_DOWN` (44) |
| 50-59 | Perm Failure | `Status.NOT_FOUND` (51), `Status.GONE` (52) |
| 60-69 | Certificate | `Status.CERT_REQUIRED` (60) |

## Testing

Generate test certificates:
```bash
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
    -keyout server.key -out server.crt -days 365 -nodes \
    -subj "/CN=localhost"
```

Test client against external server:
```bash
./simple_client  # Default: gemini://geminiprotocol.net/
```

## Known Limitations

- No async/concurrent connection handling
- No percent-encoding/decoding for URLs

## Mojo Idioms & Workarounds

### String Construction from Bytes

The `String(UnsafePointer[UInt8], Int)` constructor does not work as expected in current Mojo - it converts the pointer address to a string rather than reading bytes from memory.

**Workaround**: Build strings character-by-character:
```mojo
# DON'T: String(buf.unsafe_ptr(), len)  # Returns hex address like "0x1046f800014"

# DO: Build character by character
var s = String()
for i in range(len(result)):
    s += chr(Int(result[i]))
return s
```

This pattern is used in `client.mojo:_read_header()`, `response.mojo:body()`, and `server.mojo:_read_request_line()`.

### Function Type Parameters as Callables

When passing a function to a parameterized method, Mojo treats the type parameter itself as the callable. You don't pass the function as a runtime argument - instead, pass it as a compile-time type parameter and call it directly:

```mojo
# The pattern:
fn serve[F: fn(mut Request) raises -> None](mut self) raises:
    # Call F directly - it IS the function
    F(request)

# Usage - function name in brackets, not parentheses:
server.serve[handler]()  # NOT server.serve(handler)
```

This differs from languages where you'd pass the function as a value parameter. In Mojo, the function becomes part of the type signature, enabling compile-time specialization.
