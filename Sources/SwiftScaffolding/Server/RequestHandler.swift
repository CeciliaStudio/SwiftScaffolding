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
    private let server: ScaffoldingServer
    private var handlers: [String: (NWConnection, ByteBuffer) throws -> Scaffolding.Response] = [:]
    
    internal init(server: ScaffoldingServer) {
        self.server = server
        registerHandlers()
    }
    
    /// 注册请求处理器。
    /// - Parameters:
    ///   - type: 请求类型，例如 `c:ping`。
    ///   - handler: 请求处理函数。
    public func registerHandler(for type: String, handler: @escaping (NWConnection, ByteBuffer) throws -> Scaffolding.Response) {
        handlers[type] = handler
    }
    
    internal func handleRequest(
        from connection: NWConnection,
        type: String,
        requestBody: ByteBuffer,
        responseBuffer: ByteBuffer
    ) throws -> Bool {
        guard let handler = handlers[type] else {
            return false
        }
        let response: Scaffolding.Response = try handler(connection, requestBody)
        responseBuffer.writeUInt8(response.status)
        responseBuffer.writeUInt32(UInt32(response.data.count))
        responseBuffer.writeData(response.data)
        return true
    }
    
    private func registerHandlers() {
        registerHandler(for: "c:ping", handler: handlePingRequest(_:_:))
        registerHandler(for: "c:protocols", handler: handleProtocolsRequest(_:_:))
        registerHandler(for: "c:server_port", handler: handleServerPortRequest(_:_:))
        registerHandler(for: "c:player_ping", handler: handlePlayerPingRequest(_:_:))
        registerHandler(for: "c:player_profiles_list", handler: handlePlayerProfilesListRequest(_:_:))
    }
    
    private func handlePingRequest(_ connection: NWConnection, _ requestBody: ByteBuffer) throws -> Scaffolding.Response {
        return .init(status: 0, data: requestBody.data)
    }
    
    private func handleProtocolsRequest(_ connection: NWConnection, _ requestBody: ByteBuffer) throws -> Scaffolding.Response {
        let protocols: String = Array(handlers.keys).joined(separator: "\0")
        return .init(status: 0, data: protocols.data(using: .utf8)!)
    }
    
    private func handleServerPortRequest(_ connection: NWConnection, _ requestBody: ByteBuffer) throws -> Scaffolding.Response {
        return .init(status: 0) { $0.writeUInt16(server.room.serverPort) }
    }
    
    private func handlePlayerPingRequest(_ connection: NWConnection, _ requestBody: ByteBuffer) throws -> Scaffolding.Response {
        let member: Member = try server.decoder.decode(Member.self, from: requestBody.data)
        Logger.info("Player info for \(connection.endpoint.debugDescription) is \(String(data: requestBody.data, encoding: .utf8)!)")
        server.machineIdMap[ObjectIdentifier(connection)] = member.machineId
        if !server.room.members.contains(where: { $0.machineId == member.machineId }) {
            DispatchQueue.main.async {
                self.server.room.members.append(member)
            }
        }
        return .init(status: 0, data: Data())
    }
    
    private func handlePlayerProfilesListRequest(_ connection: NWConnection, _ requestBody: ByteBuffer) throws -> Scaffolding.Response {
        return .init(status: 0, data: try server.encoder.encode(server.room.members))
    }
}
