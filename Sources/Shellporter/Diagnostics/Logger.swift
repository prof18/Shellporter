import Foundation

/// Simple file logger writing to `~/Library/Logs/Shellporter/app.log`.
///
/// `@unchecked Sendable` because thread safety is provided by the serial dispatch queue,
/// which the compiler can't verify statically. All file I/O goes through the queue.
/// Rotates at 2 MB: current log -> `app.1.log` backup, then start fresh.
final class Logger: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.shellporter.logger", qos: .utility)
    private let fileURL: URL
    private let dateFormatter = ISO8601DateFormatter()
    private static let maxFileSize: UInt64 = 2 * 1024 * 1024 // 2 MB

    init(fileManager: FileManager = .default) {
        let logsDir = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("Shellporter", isDirectory: true)
            ?? URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Logs/Shellporter", isDirectory: true)
        self.fileURL = logsDir.appendingPathComponent("app.log")
        try? fileManager.createDirectory(at: logsDir, withIntermediateDirectories: true)
    }

    func log(_ message: String) {
        let fileURL = self.fileURL
        let now = Date()

        queue.async { [self] in
            rotateIfNeeded(fileURL: fileURL)

            let timestamp = dateFormatter.string(from: now)
            let line = "[\(timestamp)] \(message)\n"
            if let data = line.data(using: .utf8) {
                if FileManager.default.fileExists(atPath: fileURL.path),
                   let handle = try? FileHandle(forWritingTo: fileURL) {
                    defer { try? handle.close() }
                    _ = try? handle.seekToEnd()
                    try? handle.write(contentsOf: data)
                } else {
                    try? data.write(to: fileURL, options: .atomic)
                }
            }
        }
    }

    private func rotateIfNeeded(fileURL: URL) {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let size = attrs[.size] as? UInt64,
              size > Self.maxFileSize else {
            return
        }
        let backupURL = fileURL.deletingLastPathComponent().appendingPathComponent("app.1.log")
        try? FileManager.default.removeItem(at: backupURL)
        try? FileManager.default.moveItem(at: fileURL, to: backupURL)
    }
}
