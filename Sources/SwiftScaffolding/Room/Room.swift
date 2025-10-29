//
//  Room.swift
//  SwiftScaffolding
//
//  Created by 温迪 on 2025/10/29.
//

import Foundation
import Network

public final class Room {
    private static let connectQueue: DispatchQueue = DispatchQueue(label: "SwiftScaffolding.Connect")
    public private(set) var members: [Member]
    private var connection: NWConnection?
    private let easyTier: EasyTier
    
    public init(easyTier: EasyTier) {
        self.members = []
        self.easyTier = easyTier
    }
    
    public func connect(code: String) async throws {
        let pattern = #/^U\/[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}$/#
        guard code.wholeMatch(of: pattern) != nil else {
            throw RoomCodeError.invalidRoomCode
        }
        let networkName: String = "scaffolding-mc-\(code.dropFirst(2).prefix(9))"
        let networkSecret: String = String(code.dropFirst(2).suffix(9))
        try easyTier.launch(
            "--no-tun", "-d",
            "--network-name", networkName,
            "--network-secret", networkSecret,
            "-p", "tcp://public.easytier.cn:11010"
        )
        for i in 1...15 {
            try await Task.sleep(for: .seconds(1))
            guard let node = try? easyTier.getPeerList().first(where: { $0.hostname.starts(with: "scaffolding-mc-server") }) else {
                continue
            }
            let port: String = String(node.hostname.dropFirst("scaffolding-mc-server-".count))
            try easyTier.addPortForward(bind: "127.0.0.1:\(port)", destination: "\(node.ipv4):\(port)")
            try await createConnection(to: node.ipv4, port: port)
            return
        }
        throw ConnectionError.timeout
    }
    
    private func createConnection(to host: String, port: String) async throws {
        guard let port: NWEndpoint.Port = NWEndpoint.Port(port) else {
            throw ConnectionError.invalidPort
        }
        
        let connection: NWConnection = NWConnection(to: .hostPort(host: NWEndpoint.Host(host), port: port), using: .tcp)
        try await withCheckedThrowingContinuation { continuation in
            connection.stateUpdateHandler = { state in
                if state == .ready {
                    self.connection = connection
                    continuation.resume()
                    return
                }
                switch state {
                case .failed(let error), .waiting(let error):
                    continuation.resume(throwing: error)
                case .cancelled:
                    continuation.resume(throwing: ConnectionError.cancelled)
                default:
                    break
                }
            }
            connection.start(queue: Self.connectQueue)
        }
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
