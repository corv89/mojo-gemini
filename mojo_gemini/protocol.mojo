"""Gemini protocol constants and definitions.

The Gemini protocol specification can be found at:
gemini://geminiprotocol.net/docs/specification.gmi
"""

# Default Gemini port (Gemini 3 mission launched in March 1965)
comptime GEMINI_DEFAULT_PORT = 1965

# Maximum URL length per specification (1024 bytes including scheme)
comptime GEMINI_MAX_URL_LENGTH = 1024

# Maximum meta line length (1024 characters)
comptime GEMINI_MAX_META_LENGTH = 1024

# Protocol scheme
comptime GEMINI_SCHEME = "gemini"

# Response line terminator
comptime CRLF = "\r\n"

# Default MIME types
comptime MIME_GEMINI = "text/gemini"
comptime MIME_PLAIN = "text/plain"

# Maximum redirect count (spec recommends clients limit to 5)
comptime MAX_REDIRECTS = 5

# Read buffer size for responses
comptime READ_BUFFER_SIZE = 4096
