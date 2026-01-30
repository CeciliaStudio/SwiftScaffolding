//
//  ScaffoldingClient.swift
//  SwiftScaffolding
//
//  Created by 温迪 on 2025/10/29.
//

import Foundation
import Network

public final class ScaffoldingClient {
    public private(set) var room: Room!
    /// 服务端支持的协议列表。
    public private(set) var serverProtocols: [String]!
    private let easyTier: EasyTier
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let player: Member
    private var connection: NWConnection!
    private var serverNodeIp: String!
    private var protocols: [String]
    
    deinit {
        Logger.debug("ScaffoldingClient is being deallocated")
        connection?.cancel()
        easyTier.terminate()
    }
    
    /// 使用指定的 EasyTier 创建连接到指定房间的 `ScaffoldingClient`。
    /// - Parameters:
    ///   - easyTier: 使用的 EasyTier。
    ///   - playerName: 玩家名。
    ///   - vendor: 联机客户端信息。
    public init(
        easyTier: EasyTier,
        playerName: String,
        vendor: String
    ) {
        self.easyTier = easyTier
        self.player = .init(
            name: playerName,
            machineID: Scaffolding.getMachineID(),
            vendor: vendor,
            kind: .guest
        )
        
        self.encoder = .init()
        self.encoder.outputFormatting = .withoutEscapingSlashes
        self.decoder = .init()
        
        self.protocols = RequestHandler().protocols()
    }
    
    /// 连接到房间。
    /// 该方法返回后，必须每隔 5s 调用一次 `heartbeat()` 方法。
    /// https://github.com/Scaffolding-MC/Scaffolding-MC/blob/main/README.md#拓展协议
    /// - Parameters:
    ///   - roomCode: 房间码。
    ///   - checkServer: 是否检查联机中心返回的 Minecraft 服务器端口号。
    public func connect(to roomCode: String, checkServer: Bool = true, terminationHandler: ((Process) -> Void)? = nil) async throws {
        guard RoomCode.isValid(code: roomCode) else {
            throw RoomError.invalidRoomCode
        }
        let networkName: String = "scaffolding-mc-\(roomCode.dropFirst(2).prefix(9))"
        let networkSecret: String = String(roomCode.dropFirst(2).suffix(9))
        try easyTier.launch(
            "--no-tun", "-d",
            "--network-name", networkName,
            "--network-secret", networkSecret,
            "--tcp-whitelist", "0",
            "--udp-whitelist", "0",
            "--listeners", "tcp://0.0.0.0:0",
            "--listeners", "udp://0.0.0.0:0",
            terminationHandler: { [weak self] process in
                self?.stop()
                terminationHandler?(process)
            }
        )
        do {
            for _ in 0..<15 {
                try await Task.sleep(nanoseconds: 1_000_000_000)
                guard let node = try? easyTier.peerList().first(where: { $0.hostname.starts(with: "scaffolding-mc-server") }) else {
                    continue
                }
                Logger.info("Found scaffolding server: \(node.hostname)")
                let serverIp: String = node.ipv4
                guard let serverPort: UInt16 = .init(node.hostname.dropFirst("scaffolding-mc-server-".count)) else {
                    Logger.error("The scaffolding server port is invalid")
                    throw ConnectionError.invalidPort
                }
                self.serverNodeIp = serverIp
                
                let localPort: UInt16 = try ConnectionUtil.getPort(serverPort)
                try easyTier.addPortForward(bind: "127.0.0.1:\(localPort)", destination: "\(serverIp):\(serverPort)")
                try await Task.sleep(nanoseconds: 3_000_000_000)
                try await joinRoom(port: localPort, checkServer: checkServer)
                return
            }
            throw ConnectionError.timeout
        } catch {
            easyTier.terminate()
            throw error
        }
    }
    
