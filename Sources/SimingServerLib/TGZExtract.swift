import Foundation
#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif

/// Extracts `tgzPath` into a fresh temp directory named `<prefix>-<uuid>` and returns it,
/// or `nil` when extraction fails. The caller owns (and removes) the directory.
///
/// Spawns `/usr/bin/tar` with `posix_spawn` and reaps it with a blocking `waitpid`,
/// deliberately bypassing Foundation's `Process`. On Linux, `Process.waitUntilExit()`
/// learns of child exit through a SIGCHLD dispatch source and a run-loop wakeup; on
/// Docker Desktop (linuxkit 6.12) that wakeup was observed to never arrive — tar exited
/// and was reaped, yet the server hung at startup before its first log line.
/// `waitpid` on our own pid has no such hand-off to lose.
func extractTGZ(_ tgzPath: String, prefix: String) -> URL? {
    let fm = FileManager.default
    let tempDir = fm.temporaryDirectory.appendingPathComponent("\(prefix)-\(UUID().uuidString)")
    guard (try? fm.createDirectory(at: tempDir, withIntermediateDirectories: true)) != nil
    else { return nil }

    let args = ["/usr/bin/tar", "xzf", tgzPath, "-C", tempDir.path]
    var argv: [UnsafeMutablePointer<CChar>?] = args.map { strdup($0) } + [nil]
    defer { for p in argv { free(p) } }

    var pid = pid_t()
    guard posix_spawn(&pid, args[0], nil, nil, &argv, environ) == 0 else {
        try? fm.removeItem(at: tempDir)
        return nil
    }

    var status: Int32 = 0
    var rc: pid_t
    repeat { rc = waitpid(pid, &status, 0) } while rc == -1 && errno == EINTR

    // WIFEXITED && WEXITSTATUS == 0, spelled out: the C macros are not imported into Swift.
    guard rc == pid, status & 0x7f == 0, (status >> 8) & 0xff == 0 else {
        try? fm.removeItem(at: tempDir)
        return nil
    }
    return tempDir
}
