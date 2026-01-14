"""FFI bindings for POSIX process management.

Provides fork(), waitpid(), getpid(), and _exit() for prefork server architecture.
"""

from sys.ffi import external_call
from memory import UnsafePointer

comptime c_int = Int32
comptime pid_t = Int32


fn fork() -> pid_t:
    """Fork the current process.

    Returns:
        0 in the child process.
        Child's PID in the parent process.
        -1 on error.
    """
    return external_call["fork", pid_t]()


fn waitpid(pid: pid_t, status: UnsafePointer[c_int], options: c_int) -> pid_t:
    """Wait for a child process.

    Args:
        pid: Process ID to wait for (-1 for any child).
        status: Pointer to store exit status.
        options: Wait options (e.g., WNOHANG).

    Returns:
        PID of the terminated child, 0 if WNOHANG and no child exited, -1 on error.
    """
    # Pass pointer as Int address to work around Mojo's UnsafePointer inference
    return external_call["waitpid", pid_t, pid_t, Int, c_int](
        pid, Int(status), options
    )


fn getpid() -> pid_t:
    """Get the current process ID.

    Returns:
        The PID of the calling process.
    """
    return external_call["getpid", pid_t]()


fn _exit(status: c_int):
    """Exit the process immediately without cleanup.

    Use this in forked child processes to avoid running atexit handlers
    or flushing stdio buffers that belong to the parent.

    Args:
        status: Exit status code.
    """
    external_call["_exit", NoneType, c_int](status)


# waitpid options
comptime WNOHANG: c_int = 1
"""Don't block if no child has exited."""

comptime WUNTRACED: c_int = 2
"""Also return if a child has stopped."""
