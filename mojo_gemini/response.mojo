"""Gemini client response handling.

Provides GeminiResponse for handling responses received from Gemini servers.
After receiving the response header (status + meta), call body() to read
the response body (only valid for success status 2x).
"""

from memory import UnsafePointer

from mojo_tls import TLSStream

from .status import Status
from .protocol import READ_BUFFER_SIZE


struct GeminiResponse(Movable):
    """Response received from a Gemini server.

    Contains the status code, meta line, and access to the response body.
    The body can only be read once and is only present for success (2x) responses.

    Example:
        var response = client.request("gemini://example.com/")
        if response.is_success():
            print("MIME:", response.mime_type())
            print(response.body())
        else:
            print("Error:", response.meta)
    """

    var status: Status
    var meta: String
    var _stream: TLSStream
    var _body_read: Bool

    fn __init__(
        out self, status: Status, meta: String, var stream: TLSStream
    ):
        """Create a response with status, meta, and underlying stream.

        Args:
            status: Response status code.
            meta: Meta line (meaning depends on status).
            stream: TLS stream for reading body (takes ownership).
        """
        self.status = status
        self.meta = meta
        self._stream = stream^
        self._body_read = False

    fn __moveinit__(out self, deinit existing: Self):
        """Move constructor."""
        self.status = existing.status
        self.meta = existing.meta^
        self._stream = existing._stream^
        self._body_read = existing._body_read

    fn body(mut self) raises -> String:
        """Read the complete response body.

        Only valid for success responses (status 2x).
        Can only be called once - subsequent calls raise an error.
        The connection is closed after reading.

        Returns:
            Response body as string.

        Raises:
            If body was already read or read error occurs.
        """
        if self._body_read:
            raise Error("Response body already read")
        self._body_read = True

        var result = List[UInt8]()
        var buf = List[UInt8](capacity=READ_BUFFER_SIZE)
        buf.resize(READ_BUFFER_SIZE, 0)

        while True:
            try:
                var n = self._stream.read(buf.unsafe_ptr(), READ_BUFFER_SIZE)
                if n == 0:
                    break
                for i in range(n):
                    result.append(buf[i])
            except e:
                # EOF or close_notify is normal end of response
                var err_str = String(e)
                if "close_notify" in err_str or "EOF" in err_str or "peer closed" in err_str.lower():
                    break
                raise e^

        self._close()
        # Build string from bytes (can't use String(ptr, len) directly)
        var s = String()
        for i in range(len(result)):
            s += chr(Int(result[i]))
        return s

    fn body_bytes(mut self) raises -> List[UInt8]:
        """Read the complete response body as bytes.

        Use this for binary content (images, etc.).
        Can only be called once.

        Returns:
            Response body as byte list.

        Raises:
            If body was already read or read error occurs.
        """
        if self._body_read:
            raise Error("Response body already read")
        self._body_read = True

        var result = List[UInt8]()
        var buf = List[UInt8](capacity=READ_BUFFER_SIZE)
        buf.resize(READ_BUFFER_SIZE, 0)

        while True:
            try:
                var n = self._stream.read(buf.unsafe_ptr(), READ_BUFFER_SIZE)
                if n == 0:
                    break
                for i in range(n):
                    result.append(buf[i])
            except e:
                var err_str = String(e)
                if "close_notify" in err_str or "EOF" in err_str or "peer closed" in err_str.lower():
                    break
                raise e^

        self._close()
        return result^

    fn read_chunk(
        mut self, buf: UnsafePointer[UInt8], max_len: Int
    ) raises -> Int:
        """Read a chunk of the response body.

        Use this for streaming large responses. Returns 0 when body is complete.
        The body_read flag is set on the first call.

        Args:
            buf: Buffer to store received data.
            max_len: Maximum number of bytes to read.

        Returns:
            Number of bytes read, or 0 if complete.

        Raises:
            If read error occurs.
        """
        self._body_read = True
        try:
            return self._stream.read(buf, max_len)
        except e:
            var err_str = String(e)
            if "close_notify" in err_str or "EOF" in err_str or "peer closed" in err_str.lower():
                self._close()
                return 0
            raise e^

    fn _close(mut self):
        """Close the connection."""
        try:
            self._stream.close()
        except:
            pass

    fn is_success(self) -> Bool:
        """Check if response indicates success (2x)."""
        return self.status.is_success()

    fn is_redirect(self) -> Bool:
        """Check if response is a redirect (3x)."""
        return self.status.is_redirect()

    fn is_input(self) -> Bool:
        """Check if server requests input (1x)."""
        return self.status.is_input()

    fn is_failure(self) -> Bool:
        """Check if response indicates failure (4x or 5x)."""
        return self.status.is_failure()

    fn mime_type(self) -> String:
        """Get MIME type from meta (for success responses).

        Returns the MIME type portion of meta, stripping any
        parameters (charset, etc.).

        Returns:
            MIME type string, or empty string if not a success response.
        """
        if not self.is_success():
            return ""

        # Find semicolon for parameters
        var semicolon_pos = -1
        for i in range(len(self.meta)):
            if self.meta[i] == ";":
                semicolon_pos = i
                break

        var mime: String
        if semicolon_pos >= 0:
            mime = String(self.meta[:semicolon_pos])
        else:
            mime = self.meta

        # Trim whitespace
        var start = 0
        var end = len(mime)
        while start < end and (mime[start] == " " or mime[start] == "\t"):
            start += 1
        while end > start and (mime[end - 1] == " " or mime[end - 1] == "\t"):
            end -= 1

        return String(mime[start:end])
