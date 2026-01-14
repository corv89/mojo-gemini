"""FFI bindings for POSIX signal handling.

Provides signal constants and the signal() function for signal handling.
"""

from sys.ffi import external_call

comptime c_int = Int32

# Signal numbers - portable across platforms
comptime SIGTERM: c_int = 15
"""Termination signal."""

comptime SIGINT: c_int = 2
"""Interrupt signal (Ctrl+C)."""

comptime SIGHUP: c_int = 1
"""Hangup signal."""

# SIGCHLD differs: macOS = 20, Linux = 17
# TODO: Add proper cross-platform detection when Mojo's is_triple patterns are better documented
comptime SIGCHLD: c_int = 20  # macOS value; change to 17 for Linux


fn get_sigchld() -> c_int:
    """Get SIGCHLD value for the current platform.

    Currently returns macOS value (20). For Linux, SIGCHLD is 17.

    Returns:
        The SIGCHLD signal number.
    """
    return SIGCHLD


# Signal handler constants
comptime SIG_DFL: Int = 0
"""Default signal handler."""

comptime SIG_IGN: Int = 1
"""Ignore signal."""


fn signal(signum: c_int, handler: Int) -> Int:
    """Set the signal handler for a signal.

    Args:
        signum: The signal number.
        handler: The handler - use SIG_IGN to ignore, SIG_DFL for default,
                or a function pointer for custom handling.

    Returns:
        The previous handler value, or SIG_ERR (-1) on error.
    """
    return external_call["signal", Int, c_int, Int](signum, handler)
