//
//  ConnectionUtil.swift
//  SwiftScaffolding
//
//  Created by 温迪 on 2025/11/1.
//

import Foundation
import Network

internal enum ConnectionUtil {
    /// 从连接异步接收指定长度的数据。
    /// - Parameters:
    ///   - connection: 目标连接。
    ///   - length: 数据长度。
    /// - Returns: 接收到的数据。
    public static func receiveData(from connection: NWConnection, length: Int) async throws -> Data {
        if length == 0 { return Data() }
        return try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { continuation in
                    connection.receive(minimumIncompleteLength: length, maximumLength: length) { data, _, _, error in
                        if let error = error {
                            continuation.resume(throwing: error)
                            return
                        }
                        guard let data = data, data.count == length else {
                            continuation.resume(throwing: ConnectionError.cancelled)
                            return
                        }
                        continuation.resume(returning: data)
                    }
                }
            }
            group.addTask {
                try await Task.sleep(nanoseconds: 10 * 1_000_000_000)
                connection.cancel()
                throw ConnectionError.timeout
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
    
    /// 获取一个当前可绑定的本地端口号。
    /// - Parameter preferredPort: 优先尝试的端口号，为 0 时由系统自动分配。
    /// - Returns: 可用端口号，分配失败时返回 0。
    public static func getPort(_ preferredPort: UInt16 = 0) throws -> UInt16 {
        func tryBind(port: UInt16) -> UInt16? {
            let sockfd: Int32 = socket(AF_INET, SOCK_STREAM, 0)
            guard sockfd >= 0 else { return nil }
            defer { close(sockfd) }
            var addr = sockaddr_in(
                sin_len: UInt8(MemoryLayout<sockaddr_in>.size),
                sin_family: sa_family_t(AF_INET),
                sin_port: port.bigEndian,
                sin_addr: in_addr(s_addr: INADDR_ANY),
                sin_zero: (0, 0, 0, 0, 0, 0, 0, 0)
            )
            let result = withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    bind(sockfd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            guard result == 0 else { return nil }
            if port == 0 {
                var usedAddr = addr
                var len = socklen_t(MemoryLayout<sockaddr_in>.size)
                getsockname(sockfd, withUnsafeMutablePointer(to: &usedAddr) {
                    UnsafeMutableRawPointer($0).assumingMemoryBound(to: sockaddr.self)
                }, &len)
                return UInt16(bigEndian: usedAddr.sin_port)
            }
            return port
        }
        if preferredPort > 0 {
            if let port = tryBind(port: preferredPort) {
                return port
            }
            Logger.info("Local port \(preferredPort) is not usable, allocating a new one")
        }
        guard let port = tryBind(port: 0) else {
            Logger.error("Failed to allocate port")
            throw ConnectionError.failedToAllocatePort
        }
        return port
    }
}
