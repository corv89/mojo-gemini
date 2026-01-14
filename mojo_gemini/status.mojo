"""Gemini protocol status codes.

Status codes are organized into 6 categories by first digit:
- 1x: Input expected (prompt user for input)
- 2x: Success (content follows)
- 3x: Redirect (follow URL in meta)
- 4x: Temporary failure (retry later)
- 5x: Permanent failure (do not retry)
- 6x: Client certificate required
"""


@register_passable("trivial")
struct Status(Stringable, Copyable, Movable):
    """Gemini response status code."""

    var code: Int

    fn __init__(out self, code: Int):
        """Create a Status with the given code."""
        self.code = code

    fn category(self) -> Int:
        """Get the status category (first digit)."""
        return self.code // 10

    fn is_input(self) -> Bool:
        """Check if status requires input (1x)."""
        return self.category() == 1

    fn is_success(self) -> Bool:
        """Check if status indicates success (2x)."""
        return self.category() == 2

    fn is_redirect(self) -> Bool:
        """Check if status is a redirect (3x)."""
        return self.category() == 3

    fn is_temp_failure(self) -> Bool:
        """Check if status is temporary failure (4x)."""
        return self.category() == 4

    fn is_perm_failure(self) -> Bool:
        """Check if status is permanent failure (5x)."""
        return self.category() == 5

    fn is_cert_required(self) -> Bool:
        """Check if status requires client certificate (6x)."""
        return self.category() == 6

    fn is_failure(self) -> Bool:
        """Check if status is any failure (4x or 5x)."""
        return self.is_temp_failure() or self.is_perm_failure()

    @staticmethod
    fn from_int(code: Int) -> Status:
        """Create Status from integer code.

        Unknown codes are returned as-is; callers can check validity
        using category methods.
        """
        return Status(code)

    @staticmethod
    fn parse(s: String) raises -> Status:
        """Parse status code from string (first 2 characters).

        Args:
            s: String starting with 2-digit status code.

        Returns:
            Parsed Status.

        Raises:
            If string is too short or not a valid number.
        """
        if len(s) < 2:
            raise Error("Status code too short")
        var code_str = String(s[:2])
        var code = Int(atol(code_str))
        if code < 10 or code > 69:
            raise Error("Invalid status code: " + code_str)
        return Status(code)

    fn __str__(self) -> String:
        """Return string representation (2-digit code)."""
        if self.code < 10:
            return "0" + String(self.code)
        return String(self.code)

    fn __eq__(self, other: Self) -> Bool:
        return self.code == other.code

    fn __ne__(self, other: Self) -> Bool:
        return self.code != other.code


# Status code constants
comptime INPUT = Status(10)
comptime SENSITIVE_INPUT = Status(11)
comptime SUCCESS = Status(20)
comptime TEMP_REDIRECT = Status(30)
comptime REDIRECT = Status(31)
comptime TEMP_FAILURE = Status(40)
comptime SERVER_UNAVAILABLE = Status(41)
comptime CGI_ERROR = Status(42)
comptime PROXY_ERROR = Status(43)
comptime SLOW_DOWN = Status(44)
comptime PERM_FAILURE = Status(50)
comptime NOT_FOUND = Status(51)
comptime GONE = Status(52)
comptime PROXY_REFUSED = Status(53)
comptime BAD_REQUEST = Status(59)
comptime CERT_REQUIRED = Status(60)
comptime CERT_UNAUTHORIZED = Status(61)
comptime CERT_INVALID = Status(62)


fn status_description(status: Status) -> String:
    """Get human-readable description for a status code."""
    if status == INPUT:
        return "Input"
    if status == SENSITIVE_INPUT:
        return "Sensitive Input"
    if status == SUCCESS:
        return "Success"
    if status == TEMP_REDIRECT:
        return "Temporary Redirect"
    if status == REDIRECT:
        return "Permanent Redirect"
    if status == TEMP_FAILURE:
        return "Temporary Failure"
    if status == SERVER_UNAVAILABLE:
        return "Server Unavailable"
    if status == CGI_ERROR:
        return "CGI Error"
    if status == PROXY_ERROR:
        return "Proxy Error"
    if status == SLOW_DOWN:
        return "Slow Down"
    if status == PERM_FAILURE:
        return "Permanent Failure"
    if status == NOT_FOUND:
        return "Not Found"
    if status == GONE:
        return "Gone"
    if status == PROXY_REFUSED:
        return "Proxy Request Refused"
    if status == BAD_REQUEST:
        return "Bad Request"
    if status == CERT_REQUIRED:
        return "Client Certificate Required"
    if status == CERT_UNAUTHORIZED:
        return "Certificate Not Authorized"
    if status == CERT_INVALID:
        return "Certificate Not Valid"
    return "Unknown Status " + String(status.code)
