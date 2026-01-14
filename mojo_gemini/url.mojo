"""Gemini URL parsing and manipulation.

Handles gemini:// URLs with minimal parsing. Per Gemini spec:
- Scheme MUST be "gemini"
- Userinfo portion MUST NOT be used
- Default port is 1965
- Empty path and "/" are equivalent
"""

from .protocol import GEMINI_SCHEME, GEMINI_DEFAULT_PORT, GEMINI_MAX_URL_LENGTH


struct GeminiUrl(Stringable, Copyable, Movable):
    """Parsed Gemini URL."""

    var scheme: String
    var hostname: String
    var port: Int
    var path: String
    var query: String

    fn __init__(out self):
        """Create empty URL."""
        self.scheme = GEMINI_SCHEME
        self.hostname = ""
        self.port = GEMINI_DEFAULT_PORT
        self.path = "/"
        self.query = ""

    fn __init__(
        out self,
        scheme: String,
        hostname: String,
        port: Int,
        path: String,
        query: String,
    ):
        """Create URL with all components."""
        self.scheme = scheme
        self.hostname = hostname
        self.port = port
        self.path = path if len(path) > 0 else "/"
        self.query = query

    fn is_valid(self) -> Bool:
        """Check if URL is valid for Gemini protocol."""
        return (
            self.scheme == GEMINI_SCHEME
            and len(self.hostname) > 0
            and self.port > 0
            and self.port < 65536
        )

    fn to_request_string(self) -> String:
        """Build the request string to send to server.

        Format: gemini://hostname[:port]/path[?query]
        """
        var result = self.scheme + "://" + self.hostname
        if self.port != GEMINI_DEFAULT_PORT:
            result += ":" + String(self.port)
        result += self.path
        if len(self.query) > 0:
            result += "?" + self.query
        return result

    fn __str__(self) -> String:
        return self.to_request_string()


fn parse_url(url_string: String) raises -> GeminiUrl:
    """Parse a Gemini URL string.

    Args:
        url_string: URL to parse (e.g., "gemini://example.com/path?query")

    Returns:
        Parsed GeminiUrl struct.

    Raises:
        If URL is malformed, exceeds 1024 bytes, or has wrong scheme.
    """
    if len(url_string) > GEMINI_MAX_URL_LENGTH:
        raise Error("URL exceeds maximum length of 1024 bytes")

    var s = url_string

    # Parse scheme
    var scheme_end = _find(s, "://")
    if scheme_end < 0:
        raise Error("Invalid URL: missing scheme separator")

    var scheme = String(s[:scheme_end]).lower()
    if scheme != GEMINI_SCHEME:
        raise Error("Invalid scheme: " + scheme + " (expected gemini)")

    s = String(s[scheme_end + 3 :])  # Skip "://"

    # Parse hostname and port
    var hostname: String = ""
    var port = GEMINI_DEFAULT_PORT

    # Check for IPv6 address in brackets
    if len(s) > 0 and s[0] == "[":
        var bracket_end = _find(s, "]")
        if bracket_end < 0:
            raise Error("Invalid URL: unclosed IPv6 bracket")
        hostname = String(s[1:bracket_end])  # Without brackets
        s = String(s[bracket_end + 1 :])
    else:
        # Find end of host (port separator, path, or query)
        var host_end = len(s)
        var colon_pos = _find(s, ":")
        var slash_pos = _find(s, "/")
        var query_pos = _find(s, "?")

        if colon_pos >= 0 and (slash_pos < 0 or colon_pos < slash_pos):
            host_end = colon_pos
        elif slash_pos >= 0:
            host_end = slash_pos
        elif query_pos >= 0:
            host_end = query_pos

        hostname = String(s[:host_end])
        s = String(s[host_end:])

    if len(hostname) == 0:
        raise Error("Invalid URL: missing hostname")

    # Parse port if present
    if len(s) > 0 and s[0] == ":":
        s = String(s[1:])  # Skip ":"
        var port_end = len(s)
        var slash_pos = _find(s, "/")
        var query_pos = _find(s, "?")

        if slash_pos >= 0:
            port_end = slash_pos
        elif query_pos >= 0:
            port_end = query_pos

        if port_end > 0:
            var port_str = String(s[:port_end])
            port = Int(atol(port_str))
            if port <= 0 or port > 65535:
                raise Error("Invalid port: " + port_str)
        s = String(s[port_end:])

    # Parse path and query
    var path: String = "/"
    var query: String = ""

    if len(s) > 0:
        var query_pos = _find(s, "?")
        if query_pos >= 0:
            if query_pos > 0:
                path = String(s[:query_pos])
            else:
                path = "/"
            query = String(s[query_pos + 1 :])
        else:
            path = s

    if len(path) == 0:
        path = "/"

    return GeminiUrl(scheme, hostname, port, path, query)


