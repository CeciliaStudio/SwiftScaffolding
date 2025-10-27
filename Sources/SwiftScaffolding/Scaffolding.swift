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
    /// 根据设备的主板唯一标识符生成设备码。
    /// - Returns: 设备码。
    public static func getMachineID() -> String {
        let service: io_service_t = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        let uuid: String = IORegistryEntryCreateCFProperty(service, "IOPlatformUUID" as CFString, kCFAllocatorDefault, 0).takeUnretainedValue() as? String ?? UUID().uuidString
        return Insecure.SHA1.hash(data: Data(uuid.utf8)).map { String(format: "%02hhx", $0) }.joined()
    }
    
    /// 发送 Scaffolding 请求。
    /// https://github.com/Scaffolding-MC/Scaffolding-MC?tab=readme-ov-file#联机信息获取协议
    /// - Parameters:
    ///   - type: 请求类型。
    ///   - connection: 到联机中心的连接。
    ///   - body: 请求体构造函数。
    public static func sendRequest(
        _ type: String,
        to connection: NWConnection,
        body: (ByteBuffer) throws -> Void
    ) async throws -> SCFResponse {
        let buffer: ByteBuffer = ByteBuffer()
        buffer.writeUInt8(UInt8(type.count))
        buffer.writeData(type.data(using: .utf8)!)
        let bodyBuffer: ByteBuffer = ByteBuffer()
        try body(bodyBuffer)
        buffer.writeUInt32(UInt32(bodyBuffer.data.count))
        buffer.writeData(bodyBuffer.data)
        
        return try await withCheckedThrowingContinuation { continuation in
            connection.send(content: buffer.data, completion: .contentProcessed({ error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    receive(from: connection, continuation: continuation)
                }
            }))
        }
    }
    
    private static func receive(from connection: NWConnection, continuation: CheckedContinuation<SCFResponse, Error>) {
        connection.receive(minimumIncompleteLength: 5, maximumLength: 5) { data, context, isComplete, error in
            if let error = error {
                continuation.resume(throwing: error)
                return
            }
            if let data = data {
                let buffer: ByteBuffer = ByteBuffer(data: data)
                let status: UInt8 = buffer.readUInt8()
                let bodyLength: Int = Int(buffer.readUInt32())
                if bodyLength == 0 {
                    continuation.resume(returning: SCFResponse(status: status, data: Data()))
                    return
                }
                connection.receive(minimumIncompleteLength: bodyLength, maximumLength: bodyLength) { data, context, isComplete, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                        return
                    }
                    if let data = data {
                        continuation.resume(returning: SCFResponse(status: status, data: data))
                    }
                }
            }
        }
    }
    
    private init() {
    }
}

public final class SCFResponse {
    public let status: UInt8
    public let data: Data
    public let text: String?
    
    init(status: UInt8, data: Data) {
        self.status = status
        self.data = data
        self.text = String(data: data, encoding: .utf8)
    }
}
