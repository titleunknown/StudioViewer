import Foundation

/// Reads a child process's output (the viewer's, or cloudflared's) a line at a time and hands each
/// line to the main actor, in order.
///
/// Uses the file handle's readabilityHandler, which Foundation calls on a background queue each
/// time data arrives, until the process closes its end. (An earlier version iterated
/// FileHandle.bytes.lines in a Task; on 2026-10-21 that loop stopped delivering while the viewer
/// kept running, so the viewer blocked writing to a pipe nobody read and the window went stale.)
nonisolated final class PipeLines: @unchecked Sendable {
    private var buffer = Data()  // only touched from the handle's own serial callback queue
    private let deliver: @Sendable (String) -> Void

    init(_ handle: FileHandle, deliver: @escaping @Sendable (String) -> Void) {
        self.deliver = deliver
        handle.readabilityHandler = { [self] handle in
            let data = handle.availableData
            if data.isEmpty {  // end of output: the process has exited
                handle.readabilityHandler = nil
                if !buffer.isEmpty { send(buffer) }
                buffer = Data()
                return
            }
            buffer.append(data)
            while let newline = buffer.firstIndex(of: 0x0A) {
                send(buffer[buffer.startIndex..<newline])
                buffer.removeSubrange(buffer.startIndex...newline)
            }
        }
    }

    private func send(_ bytes: Data) {
        let line = String(decoding: bytes, as: UTF8.self)
        guard !line.isEmpty else { return }
        let deliver = self.deliver
        DispatchQueue.main.async { deliver(line) }  // the main queue keeps the lines in order
    }
}