fn combine_url(base: GeminiUrl, target: String) raises -> GeminiUrl:
    """Combine base URL with a relative or absolute target.

    Used for handling redirects. If target is absolute (starts with
    gemini://), it's parsed directly. Otherwise, it's resolved relative
    to the base URL.

    Args:
        base: The base URL (e.g., current page).
        target: The redirect target (absolute or relative).

    Returns:
        Combined URL.
    """
    # Check if target is absolute
    if target.startswith("gemini://"):
        return parse_url(target)

    # Relative URL - combine with base
    var path: String = ""
    var query: String = ""

    # Check for query
    var query_pos = _find(target, "?")
    if query_pos >= 0:
        path = String(target[:query_pos])
        query = String(target[query_pos + 1 :])
    else:
        path = target

    # Handle different relative path types
    if len(path) > 0 and path[0] == "/":
        # Absolute path (but relative host)
        pass
    elif len(path) == 0:
        # Query-only redirect
        path = base.path
    else:
        # Relative path - resolve against base
        var base_dir = base.path
        var last_slash = _rfind(base_dir, "/")
        if last_slash >= 0:
            base_dir = String(base_dir[: last_slash + 1])
        else:
            base_dir = "/"
        path = _normalize_path(base_dir + path)

    return GeminiUrl(base.scheme, base.hostname, base.port, path, query)


fn _find(s: String, sub: String) -> Int:
    """Find first occurrence of substring. Returns -1 if not found."""
    var sub_len = len(sub)
    if sub_len == 0:
        return 0
    if sub_len > len(s):
        return -1

    for i in range(len(s) - sub_len + 1):
        var found = True
        for j in range(sub_len):
            if s[i + j] != sub[j]:
                found = False
                break
        if found:
            return i
    return -1


fn _rfind(s: String, sub: String) -> Int:
    """Find last occurrence of substring. Returns -1 if not found."""
    var sub_len = len(sub)
    if sub_len == 0:
        return len(s)
    if sub_len > len(s):
        return -1

    for i in range(len(s) - sub_len, -1, -1):
        var found = True
        for j in range(sub_len):
            if s[i + j] != sub[j]:
                found = False
                break
        if found:
            return i
    return -1


fn _normalize_path(path: String) -> String:
    """Normalize path by resolving . and .. components."""
    var parts = List[String]()
    var current = String("")

    for i in range(len(path)):
        var c = path[i]
        if c == "/":
            if current == "..":
                if len(parts) > 0:
                    _ = parts.pop()
            elif current != "." and len(current) > 0:
                parts.append(current)
            current = String("")
        else:
            current += c

    # Handle last component
    if current == "..":
        if len(parts) > 0:
            _ = parts.pop()
    elif current != "." and len(current) > 0:
        parts.append(current)

    # Rebuild path
    if len(parts) == 0:
        return "/"

    var result = String("")
    for i in range(len(parts)):
        result += "/" + parts[i]

    # Preserve trailing slash if original had one
    if len(path) > 0 and path[len(path) - 1] == "/":
        result += "/"

    return result if len(result) > 0 else "/"
