//
//  RequestHandler.swift
//  SwiftScaffolding
//
//  Created by 温迪 on 2025/10/30.
//

import Foundation
import SwiftyJSON

public class RequestHandler {
    private let server: ScaffoldingServer
    private var handlers: [String: (ByteBuffer) throws -> Scaffolding.Response] = [:]
    
    internal init(server: ScaffoldingServer) {
        self.server = server
        registerHandlers()
    }
    
    /// 注册请求处理器。
    /// - Parameters:
    ///   - type: 请求类型，例如 `c:ping`。
    ///   - handler: 请求处理函数。
    public func registerHandler(for type: String, handler: @escaping (_ requestBody: ByteBuffer) throws -> Scaffolding.Response) {
        handlers[type] = handler
    }
    
    internal func handleRequest(type: String, requestBody: ByteBuffer, responseBuffer: ByteBuffer) throws -> Bool {
        guard let handler = handlers[type] else {
            return false
        }
        let response: Scaffolding.Response = try handler(requestBody)
        responseBuffer.writeUInt8(response.status)
        responseBuffer.writeUInt32(UInt32(response.data.count))
        responseBuffer.writeData(response.data)
        return true
    }
    
    private func registerHandlers() {
        registerHandler(for: "c:ping", handler: handlePingRequest(_:))
        registerHandler(for: "c:protocols", handler: handleProtocolsRequest(_:))
        registerHandler(for: "c:server_port", handler: handleServerPortRequest(_:))
    }
    
    private func handlePingRequest(_ requestBody: ByteBuffer) throws -> Scaffolding.Response {
        return .init(status: 0, data: requestBody.data)
    }
    
    private func handleProtocolsRequest(_ requestBody: ByteBuffer) throws -> Scaffolding.Response {
        let protocols: String =
        "c:ping\0" +
        "c:protocols\0" +
        "c:server_port\0" +
        "c:player_ping\0" +
        "c:player_profiles_list\0"
        return .init(status: 0, data: protocols.data(using: .ascii)!)
    }
    
    private func handleServerPortRequest(_ requestBody: ByteBuffer) throws -> Scaffolding.Response {
        guard let serverPort = server.room.serverPort else {
            return .init(status: 32, data: Data())
        }
        return .init(status: 0) { $0.writeUInt16(serverPort) }
    }
    
    private func handlePlayerPingRequest(_ requestBody: ByteBuffer) throws -> Scaffolding.Response {
        let member: Member = try server.decoder.decode(Member.self, from: requestBody.data)
        if !server.room.members.contains(where: { $0.machineID == member.machineID }) {
            server.room.members.append(member)
        }
        return .init(status: 0, data: Data())
    }
    
    private func handlePlayerProfilesListRequest(_ requestBody: ByteBuffer) throws -> Scaffolding.Response {
        return .init(status: 0, data: try server.encoder.encode(server.room.members))
    }
}
