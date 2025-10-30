//
//  ScaffoldingClient.swift
//  SwiftScaffolding
//
//  Created by 温迪 on 2025/10/29.
//

import Foundation
import Network

public final class ScaffoldingClient {
    private static let connectQueue: DispatchQueue = DispatchQueue(label: "SwiftScaffolding.ScaffoldingClient.Connect")
    public private(set) var room: Room!
    private let easyTier: EasyTier
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let player: Member
    private let roomCode: String
    private var connection: NWConnection!
    private var remoteIP: String!
    
    /// 使用指定的 EasyTier 创建连接到指定房间的 `ScaffoldingClient`。
    /// - Parameters:
    ///   - easyTier: 使用的 EasyTier。
    ///   - playerName: 玩家名。
    ///   - vendor: 联机客户端信息。
    ///   - roomCode: 房间的房间码。
    public init(
        easyTier: EasyTier,
        playerName: String,
        vendor: String,
        roomCode: String
    ) {
        self.easyTier = easyTier
        self.player = .init(
            name: playerName,
            machineID: Scaffolding.getMachineID(),
            vendor: vendor,
            kind: .guest
        )
        self.roomCode = roomCode
        
        self.encoder = .init()
        self.encoder.outputFormatting = .withoutEscapingSlashes
        self.decoder = .init()
    }
    
    /// 连接到房间。
    /// 该方法返回后，必须每隔 5s 调用一次 `heartbeat()` 方法。
    /// https://github.com/Scaffolding-MC/Scaffolding-MC/blob/main/README.md#拓展协议
    public func connect() async throws {
        let pattern = #/^U\/[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}$/#
        guard roomCode.wholeMatch(of: pattern) != nil else {
            throw RoomCodeError.invalidRoomCode
        }
        let networkName: String = "scaffolding-mc-\(roomCode.dropFirst(2).prefix(9))"
        let networkSecret: String = String(roomCode.dropFirst(2).suffix(9))
        try easyTier.launch(
            "--no-tun", "-d",
            "--network-name", networkName,
            "--network-secret", networkSecret,
            "-p", "tcp://public.easytier.cn:11010"
        )
        for _ in 0..<15 {
            try await Task.sleep(for: .seconds(1))
            guard let node = try? easyTier.getPeerList().first(where: { $0.hostname.starts(with: "scaffolding-mc-server") }) else {
                continue
            }
            remoteIP = node.ipv4
            let port: String = String(node.hostname.dropFirst("scaffolding-mc-server-".count))
            try easyTier.addPortForward(bind: "127.0.0.1:\(port)", destination: "\(remoteIP!):\(port)")
            try await joinRoom(port: port)
            return
        }
        throw ConnectionError.timeout
    }
    
    /// 向联机中心发送请求。
    /// - Parameters:
    ///   - name: 请求类型。
    ///   - body: 请求体构造函数。
    /// - Returns: 联机中心的响应。
    @discardableResult
    public func sendRequest(_ name: String, body: (ByteBuffer) throws -> Void = { _ in }) async throws -> SCFResponse {
        try assertReady()
        return try await Scaffolding.sendRequest(name, to: connection, body: body)
    }
    
    /// 发送 `c:player_ping` 请求并同步玩家列表。
    public func heartbeat() async throws {
        try assertReady()
        try await sendRequest("c:player_ping") { buf in
            buf.writeData(try encoder.encode(player))
        }
        let memberList: [Member] = try decoder.decode([Member].self, from: await sendRequest("c:player_profiles_list").data)
        self.room.members = memberList
    }
    
    
    
    private func joinRoom(port: String) async throws {
        guard let port: NWEndpoint.Port = NWEndpoint.Port(port) else {
            throw ConnectionError.invalidPort
        }
        
        let connection: NWConnection = NWConnection(to: .hostPort(host: "127.0.0.1", port: port), using: .tcp)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            @Sendable func finish(_ result: Result<Void, Error>) {
                connection.stateUpdateHandler = nil
                continuation.resume(with: result)
            }
            
            connection.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    self?.connection = connection
                    finish(.success(()))
                case .failed(let error):
                    finish(.failure(error))
                case .cancelled:
                    finish(.failure(ConnectionError.cancelled))
                default:
                    break
                }
            }
        }
        room = .init()
        try await heartbeat()
        let serverPort: UInt16 = ByteBuffer(data: try await sendRequest("c:server_port").data).readUInt16()
        try easyTier.addPortForward(bind: "127.0.0.1:\(serverPort)", destination: "\(remoteIP!):\(serverPort)")
        room.serverPort = serverPort
    }
    
    private func assertReady() throws {
        guard let connection = connection else {
            throw ConnectionError.missingConnection
        }
        guard connection.state == .ready else {
            throw ConnectionError.invalidConnectionState
        }
    }
    
    public enum ConnectionError: Error {
        case invalidPort
        case timeout
        case cancelled
        case missingConnection
        case invalidConnectionState
    }
    
    public enum RoomCodeError: Error {
        case invalidRoomCode
    }
}
