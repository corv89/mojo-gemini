"""Prefork Gemini server for concurrent request handling.

Provides PreforkServer which spawns N worker processes, each handling
Gemini requests independently. Uses SO_REUSEPORT so each worker has
its own accept queue - the kernel distributes connections across workers.

Example:
    from mojo_gemini import GeminiRequest
    from mojo_gemini.prefork import PreforkServer

    fn handler(mut req: GeminiRequest) raises:
        req.respond_success("text/gemini", "# Hello from worker!")

    fn main() raises:
        var server = PreforkServer[handler](
            cert_path="server.crt",
            key_path="server.key",
            num_workers=4,
        )
        server.serve()
"""

from time import sleep
from memory import UnsafePointer

from .server import GeminiServer
from .request import GeminiRequest
from ._ffi.process import fork, waitpid, getpid, _exit, WNOHANG, pid_t, c_int
from ._ffi.signal import signal, get_sigchld, SIG_IGN


struct PreforkServer[F: fn (mut GeminiRequest) raises -> None]:
    """Prefork Gemini server with N worker processes.

    Each worker creates its own TLSListener bound to the same port using
    SO_REUSEPORT. The kernel distributes incoming connections across all
    workers, providing natural load balancing without thundering herd.

    Workers run until killed. Master process monitors workers and exits
    when all workers die. Use an external process manager (systemd, etc.)
    for automatic restarts.

    Type Parameters:
        F: Handler function for Gemini requests.
    """

    var cert_path: String
    var key_path: String
    var address: String
    var port: Int
    var num_workers: Int
    var _worker_pids: List[pid_t]
    var _running: Bool

    fn __init__(
        out self,
        cert_path: String,
        key_path: String,
        address: String = "0.0.0.0",
        port: Int = 1965,
        num_workers: Int = 4,
    ):
        """Create a prefork server configuration.

        Args:
            cert_path: Path to server certificate file (PEM).
            key_path: Path to server private key file (PEM).
            address: Address to bind to (default "0.0.0.0").
            port: Port to listen on (default 1965).
            num_workers: Number of worker processes to spawn (default 4).
        """
        self.cert_path = cert_path
        self.key_path = key_path
        self.address = address
        self.port = port
        self.num_workers = num_workers
        self._worker_pids = List[pid_t]()
        self._running = False

    fn serve(mut self) raises:
        """Start the prefork server.

        Spawns num_workers child processes, each handling requests
        independently. Master process monitors workers and exits when
        all workers have died.

        Workers run in an infinite loop handling requests. Kill the
        master process (SIGTERM) to shut down the server.

        Raises:
            If fork() fails.
        """
        self._running = True

        # Ignore SIGCHLD in parent (we poll with waitpid)
        _ = signal(get_sigchld(), SIG_IGN)

        # Spawn workers
        for i in range(self.num_workers):
            var pid = self._spawn_worker()
            if pid > 0:
                self._worker_pids.append(pid)

        print("Master [" + String(getpid()) + "]: spawned " + String(len(self._worker_pids)) + " workers")

        # Master loop: monitor workers with periodic polling
        while self._running and len(self._worker_pids) > 0:
            self._reap_workers()
            sleep(0.1)  # 100ms poll interval to avoid busy-wait

        print("Master [" + String(getpid()) + "]: all workers exited, shutting down")

    fn _spawn_worker(self) raises -> pid_t:
        """Fork and run a worker process.

        Returns:
            Child PID in parent, or 0 in child (but child never returns).

        Raises:
            If fork() fails.
        """
        var pid = fork()

        if pid < 0:
            raise Error("fork() failed")

        if pid == 0:
            # Child process - run worker loop (never returns)
            self._worker_loop()
            _exit(0)  # Should not reach here

        return pid  # Parent returns child PID

    fn _worker_loop(self) raises:
        """Worker main loop: bind and handle requests forever.

        Each worker creates its own listener with SO_REUSEPORT,
        allowing multiple workers to bind to the same port.
        """
        var server = GeminiServer.bind_reuseport(
            self.cert_path,
            self.key_path,
            self.address,
            self.port,
        )

        var worker_pid = getpid()
        print("Worker [" + String(worker_pid) + "]: listening on port " + String(self.port))

        # Handle requests until killed
        while True:
            try:
                server.serve_one[Self.F]()
            except e:
                print("Worker [" + String(worker_pid) + "] error: " + String(e))

    fn _reap_workers(mut self):
        """Check for and clean up dead workers (non-blocking).

        Removes exited workers from the PID list. Called periodically
        by the master process.
        """
        # Allocate status on stack and get pointer
        var status_buf = List[c_int](capacity=1)
        status_buf.resize(1, c_int(0))
        var status_ptr = status_buf.unsafe_ptr()

        while True:
            var pid = waitpid(pid_t(-1), status_ptr, WNOHANG)
            if pid <= 0:
                break

            # Remove from list
            var found_idx = -1
            for i in range(len(self._worker_pids)):
                if self._worker_pids[i] == pid:
                    found_idx = i
                    break

            if found_idx >= 0:
                _ = self._worker_pids.pop(found_idx)
                print("Master [" + String(getpid()) + "]: worker " + String(pid) + " exited")
