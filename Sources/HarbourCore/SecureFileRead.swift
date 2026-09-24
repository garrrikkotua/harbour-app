import Foundation
import Darwin

/// Reading files that live in a user-writable location from the root daemon.
///
/// The runtime additions file sits in the user's Application Support folder.
/// A plain `Data(contentsOf:)` follows symlinks and blocks on FIFOs, so the
/// user could hang the enforcement loop forever (the timer would never expire
/// and the Mac would stay blocked) or point it at /dev/zero to exhaust memory.
public enum SecureFileRead {

    /// Contents of a regular file at `path`, or nil if the final component is
    /// a symlink, the file is not a regular file, or it exceeds `maxBytes`.
    /// Never blocks on FIFOs or devices.
    public static func regularFile(atPath path: String, maxBytes: Int) -> Data? {
        let fd = open(path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { return nil }
        defer { close(fd) }

        var info = stat()
        guard fstat(fd, &info) == 0,
              info.st_mode & S_IFMT == S_IFREG,
              info.st_size >= 0, info.st_size <= off_t(maxBytes)
        else { return nil }

        // Read at most one byte past the limit so a file that grows after
        // fstat is still rejected rather than truncated.
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16 * 1024)
        while data.count <= maxBytes {
            let n = buffer.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
            if n < 0 {
                if errno == EINTR { continue }
                return nil
            }
            if n == 0 { break }
            data.append(contentsOf: buffer[0..<n])
        }
        return data.count <= maxBytes ? data : nil
    }
}
