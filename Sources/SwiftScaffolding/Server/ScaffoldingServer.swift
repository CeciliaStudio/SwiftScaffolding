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
    public let handler: RequestHandler
    internal let encoder: JSONEncoder
    internal let decoder: JSONDecoder
    internal var machineIdMap: [ObjectIdentifier: String] = [:]
    private let easyTier: EasyTier
    private var listener: NWListener!
    private var connections: [NWConnection] = []
    private var connectionTasks: [ObjectIdentifier: Task<Void, Never>] = [:]
    
    deinit {
        Logger.debug("ScaffoldingServer is being deallocated")
        listener?.cancel()
        easyTier.terminate()
    }
    
    /// 创建联机中心。
    ///
    /// - Parameters:
    ///   - easyTier: 使用的 EasyTier。
    ///   - roomCode: 房间码。若不合法，将在 `createRoom()` 中抛出 `RoomError.invalidRoomCode` 错误。
    ///   - serverPort: Minecraft 服务器端口号。
    ///   - hostInfo: 房主信息。
    public init(
        easyTier: EasyTier,
        roomCode: String,
        serverPort: UInt16,
        hostInfo: PlayerInfo
    ) {
        self.room = Room(
            members: [.init(
                name: hostInfo.name,
                machineID: Scaffolding.getMachineID(forHost: true),
                vendor: hostInfo.vendor,
                kind: .host
            )],
            serverPort: serverPort
        )
        self.easyTier = easyTier
        self.roomCode = roomCode
        
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = .withoutEscapingSlashes
        self.decoder = JSONDecoder()
        self.handler = .init()
        self.handler.server = self
    }
    
    // 旧格式支持
    @available(*, deprecated, renamed: "ScaffoldingServer.init(easyTier:roomCode:serverPort:hostInfo:)", message: "")
    public convenience init(
        easyTier: EasyTier,
        roomCode: String,
        playerName: String,
        vendor: String,
        serverPort: UInt16
    ) {
        self.init(easyTier: easyTier, roomCode: roomCode, serverPort: serverPort, hostInfo: .init(name: playerName, vendor: vendor))
    }
    
    /// 启动联机中心监听器。
    ///
    /// 默认会在 `13452` 端口监听。若该端口被占用，会重新申请一个端口。
    /// - Returns: 联机中心实际端口号。
    @discardableResult
    public func startListener() async throws -> UInt16 {
        let port: UInt16 = try ConnectionUtil.getPort(13452)
        listener = try NWListener(using: .tcp, on: .init(integerLiteral: port))
        listener.newConnectionHandler = { connection in
            Logger.info("New connection: \(connection.endpoint.debugDescription)")
            connection.stateUpdateHandler = { [weak self] state in
                guard let self = self else { return }
                switch state {
                case .ready:
                    handleConnection(connection)
                    return
                case .failed(let error):
                    Logger.error("Failed to create connection: \(error)")
                case .cancelled:
                    Logger.info("Connection closed: \(connection.endpoint.debugDescription)")
                default:
                    return
                }
                Task { @MainActor in
                    self.cleanup(connection)
                }
            }
            connection.start(queue: Scaffolding.networkQueue)
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
            listener.start(queue: Scaffolding.networkQueue)
        }
        Logger.info("ScaffoldingServer listener started at 127.0.0.1:\(port)")
        return port
    }
    
    /// 创建 EasyTier 网络。
    ///
    /// 如果只是本地测试，无需创建 EasyTier 网络，可以直接使用 `ScaffoldingClient.connectDirectly(port:)` 连接。
    /// - Parameter terminationHandler: 进程退出回调，不会在正常关闭时被调用。
    public func createRoom(terminationHandler: ((Process) -> Void)? = nil) throws {
        guard let listener = listener,
              let port = listener.port?.debugDescription else {
            throw ConnectionError.invalidConnectionState
        }
        guard RoomCode.isValid(code: roomCode) else {
            throw RoomError.invalidRoomCode
        }
        let networkName: String = "scaffolding-mc-\(roomCode.dropFirst(2).prefix(9))"
        let networkSecret: String = String(roomCode.dropFirst(2).suffix(9))
        try easyTier.launch(
            "--no-tun", "-d",
            "--network-name", networkName,
            "--network-secret", networkSecret,
            "--hostname", "scaffolding-mc-server-\(port)",
            "--tcp-whitelist", "\(port)",
            "--tcp-whitelist", "\(room.serverPort)",
            "--udp-whitelist", "0",
            "--listeners", "tcp://0.0.0.0:0",
            "--listeners", "udp://0.0.0.0:0",
            terminationHandler: { [weak self] process in
                self?.stop()
                terminationHandler?(process)
            }
        )
    }
    
    /// 关闭房间并断开所有连接。
    public func stop() {
        Logger.info("Stopping scaffolding server")
        easyTier.terminate()
        listener?.cancel()
        listener = nil
        for connection in connections {
            connection.cancel()
            DispatchQueue.main.async {
                self.cleanup(connection)
            }
        }
        connections = []
        handler.destroy()
    }
    
    
    
    @MainActor
    private func cleanup(_ connection: NWConnection) {
        connection.stateUpdateHandler = nil
        if connection.state != .cancelled { connection.cancel() }
        let identifier: ObjectIdentifier = .init(connection)
        
        if let machineId = machineIdMap[identifier] {
            self.room.members.removeAll(where: { $0.machineId == machineId })
            self.machineIdMap.removeValue(forKey: identifier)
        }
        
        self.connectionTasks[identifier]?.cancel()
        self.connectionTasks.removeValue(forKey: identifier)
        self.connections.removeAll(where: { $0 === connection })
    }
    
    private func handleConnection(_ connection: NWConnection) {
        if !self.connections.contains(where: { $0 === connection }) { self.connections.append(connection) }
        let task: Task<Void, Never> = Task.detached {
            do {
                try await self.startReceiving(from: connection)
            } catch {
                Logger.error("An error occurred while processing requests: \(error.localizedDescription)")
            }
            await MainActor.run {
                self.cleanup(connection)
            }
        }
        connectionTasks[ObjectIdentifier(connection)] = task
    }
    
    // 该方法只会在连接发生异常或连接断开时返回。
    private func startReceiving(from connection: NWConnection) async throws {
        while !Task.isCancelled {
            let headerBuffer: ByteBuffer = .init()
            headerBuffer.writeData(try await ConnectionUtil.receiveData(from: connection, length: 1))
            
            let typeLength: Int = Int(try headerBuffer.readUInt8())
            headerBuffer.writeData(try await ConnectionUtil.receiveData(from: connection, length: typeLength + 4))
            let type: String = try headerBuffer.readString(typeLength)
            
            let bodyLength: Int = Int(try headerBuffer.readUInt32())
            let bodyData: Data = try await ConnectionUtil.receiveData(from: connection, length: bodyLength)
            
            let responseBuffer: ByteBuffer = .init()
            if !handler.protocols().contains(type) {
                Logger.info("Received unknown request: \(type)")
            }
            
            try handler.handleRequest(from: connection, type: type, requestBody: .init(data: bodyData), responseBuffer: responseBuffer)
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                connection.send(content: responseBuffer.data, completion: .contentProcessed { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: ())
                    }
                })
            }
        }
    }
}
