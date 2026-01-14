"""MIME type detection for file serving.

Provides detect_mime_type() for determining MIME types from file extensions.
"""

from .protocol import MIME_GEMINI, MIME_PLAIN


fn detect_mime_type(path: String) -> String:
    """Detect MIME type from file extension.

    Args:
        path: File path or filename.

    Returns:
        MIME type string. Defaults to "application/octet-stream" for unknown extensions.
    """
    var ext = _get_extension(path).lower()

    # Gemini-specific
    if ext == ".gmi" or ext == ".gemini":
        return MIME_GEMINI

    # Text formats
    if ext == ".txt":
        return MIME_PLAIN
    if ext == ".md" or ext == ".markdown":
        return "text/markdown"
    if ext == ".html" or ext == ".htm":
        return "text/html"
    if ext == ".css":
        return "text/css"
    if ext == ".csv":
        return "text/csv"
    if ext == ".xml":
        return "text/xml"
    if ext == ".rtf":
        return "text/rtf"

    # Code/config (serve as plain text)
    if ext == ".py" or ext == ".mojo" or ext == ".nim":
        return MIME_PLAIN
    if ext == ".js" or ext == ".ts":
        return "text/javascript"
    if ext == ".json":
        return "application/json"
    if ext == ".yaml" or ext == ".yml":
        return "text/yaml"
    if ext == ".toml":
        return "text/plain"

    # Images
    if ext == ".jpg" or ext == ".jpeg":
        return "image/jpeg"
    if ext == ".png":
        return "image/png"
    if ext == ".gif":
        return "image/gif"
    if ext == ".svg":
        return "image/svg+xml"
    if ext == ".webp":
        return "image/webp"
    if ext == ".ico":
        return "image/x-icon"
    if ext == ".bmp":
        return "image/bmp"

    # Audio
    if ext == ".mp3":
        return "audio/mpeg"
    if ext == ".wav":
        return "audio/wav"
    if ext == ".ogg" or ext == ".oga":
        return "audio/ogg"
    if ext == ".flac":
        return "audio/flac"
    if ext == ".aac":
        return "audio/aac"
    if ext == ".m4a":
        return "audio/mp4"

    # Video
    if ext == ".mp4":
        return "video/mp4"
    if ext == ".webm":
        return "video/webm"
    if ext == ".ogv":
        return "video/ogg"
    if ext == ".avi":
        return "video/x-msvideo"
    if ext == ".mkv":
        return "video/x-matroska"

    # Documents
    if ext == ".pdf":
        return "application/pdf"
    if ext == ".epub":
        return "application/epub+zip"

    # Archives
    if ext == ".zip":
        return "application/zip"
    if ext == ".gz" or ext == ".gzip":
        return "application/gzip"
    if ext == ".tar":
        return "application/x-tar"
    if ext == ".7z":
        return "application/x-7z-compressed"

    # Fonts
    if ext == ".woff":
        return "font/woff"
    if ext == ".woff2":
        return "font/woff2"
    if ext == ".ttf":
        return "font/ttf"
    if ext == ".otf":
        return "font/otf"

    # Default binary
    return "application/octet-stream"


fn _get_extension(path: String) -> String:
    """Extract file extension from path.

    Args:
        path: File path or filename.

    Returns:
        Extension including dot (e.g., ".txt"), or empty string if none.
    """
    var last_dot = -1
    var last_slash = -1

    for i in range(len(path)):
        var c = path[i]
        if c == ".":
            last_dot = i
        elif c == "/" or c == "\\":
            last_slash = i

    # Extension must come after last path separator
    if last_dot > last_slash:
        return path[last_dot:]

    return ""


fn is_text_type(mime_type: String) -> Bool:
    """Check if MIME type represents text content.

    Args:
        mime_type: MIME type string.

    Returns:
        True if content is textual (can be displayed as text).
    """
    if mime_type.startswith("text/"):
        return True
    if mime_type == "application/json":
        return True
    if mime_type == "application/xml":
        return True
    return False


fn is_gemini_type(mime_type: String) -> Bool:
    """Check if MIME type is text/gemini.

    Args:
        mime_type: MIME type string.

    Returns:
        True if this is Gemini markup content.
    """
    return mime_type == MIME_GEMINI or mime_type.startswith("text/gemini;")
