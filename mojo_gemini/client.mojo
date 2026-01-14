"""Gemini protocol client.

Provides GeminiClient for making requests to Gemini servers.
Uses mojo_tls with disabled certificate verification (TOFU model)
since Gemini commonly uses self-signed certificates.
"""

from memory import UnsafePointer

from mojo_tls import TLSStream, TLSConfig

from .protocol import GEMINI_DEFAULT_PORT, MAX_REDIRECTS, CRLF, GEMINI_MAX_URL_LENGTH
from .url import GeminiUrl, parse_url, combine_url
from .response import GeminiResponse
from .status import Status


struct GeminiClient(Movable):
    """Gemini protocol client.

    Makes requests to Gemini servers over TLS. Uses TOFU (Trust-On-First-Use)
    model where self-signed certificates are accepted.

    Example:
        var client = GeminiClient()
        var response = client.request("gemini://geminiprotocol.net/")
        if response.is_success():
            print("Content type:", response.mime_type())
            print(response.body())
        elif response.is_redirect():
            print("Redirect to:", response.meta)
        else:
            print("Error:", response.status, response.meta)
    """

    var max_redirects: Int
    var _client_cert_path: String
    var _client_key_path: String

    fn __init__(out self, max_redirects: Int = MAX_REDIRECTS):
        """Create a new Gemini client.

        Args:
            max_redirects: Maximum redirects to follow (default 5, per spec).
        """
        self.max_redirects = max_redirects
        self._client_cert_path = ""
        self._client_key_path = ""

    fn __moveinit__(out self, deinit existing: Self):
        """Move constructor."""
        self.max_redirects = existing.max_redirects
        self._client_cert_path = existing._client_cert_path^
        self._client_key_path = existing._client_key_path^

    fn set_client_certificate(mut self, cert_path: String, key_path: String):
        """Set client certificate for authentication.

        Some Gemini servers require client certificates for identity-based
        access control (status 60 responses).

        Args:
            cert_path: Path to PEM certificate file.
            key_path: Path to PEM private key file.
        """
        self._client_cert_path = cert_path
        self._client_key_path = key_path

    fn request(mut self, url_string: String) raises -> GeminiResponse:
        """Make a Gemini request.

        Automatically follows redirects up to max_redirects.

        Args:
            url_string: Gemini URL to request (e.g., "gemini://example.com/page").

        Returns:
            GeminiResponse with status, meta, and body access.

        Raises:
            On network error, invalid URL, or too many redirects.
        """
        var url = parse_url(url_string)
        var redirects = 0

        while True:
            var response = self._do_request(url)

            if response.status.is_redirect():
                redirects += 1
                if redirects > self.max_redirects:
                    raise Error("Too many redirects (max " + String(self.max_redirects) + ")")

                # Parse redirect target
                var target = response.meta
                if len(target) == 0:
                    raise Error("Empty redirect location")

                url = combine_url(url, target)
                if not url.is_valid():
                    raise Error("Invalid redirect URL: " + target)
                continue

            return response^

    fn request_no_redirect(mut self, url_string: String) raises -> GeminiResponse:
        """Make a Gemini request without following redirects.

        Use this when you want to handle redirects manually.

        Args:
            url_string: Gemini URL to request.

        Returns:
            GeminiResponse (may be a redirect response).

        Raises:
            On network error or invalid URL.
        """
        var url = parse_url(url_string)
        return self._do_request(url)

    fn _do_request(self, url: GeminiUrl) raises -> GeminiResponse:
        """Execute a single request (no redirect following).

        Args:
            url: Parsed URL to request.

        Returns:
            Response from server.

        Raises:
            On connection or protocol error.
        """
        # Create TLS config with disabled verification (TOFU model)
        var config = TLSConfig()
        config.set_client_mode()
        config.set_verify_none()  # Accept self-signed certificates

        # Load client certificate if configured
        if len(self._client_cert_path) > 0:
            config.load_own_cert_and_key(
                self._client_cert_path, self._client_key_path
            )

        # Connect
        var port_str = String(url.port)
        var stream = TLSStream(config^)
        stream._connect(url.hostname, port_str)

        # Send request: <URL><CR><LF>
        var request_line = url.to_request_string() + CRLF
        if len(request_line) > GEMINI_MAX_URL_LENGTH + 2:
            raise Error("Request URL too long")
        _ = stream.write_all(request_line)

        # Read response header: <status><space><meta><CR><LF>
        var header = self._read_header(stream)

        # Parse status (first 2 chars) and meta
        if len(header) < 2:
            raise Error("Malformed response: status too short")

        var status = Status.parse(header)

        # Meta starts after status and space
        var meta = ""
        if len(header) > 3:
            meta = String(header[3:])
        elif len(header) > 2 and header.as_bytes()[2] != ord(" "):
            # Status without space (technically non-compliant but handle it)
            meta = String(header[2:])

        return GeminiResponse(status, meta, stream^)

    fn _read_header(self, mut stream: TLSStream) raises -> String:
        """Read response header line (until CRLF).

        Args:
            stream: TLS stream to read from.

        Returns:
            Header line without CRLF.

        Raises:
            On read error or malformed header.
        """
        var result = List[UInt8]()
        var buf = List[UInt8](capacity=1)
        buf.resize(1, 0)

        # Read up to reasonable limit (status + space + 1024 meta + CRLF)
        var max_header = 1030

        while len(result) < max_header:
            var n = stream.read(buf.unsafe_ptr(), 1)
            if n == 0:
                break
            var ch = buf[0]
            if ch == ord("\n"):
                # Strip trailing CR if present
                if len(result) > 0 and result[len(result) - 1] == ord("\r"):
                    _ = result.pop()
                break
            result.append(ch)

        if len(result) == 0:
            raise Error("Empty response from server")

        # Build string from bytes
        var s = String()
        for i in range(len(result)):
            s += chr(Int(result[i]))
        return s
