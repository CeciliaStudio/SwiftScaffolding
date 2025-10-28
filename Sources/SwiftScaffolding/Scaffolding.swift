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
    /// 根据设备的主板唯一标识符生成设备标识符。
    /// https://github.com/Scaffolding-MC/Scaffolding-MC/blob/main/README.md#machine_id
    /// - Returns: 设备标识符。
    public static func getMachineID() -> String {
        let service: io_service_t = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        let uuid: String = IORegistryEntryCreateCFProperty(service, "IOPlatformUUID" as CFString, kCFAllocatorDefault, 0).takeUnretainedValue() as? String ?? UUID().uuidString
        return Insecure.SHA1.hash(data: Data(uuid.utf8)).map { String(format: "%02hhx", $0) }.joined()
    }
    
    /// 生成符合 Scaffolding 标准的房间码。
    /// https://github.com/Scaffolding-MC/Scaffolding-MC/blob/main/README.md#联机房间码
    /// - Returns: 生成的房间码。
    public static func generateRoomCode() -> String {
        let charset: [String] = "0123456789ABCDEFGHJKLMNPQRSTUVWXYZ".map { String($0) }
        let b: Int = 34
        var digits: [Int] = []
        var sumMod7: Int = 0
        var powMod7: Int = 1
        for _ in 0..<15 {
            let d: Int = Int.random(in: 0..<b)
            digits.append(d)
            sumMod7 = (sumMod7 + d * powMod7) % 7
            powMod7 = (powMod7 * b) % 7
        }
        let invPow15: Int = 6
        let base: Int = ((7 - (sumMod7 % 7)) * invPow15) % 7
        let kMax: Int = ((b - 1) - base) / 7
        let d15: Int = base + 7 * Int.random(in: 0...kMax)
        digits.append(d15)
        
        var code: String = ""
        for i in 0..<16 {
            let idx: Int = digits[i]
            code += charset[idx]
            if i == 3 || i == 7 || i == 11 { code += "-" }
        }
        return "U/" + String(code.reversed())
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
