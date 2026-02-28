//
//  RequestHandler.swift
//  SwiftScaffolding
//
//  Created by 温迪 on 2025/10/30.
//

import Foundation
import SwiftyJSON
import Network

public class RequestHandler {
    weak var server: ScaffoldingServer?
    private var handlers: [String: (Sender, ByteBuffer) throws -> Scaffolding.Response] = [:]
    
    internal init() {
        registerHandlers()
    }
    
    /// 注册请求处理器。
    ///
    /// `handler` 闭包接受两个参数：
    /// - `sender`：一个 `Sender` 对象，包含发送者的档案信息和连接对象。
    /// - `buffer`：一个用于读取请求体的 `ByteBuffer`。
    ///
    /// - Parameters:
    ///   - type: 请求类型，例如 `c:ping`。
    ///   - handler: 请求处理函数。
    public func registerHandler(for type: String, handler: @escaping (Sender, ByteBuffer) throws -> Scaffolding.Response) {
        handlers[type] = handler
    }
    
    /// 获取已注册的协议列表。
    public func protocols() -> [String] {
        return Array(handlers.keys)
    }
    
    internal func handleRequest(
        from connection: NWConnection,
        type: String,
        requestBody: ByteBuffer,
        responseBuffer: ByteBuffer
    ) throws {
        guard let server else { return }
        guard let handler = handlers[type] else {
            Logger.warn("Unknown request: \(type)")
            responseBuffer.writeUInt8(255)
            let message: String = "Unknown request"
            responseBuffer.writeUInt32(UInt32(message.count))
            responseBuffer.writeString(message)
            return
        }
        
        let member: Member? = server.machineIdMap[ObjectIdentifier(connection)]
            .flatMap { machineId in server.room.members.first(where: { $0.machineId == machineId }) }
        let sender: Sender = .init(member: member, connection: connection)
        
        let response: Scaffolding.Response = try handler(sender, requestBody)
        responseBuffer.writeUInt8(response.status)
        responseBuffer.writeUInt32(UInt32(response.data.count))
        responseBuffer.writeData(response.data)
    }
    
    private func registerHandlers() {
        registerHandler(for: "c:ping", handler: handlePing(sender:requestBody:))
        registerHandler(for: "c:protocols", handler: handleProtocols(sender:requestBody:))
        registerHandler(for: "c:server_port", handler: handleServerPort(sender:requestBody:))
        registerHandler(for: "c:player_ping", handler: handlePlayerPing(sender:requestBody:))
        registerHandler(for: "c:player_profiles_list", handler: handlePlayerList(sender:requestBody:))
    }
    
    private func handlePing(sender: Sender, requestBody: ByteBuffer) throws -> Scaffolding.Response {
        return .init(status: 0, data: requestBody.data)
    }
    
    private func handleProtocols(sender: Sender, requestBody: ByteBuffer) throws -> Scaffolding.Response {
        let protocols: String = Array(self.handlers.keys).joined(separator: "\0")
        return .init(status: 0) { $0.writeString(protocols) }
    }
    
    private func handleServerPort(sender: Sender, requestBody: ByteBuffer) throws -> Scaffolding.Response {
        guard let server else { return .init(status: 255, data: .init()) }
        return .init(status: 0) { $0.writeUInt16(server.room.serverPort) }
    }
    
    private func handlePlayerPing(sender: Sender, requestBody: ByteBuffer) throws -> Scaffolding.Response {
        guard let server else { return .init(status: 255, data: .init()) }
        let connection: NWConnection = sender.connection
        let rawMember: Member = try server.decoder.decode(Member.self, from: requestBody.data)
        
        let member: Member = .init(
            name: rawMember.name,
            machineID: rawMember.machineId,
            vendor: rawMember.vendor,
            kind: .guest
        )
        
        let identifier: ObjectIdentifier = .init(connection)
        
        if server.machineIdMap[identifier] == nil
            && server.machineIdMap.values.contains(member.machineId) {
            Logger.warn("Detected a machine_id collision")
            throw RoomError.playerInfoMismatch
        }
        if let machineId = server.machineIdMap[identifier], machineId != member.machineId {
            Logger.warn("machine_id mismatch detected")
            throw RoomError.playerInfoMismatch
        }
        
        server.machineIdMap[identifier] = member.machineId
        
        if let storedMember: Member = server.room.members.first(where: { $0.machineId == member.machineId }) {
            if storedMember != member {
                Logger.warn("Member info mismatch for \(storedMember.name)")
                throw RoomError.playerInfoMismatch
            }
        } else {
            Logger.info("Received player info from \(connection.endpoint.debugDescription): { \"name\": \"\(member.name)\", \"vendor\": \"\(member.vendor)\", \"machine_id\": \"\(member.machineId)\"}")
            DispatchQueue.main.async {
                server.room.members.append(member)
            }
        }
        
        return .init(status: 0, data: Data())
    }
    
    private func handlePlayerList(sender: Sender, requestBody: ByteBuffer) throws -> Scaffolding.Response {
        guard let server else { return .init(status: 255, data: .init()) }
        return .init(status: 0, data: try server.encoder.encode(server.room.members))
    }
    
    public struct Sender {
        public let member: Member?
        public let connection: NWConnection
    }
}