    /// 不使用 EasyTier，直接连接到本地联机大厅。
    /// - Parameter port: 联机大厅端口号。
    public func connectDirectly(port: UInt16) async throws {
        Logger.info("Directly connecting to scaffolding server...")
        self.connection = try await ConnectionUtil.makeConnection(host: "127.0.0.1", port: port)
        Logger.info("Connected to scaffolding server")
        
        room = Room(members: [], serverPort: 0)
        try await heartbeat()
        try await fetchProtocols()
        
        let serverPort: UInt16 = ByteBuffer(data: try await sendRequest("c:server_port").data).readUInt16()
        room.serverPort = serverPort
        Logger.info("Minecraft server is ready: 127.0.0.1:\(serverPort)")
    }
    
    /// 向联机中心发送请求。
    /// - Parameters:
    ///   - name: 请求类型。
    ///   - body: 请求体构造函数。
    /// - Returns: 联机中心的响应。
    @discardableResult
    public func sendRequest(_ name: String, timeout: Double = 5, body: (ByteBuffer) throws -> Void = { _ in }) async throws -> Scaffolding.Response {
        try assertReady()
        return try await Scaffolding.sendRequest(name, to: connection, timeout: timeout, body: body)
    }
    
    /// 发送 `c:player_ping` 请求并同步玩家列表。
    public func heartbeat() async throws {
        do {
            try await sendRequest("c:player_ping") { buf in
                buf.writeData(try encoder.encode(player))
            }
        } catch ConnectionError.timeout {
            Logger.error("Timeout occurred while sending c:player_ping request")
            if room.members.isEmpty {
                throw ConnectionError.timeout
            }
            do {
                try await sendRequest("c:ping", timeout: 1)
            } catch ConnectionError.timeout {
                Logger.info("The room has been closed")
                stop()
                throw RoomError.roomClosed
            }
        }
        let memberList: [Member] = try decoder.decode([Member].self, from: await sendRequest("c:player_profiles_list").data)
        await MainActor.run {
            self.room.members = memberList
        }
    }
    
    /// 退出房间并关闭连接。
    public func stop() {
        Logger.info("Stopping scaffolding client")
        easyTier.terminate()
        connection?.cancel()
        connection = nil
    }
    
    /// 注册一个协议。
    ///
    /// 该协议会被包含在 `c:protocols` 发送的协议列表中。
    /// - Parameter name: 协议名。
    public func registerProtocol(_ name: String) {
        self.protocols.append(name)
    }
    
    
    
    private func joinRoom(port: UInt16, checkServer: Bool) async throws {
        Logger.info("Connecting to scaffolding server...")
        self.connection = try await ConnectionUtil.makeConnection(host: "127.0.0.1", port: port)
        Logger.info("Connected to scaffolding server")
        
        room = Room(members: [], serverPort: 0)
        try await heartbeat()
        try await fetchProtocols()
        
        let serverPort: UInt16 = ByteBuffer(data: try await sendRequest("c:server_port").data).readUInt16()
        let localPort: UInt16 = try ConnectionUtil.getPort(serverPort)
        try easyTier.addPortForward(bind: "127.0.0.1:\(localPort)", destination: "\(serverNodeIp!):\(serverPort)")
        
        if checkServer {
            guard await Scaffolding.checkMinecraftServer(on: localPort) else {
                Logger.error("Minecraft server check failed")
                throw ConnectionError.invalidPort
            }
        }
        
        room.serverPort = localPort
        Logger.info("Minecraft server is ready: 127.0.0.1:\(localPort)")
    }
    
    private func fetchProtocols() async throws {
        let response: Scaffolding.Response = try await sendRequest("c:protocols") { buf in
            buf.writeData(protocols.joined(separator: "\0").data(using: .utf8)!)
        }
        guard let rawProtocols: String = response.text else {
            Logger.error("Failed to parse c:protocols response")
            self.serverProtocols = []
            return
        }
        self.serverProtocols = rawProtocols.split(separator: "\0").map(String.init)
    }
    
    private func assertReady() throws {
        guard let connection = connection else {
            throw ConnectionError.missingConnection
        }
        guard connection.state == .ready else {
            throw ConnectionError.invalidConnectionState
        }
    }
}
