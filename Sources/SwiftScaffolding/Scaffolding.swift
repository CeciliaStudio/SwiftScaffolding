//
//  Scaffolding.swift
//  SwiftScaffolding
//
//  Created by 温迪 on 2025/10/27.
//

import Foundation
import IOKit
import CryptoKit
import Network

public final class Scaffolding {
    internal static let networkQueue: DispatchQueue = DispatchQueue(label: "SwiftScaffolding.Network")
    
    /// 根据设备的主板唯一标识符生成设备标识符。
    /// https://github.com/Scaffolding-MC/Scaffolding-MC/blob/main/README.md#machine_id
    /// - Returns: 设备标识符。
    public static func getMachineID() -> String {
        let service: io_service_t = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        let uuid: String = IORegistryEntryCreateCFProperty(service, "IOPlatformUUID" as CFString, kCFAllocatorDefault, 0).takeUnretainedValue() as? String ?? UUID().uuidString
        return Insecure.SHA1.hash(data: Data(uuid.utf8)).map { String(format: "%02hhx", $0) }.joined()
    }
    
    /// 发送 Scaffolding 请求。
    /// https://github.com/Scaffolding-MC/Scaffolding-MC/blob/main/README.md#联机信息获取协议
    /// - Parameters:
    ///   - type: 请求类型。
    ///   - connection: 到联机中心的连接。
    ///   - body: 请求体构造函数。
    public static func sendRequest(
        _ type: String,
        to connection: NWConnection,
        body: (ByteBuffer) throws -> Void
    ) async throws -> Response {
        let buffer: ByteBuffer = ByteBuffer()
        buffer.writeUInt8(UInt8(type.count))
        buffer.writeData(type.data(using: .utf8)!)
        let bodyBuffer: ByteBuffer = ByteBuffer()
        try body(bodyBuffer)
        buffer.writeUInt32(UInt32(bodyBuffer.data.count))
        buffer.writeData(bodyBuffer.data)
        
        return try await withCheckedThrowingContinuation { continuation in
            var didResume: Bool = false
            func safeResume(_ block: () -> Void) {
                if !didResume {
                    didResume = true
                    block()
                }
            }
            networkQueue.asyncAfter(deadline: .now() + 5) {
                safeResume {
                    continuation.resume(throwing: ConnectionError.timeout)
                }
            }
            connection.send(content: buffer.data, completion: .contentProcessed({ error in
                if let error: NWError = error {
                    safeResume { continuation.resume(throwing: error) }
                } else {
                    receive(from: connection) { result in
                        safeResume { continuation.resume(with: result) }
                    }
                }
            }))
        }
    }
    
    
    
    private static func receive(from connection: NWConnection, completion: @escaping (Result<Response, Error>) -> Void) {
        connection.receive(minimumIncompleteLength: 5, maximumLength: 5) { data, context, isComplete, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            if let data = data {
                let buffer: ByteBuffer = ByteBuffer(data: data)
                let status: UInt8 = buffer.readUInt8()
                let bodyLength: Int = Int(buffer.readUInt32())
                if bodyLength == 0 {
                    completion(.success(Response(status: status, data: Data())))
                    return
                }
                connection.receive(minimumIncompleteLength: bodyLength, maximumLength: bodyLength) { data, context, isComplete, error in
                    if let error = error {
                        completion(.failure(error))
                        return
                    }
                    if let data = data {
                        completion(.success(Response(status: status, data: data)))
                    }
                }
            }
        }
    }
    
    /// 检查本地指定端口是否存在一个 Minecraft 服务器。
    /// - Parameters:
    ///   - port: 服务器端口。
    public static func checkMinecraftServer(on port: UInt16, timeout: Double = 10) async -> Bool {
        do {
            let connection: NWConnection = try await ConnectionUtil.makeConnection(host: "127.0.0.1", port: port, timeout: timeout)
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                connection.send(content: [0xFE], completion: .contentProcessed { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: ())
                    }
                })
            }
            return try await ConnectionUtil.receiveData(from: connection, length: 1, timeout: timeout)[0] == 0xFF
        } catch {
            return false
        }
    }
    
    public final class Response {
        public let status: UInt8
        public let data: Data
        public var text: String? { String(data: data, encoding: .utf8) }
        
        /// 根据响应状态码与响应体创建响应。
        /// - Parameters:
        ///   - status: 响应状态。
        ///   - data: 响应体。
        public init(status: UInt8, data: Data) {
            self.status = status
            self.data = data
        }
        
        /// 根据响应状态码与响应体构造函数创建响应。
        /// - Parameters:
        ///   - status: 响应状态。
        ///   - body: 响应体构造函数。
        public init(status: UInt8, body: (ByteBuffer) -> Void) {
            self.status = status
            let buffer: ByteBuffer = .init()
            body(buffer)
            self.data = buffer.data
        }
    }
    
    private init() {
    }
}
