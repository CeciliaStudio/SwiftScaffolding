//
//  ConnectionUtil.swift
//  SwiftScaffolding
//
//  Created by 温迪 on 2025/11/1.
//

import Foundation
import Network

internal enum ConnectionUtil {
    /// 向目标地址创建一个 TCP 连接。
    /// - Parameters:
    ///   - host: 目标地址。
    ///   - port: 目标端口。
    ///   - timeout: 超时时间。
    public static func makeConnection(host: String, port: UInt16, timeout: Double = 10) async throws -> NWConnection {
        let connection: NWConnection = NWConnection(to: .hostPort(host: .init(stringLiteral: host), port: .init(integerLiteral: port)), using: .tcp)
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<NWConnection, Error>) in
            let once: Once = .init()
            @Sendable func finish(with result: Result<NWConnection, Error>) {
                Task {
                    await once.run {
                        connection.stateUpdateHandler = nil
                        continuation.resume(with: result)
                    }
                }
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    finish(with: .success(connection))
                case .failed(let error):
                    finish(with: .failure(error))
                case .cancelled:
                    finish(with: .failure(ConnectionError.cancelled))
                default:
                    break
                }
            }
            Task {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                await once.run {
                    continuation.resume(throwing: ConnectionError.timeout)
                }
            }
            connection.start(queue: Scaffolding.networkQueue)
        }
    }
    
    public static func receiveData(from connection: NWConnection, length: Int, timeout: Double = 10) async throws -> Data {
        if length == 0 { return Data() }
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            let once: Once = .init()
            
            @Sendable func finish(with result: Result<Data, Error>) {
                Task {
                    await once.run {
                        continuation.resume(with: result)
                    }
                }
            }
            
            connection.receive(minimumIncompleteLength: length, maximumLength: length) { (data: Data?, _: NWConnection.ContentContext?, _: Bool, error: NWError?) in
                if let error: NWError = error {
                    finish(with: .failure(error))
                    return
                }
                guard let data: Data = data, data.count == length else {
                    finish(with: .failure(ConnectionError.cancelled))
                    return
                }
                finish(with: .success(data))
            }
            
            Task {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                await once.run {
                    continuation.resume(throwing: ConnectionError.timeout)
                }
            }
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
