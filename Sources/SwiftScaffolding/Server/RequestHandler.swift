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
    var server: ScaffoldingServer!
    private var handlers: [String: (Sender, ByteBuffer) throws -> Scaffolding.Response] = [:]
    
    internal init() {
        registerHandlers()
    }
    
    /// 注册请求处理器。
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
    
    internal func destroy() {
        handlers.removeAll()
        server = nil
    }
    
    internal func handleRequest(
        from connection: NWConnection,
        type: String,
        requestBody: ByteBuffer,
        responseBuffer: ByteBuffer
    ) throws {
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
        registerHandler(for: "c:ping") { sender, requestBody in
            return .init(status: 0, data: requestBody.data)
        }
        
        registerHandler(for: "c:protocols") { sender, requestBody in
            let protocols: String = Array(self.handlers.keys).joined(separator: "\0")
            return .init(status: 0) { $0.writeString(protocols) }
        }
        
        registerHandler(for: "c:server_port") { sender, requestBody in
            return .init(status: 0) { $0.writeUInt16(self.server.room.serverPort) }
        }
        
        registerHandler(for: "c:player_ping") { sender, requestBody in
            let connection: NWConnection = sender.connection
            let rawMember: Member = try self.server.decoder.decode(Member.self, from: requestBody.data)
            
            let member: Member = .init(
                name: rawMember.name,
                machineID: rawMember.machineId,
                vendor: rawMember.vendor,
                kind: .guest
            )
            
            let identifier: ObjectIdentifier = .init(connection)
            
            if self.server.machineIdMap[identifier] == nil
                && self.server.machineIdMap.values.contains(member.machineId) {
                Logger.warn("Detected a machine_id collision")
                throw RoomError.playerInfoMismatch
            }
            if let machineId = self.server.machineIdMap[identifier], machineId != member.machineId {
                Logger.warn("machine_id mismatch detected")
                throw RoomError.playerInfoMismatch
            }
            
            self.server.machineIdMap[identifier] = member.machineId
            
            if let storedMember: Member = self.server.room.members.first(where: { $0.machineId == member.machineId }) {
                if storedMember != member {
                    Logger.warn("Member info mismatch for \(storedMember.name)")
                    throw RoomError.playerInfoMismatch
                }
            } else {
                Logger.info("Received player info from \(connection.endpoint.debugDescription): { \"name\": \"\(member.name)\", \"vendor\": \"\(member.vendor)\", \"machine_id\": \"\(member.machineId)\"}")
                DispatchQueue.main.async {
                    self.server.room.members.append(member)
                }
            }
            
            return .init(status: 0, data: Data())
        }
        
        registerHandler(for: "c:player_profiles_list") { sender, requestBody in
            return .init(status: 0, data: try self.server.encoder.encode(self.server.room.members))
        }
    }
    
    public struct Sender {
        public let member: Member?
        public let connection: NWConnection
    }
}
