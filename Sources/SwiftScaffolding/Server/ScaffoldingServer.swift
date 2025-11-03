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
    private var errorHandler: ErrorHandler?
    private var connections: [NWConnection] = []
    
    /// 使用指定的 EasyTier 创建联机中心。
    /// - Parameters:
    ///   - easyTier: 使用的 EasyTier。
    ///   - roomCode: 房间码。若不合法，将在 `createRoom()` 中抛出 `RoomCodeError.invalidRoomCode` 错误。
    ///   - playerName: 玩家名。
    ///   - vendor: 联机客户端信息。
    ///   - serverPort: Minecraft 服务器端口号。
    ///   - errorHandler: 异步错误处理对象。
    public init(
        easyTier: EasyTier,
        roomCode: String,
        playerName: String,
        vendor: String,
        serverPort: UInt16,
        errorHandler: ErrorHandler? = nil
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
        self.errorHandler = errorHandler
    }
    
    /// 启动连接监听器。
    public func startListener() async throws {
        listener = try NWListener(using: .tcp, on: 13452)
        listener.newConnectionHandler = { connection in
            connection.stateUpdateHandler = { [weak self] state in
                guard let self = self else { return }
                switch state {
                case .ready:
                    if !self.connections.contains(where: { $0 === connection }) { self.connections.append(connection) }
                    Task {
                        do {
                            try await self.startReceiving(from: connection)
                        } catch {
                            self.errorHandler?.handle(error)
                            connection.cancel()
                        }
                    }
                case .failed, .cancelled:
                    if let idx = self.connections.firstIndex(where: { $0 === connection }) {
                        self.connections.remove(at: idx)
                    }
                default:
                    break
                }
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
    
    
    
    private func startReceiving(from connection: NWConnection) async throws {
        while true {
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
            }
        }
    }
}
