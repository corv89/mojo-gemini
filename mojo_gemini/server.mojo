"""Gemini protocol server.

Provides GeminiServer for serving Gemini content.
Uses mojo_tls TLSListener for accepting TLS connections.
"""

from memory import UnsafePointer

from mojo_tls import TLSListener, TLSConfig, TLSClientConnection

from .protocol import GEMINI_DEFAULT_PORT, GEMINI_MAX_URL_LENGTH, CRLF
from .request import GeminiRequest
from .status import Status, BAD_REQUEST, TEMP_FAILURE
from .url import parse_url


struct GeminiServer(Movable):
    """Gemini protocol server.

    Binds to a port and serves Gemini requests. Each request is handled
    by a user-provided callback function.

    Example:
        fn handler(mut req: GeminiRequest) raises:
            if req.path() == "/":
                req.respond_success("text/gemini", "# Hello, Gemini!")
            else:
                req.respond_not_found()

        fn main() raises:
            var server = GeminiServer.bind("server.crt", "server.key")
            print("Listening on port 1965...")
            server.serve(handler)

    Note: The server runs synchronously, handling one request at a time.
    For production use, consider spawning a new process/thread per request.
    """

    var _listener: TLSListener

    fn __init__(out self, var listener: TLSListener):
        """Create server from TLS listener.

        Args:
            listener: Bound TLS listener (takes ownership).
        """
        self._listener = listener^

    fn __moveinit__(out self, deinit existing: Self):
        """Move constructor."""
        self._listener = existing._listener^

    @staticmethod
    fn bind(
        cert_path: String,
        key_path: String,
        address: String = "0.0.0.0",
        port: Int = GEMINI_DEFAULT_PORT,
    ) raises -> GeminiServer:
        """Create a Gemini server bound to the given address.

        Args:
            cert_path: Path to server certificate file (PEM).
            key_path: Path to server private key file (PEM).
            address: Address to bind to (default "0.0.0.0" for all interfaces).
            port: Port to listen on (default 1965).

        Returns:
            GeminiServer ready to accept connections.

        Raises:
            If binding or certificate loading fails.
        """
        var port_str = String(port)
        var listener = TLSListener.bind(cert_path, key_path, address, port_str)
        return GeminiServer(listener^)

    fn serve[
        F: fn (mut GeminiRequest) raises -> None
    ](mut self) raises:
        """Start serving requests indefinitely.

        Blocks and handles requests in a loop. Each connection is handled
        synchronously - the server processes one request at a time.

        Type Parameters:
            F: Handler function to call for each request. The handler receives
                a GeminiRequest and should call one of its respond methods.

        Raises:
            If a fatal server error occurs. Individual request errors are
            caught and result in error responses to the client.
        """
        while True:
            self._handle_one[F]()

    fn serve_one[
        F: fn (mut GeminiRequest) raises -> None
    ](mut self) raises:
        """Handle a single request.

        Useful for testing or controlled request handling.

        Type Parameters:
            F: Handler function to call for the request.

        Raises:
            If accept or handler fails.
        """
        self._handle_one[F]()

    fn _handle_one[
        F: fn (mut GeminiRequest) raises -> None
    ](mut self) raises:
        """Accept and handle one connection.

        Type Parameters:
            F: Request handler function.

        Raises:
            If accept fails.
        """
        # Accept connection
        var client = self._listener.accept()

        try:
            # Perform TLS handshake
            client.handshake()

            # Read request line (URL)
            var request_line = self._read_request_line(client)

            # Validate length
            if len(request_line) > GEMINI_MAX_URL_LENGTH:
                self._send_error(client, BAD_REQUEST, "URL too long")
                return

            # Parse URL
            var url = parse_url(request_line)

            if not url.is_valid():
                self._send_error(client, BAD_REQUEST, "Invalid URL")
                return

            # Create request and call handler
            var request = GeminiRequest(url^, request_line, client^)

            try:
                F(request)
            except e:
                # If handler didn't respond, send error
                if not request.has_responded():
                    try:
                        request.respond(TEMP_FAILURE, "Internal server error")
                    except:
                        pass

        except e:
            # Send error response if possible
            try:
                self._send_error(client, BAD_REQUEST, String(e))
            except:
                pass

    fn _read_request_line(
        self, mut client: TLSClientConnection
    ) raises -> String:
        """Read the request line (URL followed by CRLF).

        Args:
            client: Client connection to read from.

        Returns:
            URL string without CRLF.

        Raises:
            If read fails or request is malformed.
        """
        var result = List[UInt8]()
        var buf = List[UInt8](capacity=1)
        buf.resize(1, 0)

        # Read until CRLF, with limit
        var max_len = GEMINI_MAX_URL_LENGTH + 2  # URL + CRLF

        while len(result) <= max_len:
            var n = client.read(buf.unsafe_ptr(), 1)
            if n == 0:
                raise Error("Connection closed before request complete")
            var ch = buf[0]
            if ch == ord("\n"):
                # Strip trailing CR
                if len(result) > 0 and result[len(result) - 1] == ord("\r"):
                    _ = result.pop()
                break
            result.append(ch)

        if len(result) == 0:
            raise Error("Empty request")

        # Build string from bytes
        var s = String()
        for i in range(len(result)):
            s += chr(Int(result[i]))
        return s

    fn _send_error(
        self,
        mut client: TLSClientConnection,
        status: Status,
        message: String,
    ):
        """Send error response and close connection.

        Args:
            client: Client connection.
            status: Error status code.
            message: Error message.
        """
        try:
            var response = String(status.code) + " " + message + CRLF
            _ = client.write_all(response)
            client.close()
        except:
            pass

    fn is_bound(self) -> Bool:
        """Check if the server is bound to a port.

        Returns:
            True if server is bound and ready to accept.
        """
        return self._listener.is_bound()
