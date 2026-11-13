import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public enum SocketServer {
    /// Serves the pack API on localhost only. One request at a time is enough for the simulator.
    public static func serve(port: UInt16, app: ServerApp) -> Never {
        let descriptor = socket(AF_INET, socketStream, 0)
        precondition(descriptor >= 0, "socket failed")
        var reuse: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout.size(ofValue: reuse)))

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sock in
                bind(descriptor, sock, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        precondition(bound == 0, "bind failed on 127.0.0.1:\(port)")
        precondition(listen(descriptor, 16) == 0, "listen failed")
        FileHandle.standardOutput.write(Data("Sudoku pack server http://127.0.0.1:\(port) mode=\(app.mode.rawValue)\n".utf8))

        while true {
            let client = accept(descriptor, nil, nil)
            if client < 0 { continue }
            handle(client: client, app: app)
            closeSocket(client)
        }
    }

    private static func handle(client: Int32, app: ServerApp) {
        var collected = Data()
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while collected.count < 262_144 {
            let count = buffer.withUnsafeMutableBytes { raw in
                socketRead(client, raw.baseAddress, raw.count)
            }
            if count <= 0 { break }
            collected.append(buffer, count: count)
            if let request = HTTPParser.parse(collected) {
                let response = app.response(for: request).wireData()
                _ = response.withUnsafeBytes { raw in
                    socketWrite(client, raw.baseAddress, raw.count)
                }
                return
            }
        }
    }

    private static func socketRead(_ fd: Int32, _ buffer: UnsafeMutableRawPointer?, _ count: Int) -> Int {
        #if canImport(Darwin)
        Darwin.read(fd, buffer, count)
        #else
        Glibc.read(fd, buffer, count)
        #endif
    }

    private static func socketWrite(_ fd: Int32, _ buffer: UnsafeRawPointer?, _ count: Int) -> Int {
        #if canImport(Darwin)
        Darwin.write(fd, buffer, count)
        #else
        Glibc.write(fd, buffer, count)
        #endif
    }

    private static var socketStream: Int32 {
        #if canImport(Darwin)
        SOCK_STREAM
        #else
        Int32(SOCK_STREAM.rawValue)
        #endif
    }

    private static func closeSocket(_ fd: Int32) {
        #if canImport(Darwin)
        Darwin.close(fd)
        #else
        Glibc.close(fd)
        #endif
    }
}
