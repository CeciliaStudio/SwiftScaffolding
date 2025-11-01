//
//  ScaffoldingServer.swift
//  SwiftScaffolding
//
//  Created by 温迪 on 2025/10/30.
//

import Foundation
import Network

public final class ScaffoldingServer {
    public private(set) var room: Room
    public let roomCode: String
    internal let encoder: JSONEncoder
    internal let decoder: JSONDecoder
    private let easyTier: EasyTier
    private var listener: NWListener!
    private var handler: RequestHandler!
    
    /// 使用指定的 EasyTier 创建联机中心。
    /// - Parameter easyTier: 使用的 EasyTier。
    /// - Parameter roomCode: 房间码。若不合法，将在 `start()` 中抛出 `RoomCodeError.invalidRoomCode` 错误。
    /// - Parameter serverPort: Minecraft 服务器端口号。
    public init(easyTier: EasyTier, roomCode: String, serverPort: UInt16) {
        self.room = Room()
        self.room.serverPort = serverPort
        self.easyTier = easyTier
        self.roomCode = roomCode
        
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = .withoutEscapingSlashes
        self.decoder = JSONDecoder()
        self.handler = RequestHandler(server: self)
    }
    
    public func startListener() async throws {
        listener = try NWListener(using: .tcp)
        listener.newConnectionHandler = { connection in
            connection.stateUpdateHandler = { state in
                if state == .ready {
                    Task {
                        try await self.receive(from: connection)
                    }
                }
            }
            connection.start(queue: Scaffolding.connectQueue)
        }
        listener.start(queue: Scaffolding.connectQueue)
    }
    
    
    
    private func receive(from connection: NWConnection) async throws {
        let headerBuffer: ByteBuffer = .init()
        headerBuffer.writeData(try await ConnectionUtil.receiveData(from: connection, length: 1))
        let typeLength: Int = Int(headerBuffer.readUInt8())
        headerBuffer.writeData(try await ConnectionUtil.receiveData(from: connection, length: typeLength + 4))
        guard let type = String(data: headerBuffer.readData(length: typeLength), encoding: .utf8) else { return }
        
        let bodyLength: Int = Int(headerBuffer.readUInt32())
        let bodyData: Data = headerBuffer.readData(length: bodyLength)
        if let handler = handler {
            let responseBuffer: ByteBuffer = .init()
            guard try handler.handleRequest(type: type, requestBody: .init(data: bodyData), responseBuffer: responseBuffer) else { return }
            connection.send(content: responseBuffer.data, completion: .idempotent)
            try await receive(from: connection)
        }
    }
}
