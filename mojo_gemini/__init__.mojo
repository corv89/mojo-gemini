"""mojo-gemini: Gemini protocol implementation for Mojo.

This package provides client and server implementations for the Gemini
protocol, built on mojo-tls for TLS support.

Client example:
    from mojo_gemini import GeminiClient

    fn main() raises:
        var client = GeminiClient()
        var response = client.request("gemini://geminiprotocol.net/")

        if response.is_success():
            print("Content type:", response.mime_type())
            print(response.body())
        elif response.is_redirect():
            print("Redirect to:", response.meta)
        else:
            print("Error:", response.status, response.meta)

Server example:
    from mojo_gemini import GeminiServer, GeminiRequest, Status

    fn handler(mut req: GeminiRequest) raises:
        if req.path() == "/":
            req.respond_success("text/gemini", "# Welcome to Gemini!")
        elif req.path() == "/about":
            req.respond_success("text/gemini", "# About\\n\\nThis is a Gemini server.")
        else:
            req.respond_not_found()

    fn main() raises:
        var server = GeminiServer.bind("server.crt", "server.key")
        print("Listening on port 1965...")
        server.serve(handler)

For more information about the Gemini protocol:
    gemini://geminiprotocol.net/docs/specification.gmi
"""

# Core types
from .status import (
    Status,
    status_description,
    INPUT,
    SENSITIVE_INPUT,
    SUCCESS,
    TEMP_REDIRECT,
    REDIRECT,
    TEMP_FAILURE,
    SERVER_UNAVAILABLE,
    CGI_ERROR,
    PROXY_ERROR,
    SLOW_DOWN,
    PERM_FAILURE,
    NOT_FOUND,
    GONE,
    PROXY_REFUSED,
    BAD_REQUEST,
    CERT_REQUIRED,
    CERT_UNAUTHORIZED,
    CERT_INVALID,
)
from .url import GeminiUrl, parse_url, combine_url

# Client API
from .client import GeminiClient
from .response import GeminiResponse

# Server API
from .server import GeminiServer
from .request import GeminiRequest

# Utilities
from .mime import detect_mime_type, is_text_type, is_gemini_type

# Protocol constants
from .protocol import (
    GEMINI_DEFAULT_PORT,
    GEMINI_MAX_URL_LENGTH,
    GEMINI_SCHEME,
    MIME_GEMINI,
    MIME_PLAIN,
    MAX_REDIRECTS,
)
