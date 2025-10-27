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
        let buffer: ByteBuffer = ByteBuffer()
        var status: UInt8?
        var bodyLength: UInt32?
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, context, isComplete, error in
            if let error = error {
                continuation.resume(throwing: error)
                return
            }
            
            if let data = data, !data.isEmpty {
                buffer.writeData(data)
                if buffer.data.count >= 1 {
                    status = buffer.readUInt8()
                }
                if buffer.data.count >= 5 {
                    bodyLength = buffer.readUInt32()
                }
                
                if let status = status,
                    let bodyLength = bodyLength,
                    buffer.data.count == 5 + bodyLength {
                    continuation.resume(returning: SCFResponse(status: status, data: buffer.readData(length: Int(bodyLength))))
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
