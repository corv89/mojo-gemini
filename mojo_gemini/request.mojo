"""Gemini server request handling.

Provides GeminiRequest for handling requests received by a Gemini server.
Contains the parsed URL and methods for sending responses to the client.
"""

from memory import UnsafePointer

from mojo_tls import TLSClientConnection

from .url import GeminiUrl
from .status import (
    Status,
    INPUT,
    SENSITIVE_INPUT,
    TEMP_REDIRECT,
    REDIRECT,
    NOT_FOUND,
    PERM_FAILURE,
    TEMP_FAILURE,
    CERT_REQUIRED,
    CERT_UNAUTHORIZED,
    CERT_INVALID,
)
from .protocol import CRLF


struct GeminiRequest(Movable):
    """Request received by a Gemini server.

    Contains the parsed URL and client connection. Use respond() methods
    to send a response to the client.

    Example:
        fn handler(mut req: GeminiRequest) raises:
            if req.path() == "/":
                req.respond_success("text/gemini", "# Welcome to my Gemini server!")
            elif req.path() == "/search":
                if len(req.query()) == 0:
                    req.respond(INPUT, "Enter search query:")
                else:
                    req.respond_success("text/gemini", "Results for: " + req.query())
            else:
                req.respond(NOT_FOUND, "Page not found")
    """

    var url: GeminiUrl
    var raw_url: String
    var _client: TLSClientConnection
    var _responded: Bool

    fn __init__(
        out self,
        var url: GeminiUrl,
        raw_url: String,
        var client: TLSClientConnection,
    ):
        """Create a request with URL and client connection.

        Args:
            url: Parsed Gemini URL from request.
            raw_url: Original URL string from request line.
            client: TLS client connection (takes ownership).
        """
        self.url = url^
        self.raw_url = raw_url
        self._client = client^
        self._responded = False

    fn __moveinit__(out self, deinit existing: Self):
        """Move constructor."""
        self.url = existing.url^
        self.raw_url = existing.raw_url^
        self._client = existing._client^
        self._responded = existing._responded

    fn respond(mut self, status: Status, meta: String) raises:
        """Send a response without body.

        Use for non-success responses (redirect, error, input request, etc.).
        The connection is closed after sending.

        Args:
            status: Response status code.
            meta: Meta information (varies by status):
                - Input (1x): prompt string
                - Redirect (3x): target URL
                - Failure (4x/5x): error message
                - Cert (6x): certificate info

        Raises:
            If already responded or write fails.
        """
        if self._responded:
            raise Error("Already responded to request")
        self._responded = True

        var header = String(status.code) + " " + meta + CRLF
        _ = self._client.write_all(header)
        self._close()

    fn respond_success(mut self, mime_type: String, body: String) raises:
        """Send a success response with text body.

        Args:
            mime_type: MIME type of content (e.g., "text/gemini", "text/plain").
            body: Response body content.

        Raises:
            If already responded or write fails.
        """
        if self._responded:
            raise Error("Already responded to request")
        self._responded = True

        var header = "20 " + mime_type + CRLF
        _ = self._client.write_all(header)
        _ = self._client.write_all(body)
        self._close()

    fn respond_success_bytes(
        mut self,
        mime_type: String,
        body: UnsafePointer[UInt8],
        length: Int,
    ) raises:
        """Send a success response with binary body.

        Use for binary content like images.

        Args:
            mime_type: MIME type of content (e.g., "image/png").
            body: Pointer to body data.
            length: Length of body in bytes.

        Raises:
            If already responded or write fails.
        """
        if self._responded:
            raise Error("Already responded to request")
        self._responded = True

        var header = "20 " + mime_type + CRLF
        _ = self._client.write_all(header)
        _ = self._client.write(body, length)
        self._close()

    fn respond_input(mut self, prompt: String) raises:
        """Send an input request (status 10).

        Client should prompt user for input and re-request with query string.

        Args:
            prompt: Prompt string to show user.
        """
        self.respond(INPUT, prompt)

    fn respond_sensitive_input(mut self, prompt: String) raises:
        """Send a sensitive input request (status 11).

        Client should prompt for password/sensitive input (masked display).

        Args:
            prompt: Prompt string to show user.
        """
        self.respond(SENSITIVE_INPUT, prompt)

    fn respond_redirect(mut self, target: String, permanent: Bool = False) raises:
        """Send a redirect response.

        Args:
            target: Target URL (absolute or relative).
            permanent: If True, use permanent redirect (31). Default is temporary (30).
        """
        var status = REDIRECT if permanent else TEMP_REDIRECT
        self.respond(status, target)

    fn respond_not_found(mut self, message: String = "Not found") raises:
        """Send a not found response (status 51)."""
        self.respond(NOT_FOUND, message)

    fn respond_error(mut self, message: String) raises:
        """Send a permanent failure response (status 50)."""
        self.respond(PERM_FAILURE, message)

    fn respond_temp_error(mut self, message: String) raises:
        """Send a temporary failure response (status 40)."""
        self.respond(TEMP_FAILURE, message)

    fn path(self) -> String:
        """Get the request path.

        Returns:
            Path component of URL (e.g., "/page/subpage").
        """
        return self.url.path

    fn query(self) -> String:
        """Get the query string.

        Returns:
            Query string from URL, or empty string if none.
        """
        return self.url.query

    fn hostname(self) -> String:
        """Get the requested hostname.

        Useful for virtual hosting (multiple domains on one server).

        Returns:
            Hostname from URL.
        """
        return self.url.hostname

    fn port(self) -> Int:
        """Get the requested port.

        Returns:
            Port number from URL (default 1965).
        """
        return self.url.port

    fn has_responded(self) -> Bool:
        """Check if a response has been sent.

        Returns:
            True if respond() or respond_success() was called.
        """
        return self._responded

    # --- Client Certificate Methods ---

    fn has_client_cert(self) -> Bool:
        """Check if the client presented a certificate.

        Use this to check for client identity before accessing protected resources.
        Only meaningful when server was created with client_auth="optional" or "required".

        Returns:
            True if client certificate is available.
        """
        return self._client.has_peer_cert()

    fn client_cert_fingerprint(self) raises -> String:
        """Get SHA-256 fingerprint of the client's certificate.

        The fingerprint is a 64-character lowercase hex string representing
        the SHA-256 hash of the DER-encoded certificate. This can be used
        as a persistent client identity.

        Returns:
            64-character hex string.

        Raises:
            If no client certificate is available.
        """
        return self._client.get_peer_cert_fingerprint_hex()

    fn verify_client_cert(self, expected_fingerprint: String) raises -> Bool:
        """Verify client certificate fingerprint matches expected value.

        Args:
            expected_fingerprint: Expected SHA-256 fingerprint as hex string
                (case-insensitive).

        Returns:
            True if fingerprint matches.

        Raises:
            If no client certificate is available.
        """
        return self._client.verify_peer_cert_fingerprint(expected_fingerprint)

    # --- Certificate Response Methods ---

    fn respond_cert_required(
        mut self, message: String = "Client certificate required"
    ) raises:
        """Request client certificate (status 60).

        The client should reconnect with a certificate.

        Args:
            message: Message to display to user.
        """
        self.respond(CERT_REQUIRED, message)

    fn respond_cert_unauthorized(
        mut self, message: String = "Certificate not authorized"
    ) raises:
        """Reject unauthorized certificate (status 61).

        The client's certificate is not authorized for this resource.

        Args:
            message: Message to display to user.
        """
        self.respond(CERT_UNAUTHORIZED, message)

    fn respond_cert_invalid(
        mut self, message: String = "Certificate not valid"
    ) raises:
        """Reject invalid certificate (status 62).

        The client's certificate is malformed or otherwise invalid.

        Args:
            message: Message to display to user.
        """
        self.respond(CERT_INVALID, message)

    fn _close(mut self):
        """Close the connection."""
        try:
            self._client.close()
        except:
            pass
