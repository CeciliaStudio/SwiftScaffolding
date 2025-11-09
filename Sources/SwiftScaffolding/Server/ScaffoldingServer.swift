//
//  ScaffoldingServer.swift
//  SwiftScaffolding
//
//  Created by 温迪 on 2025/10/30.
//

import Foundation
import Network

public final class ScaffoldingServer {
    public let room: Room
    public let roomCode: String
    internal let encoder: JSONEncoder
    internal let decoder: JSONDecoder
    internal var machineIdMap: [ObjectIdentifier: String] = [:]
    private let easyTier: EasyTier
    private var listener: NWListener!
    private var handler: RequestHandler!
    private var connections: [NWConnection] = []
    
    /// 使用指定的 EasyTier 创建联机中心。
    /// - Parameters:
    ///   - easyTier: 使用的 EasyTier。
    ///   - roomCode: 房间码。若不合法，将在 `createRoom()` 中抛出 `RoomCodeError.invalidRoomCode` 错误。
    ///   - playerName: 玩家名。
    ///   - vendor: 联机客户端信息。
    ///   - serverPort: Minecraft 服务器端口号。
    public init(
        easyTier: EasyTier,
        roomCode: String,
        playerName: String,
        vendor: String,
        serverPort: UInt16
    ) {
        self.room = Room(
            members: [.init(name: playerName, machineID: Scaffolding.getMachineID(), vendor: vendor, kind: .host)],
            serverPort: serverPort
        )
        self.easyTier = easyTier
        self.roomCode = roomCode
        
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = .withoutEscapingSlashes
        self.decoder = JSONDecoder()
        self.handler = RequestHandler(server: self)
    }
    
    /// 启动连接监听器。
    public func startListener() async throws {
        listener = try NWListener(using: .tcp, on: 13452)
        listener.newConnectionHandler = { connection in
            Logger.info("New connection: \(connection.endpoint.debugDescription)")
            connection.stateUpdateHandler = { [weak self] state in
                guard let self = self else { return }
                switch state {
                case .ready:
                    if !self.connections.contains(where: { $0 === connection }) { self.connections.append(connection) }
                    Task {
                        do {
                            try await self.startReceiving(from: connection)
                        } catch {
                            Logger.error("An error occurred while receiving the request: \(error)")
                            connection.cancel()
                        }
                    }
                    return
                case .failed(let error):
                    Logger.error("Failed to create connection: \(error)")
                case .cancelled:
                    Logger.info("Connection closed: \(connection.endpoint.debugDescription)")
                default:
                    return
                }
                cleanup(connection)
            }
            connection.start(queue: Scaffolding.connectQueue)
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            @Sendable func finish(_ result: Result<Void, Error>) {
                listener.stateUpdateHandler = nil
                continuation.resume(with: result)
            }
            
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    finish(.success(()))
                case .failed(let error):
                    finish(.failure(error))
                case .cancelled:
                    finish(.failure(ConnectionError.cancelled))
                default:
                    break
                }
            }
            listener.start(queue: Scaffolding.connectQueue)
        }
        Logger.info("ScaffoldingServer listener started at 127.0.0.1:13452")
    }
    
    /// 创建 EasyTier 网络。
    public func createRoom() throws {
        guard let listener = listener,
              let port = listener.port?.debugDescription else {
            throw ConnectionError.invalidConnectionState
        }
        guard RoomCode.isValid(code: roomCode) else {
            throw RoomCodeError.invalidRoomCode
        }
        let networkName: String = "scaffolding-mc-\(roomCode.dropFirst(2).prefix(9))"
        let networkSecret: String = String(roomCode.dropFirst(2).suffix(9))
        try easyTier.launch(
            "--no-tun", "-d",
            "--network-name", networkName,
            "--network-secret", networkSecret,
            "--hostname", "scaffolding-mc-server-\(port)",
            "-p", "tcp://public.easytier.cn:11010",
            "--tcp-whitelist=\(port)",
            "--tcp-whitelist=\(room.serverPort)"
        )
    }
    
    /// 关闭房间并断开所有连接。
    public func stop() throws {
        easyTier.kill()
        listener.cancel()
        for connection in connections {
            connection.cancel()
        }
        connections = []
        handler = nil
    }
    
    
    
    private func cleanup(_ connection: NWConnection) {
        if let machineId = machineIdMap[ObjectIdentifier(connection)] {
            DispatchQueue.main.async {
                if let index = self.room.members.firstIndex(where: { $0.machineId == machineId }) {
                    Logger.info("Removed player \(self.room.members[index].name) from the room")
                    self.room.members.remove(at: index)
                }
            }
            machineIdMap.removeValue(forKey: ObjectIdentifier(connection))
        }
        if let index = self.connections.firstIndex(where: { $0 === connection }) {
            self.connections.remove(at: index)
        }
    }
    
    // 该方法只会在连接发生异常或连接断开时返回。
    private func startReceiving(from connection: NWConnection) async throws {
        while true {
            let headerBuffer: ByteBuffer = .init()
            headerBuffer.writeData(try await ConnectionUtil.receiveData(from: connection, length: 1))
            let typeLength: Int = Int(headerBuffer.readUInt8())
            headerBuffer.writeData(try await ConnectionUtil.receiveData(from: connection, length: typeLength + 4))
            guard let type = String(data: headerBuffer.readData(length: typeLength), encoding: .utf8) else { return }
            Logger.info("Received \(type) request from \(connection.endpoint.debugDescription)")
            
            let bodyLength: Int = Int(headerBuffer.readUInt32())
            let bodyData: Data = try await ConnectionUtil.receiveData(from: connection, length: bodyLength)
            if let handler = handler {
                let responseBuffer: ByteBuffer = .init()
                guard try handler.handleRequest(from: connection, type: type, requestBody: .init(data: bodyData), responseBuffer: responseBuffer) else {
                    Logger.warn("Received unknown request: \(type)")
                    return
                }
                connection.send(content: responseBuffer.data, completion: .idempotent)
            }
        }
    }
}
