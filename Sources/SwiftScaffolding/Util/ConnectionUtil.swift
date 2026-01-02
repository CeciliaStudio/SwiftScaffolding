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
    
    /// 获取空闲端口。
    /// - Returns: 一个 `UInt16?`，为 `nil` 时表示创建失败。
    public static func getFreePort() -> UInt16? {
        var addr: sockaddr_in = sockaddr_in()
        addr.sin_len = __uint8_t(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(0).bigEndian
        addr.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        
        let fd: Int32 = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        
        guard withUnsafePointer(to: &addr, {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }) == 0 else { return nil }
        
        var len: socklen_t = socklen_t(MemoryLayout<sockaddr_in>.size)
        guard getsockname(fd, withUnsafeMutablePointer(to: &addr, {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { $0 }
        }), &len) == 0 else { return nil }
        
        return UInt16(bigEndian: addr.sin_port)
    }
}
