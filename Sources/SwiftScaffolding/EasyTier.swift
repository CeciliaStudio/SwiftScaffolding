//
//  EasyTier.swift
//  SwiftScaffolding
//
//  Created by 温迪 on 2025/10/26.
//

import Foundation
import SwiftyJSON

public final class EasyTier {
    public let coreURL: URL
    public let cliURL: URL
    public let logURL: URL?
    public let options: [Option]
    
    public private(set) var process: Process?
    private var rpcPort: UInt16?
    
    /// 创建一个 EasyTier 实例。
    /// - Parameters:
    ///   - coreURL: `easytier-core` 的路径。
    ///   - cliURL: `easytier-cli` 的路径。
    ///   - logURL: `easytier-core` 日志路径，为 `nil` 时不输出日志。
    ///   - options: 启动时的选项。
    public init(coreURL: URL, cliURL: URL, logURL: URL?, _ options: Option...) {
        self.coreURL = coreURL
        self.cliURL = cliURL
        self.logURL = logURL
        self.options = options
    }
    
    /// 启动 EasyTier。
    /// - Parameters:
    ///   - args: `easytier-core` 的参数。
    ///   - terminationHandler: 进程退出回调，不会在正常 `terminate()` 时被调用。
    public func launch(_ args: String..., terminationHandler: ((Process) -> Void)? = nil) throws {
        terminate()
        let rpcPort: UInt16 = try ConnectionUtil.getPort()
        self.rpcPort = rpcPort
        Logger.info("RPC port: \(rpcPort)")
        let rpcArgs: [String] = ["--rpc-portal", "\(rpcPort)", "--rpc-portal-whitelist", "127.0.0.1"]
        let args: [String] = args + rpcArgs + options.flatMap { option in
            switch option {
            case .p2pOnly: ["--p2p-only"]
            case .peer(let address): ["-p", address]
            }
        }
        Logger.info("Launching easytier-core with \(args)")
        let process: Process = Process()
        process.executableURL = coreURL
        process.arguments = args
        
        if let logURL = logURL {
            if FileManager.default.fileExists(atPath: logURL.path) {
                try FileManager.default.removeItem(at: logURL)
            }
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
            let handle: FileHandle = try FileHandle(forWritingTo: logURL)
            process.standardOutput = handle
            process.standardError = handle
        } else {
            process.standardOutput = nil
            process.standardError = nil
        }
        process.terminationHandler = { [weak self] process in
            self?.process = nil
            Logger.error("EasyTier crashed")
            terminationHandler?(process)
        }
        
        try process.run()
        self.process = process
    }
    
    /// 关闭 `easytier-core` 进程。
    public func terminate() {
        if let process = self.process {
            process.terminationHandler = nil
            process.terminate()
            self.process = nil
        }
    }
    
    /// 以 JSON 模式调用 `easytier-cli`。
    /// 如果 `easytier-cli` 报错，会抛出 `EasyTierError.cliError` 错误。
    /// - Parameter args: `easytier-cli` 的参数。
    /// - Returns: 调用结果，不是 JSON 时为 `nil`。
    @discardableResult
    public func callCLI(_ args: String...) throws -> JSON? {
        guard let rpcPort = self.rpcPort else { throw ConnectionError.failedToAllocatePort }
        let process: Process = Process()
        process.executableURL = cliURL
        process.arguments = ["--rpc-portal", "127.0.0.1:\(rpcPort)", "--output", "json"] + args
        
        let output: Pipe = Pipe()
        let error: Pipe = Pipe()
        process.standardOutput = output
        process.standardError = error
        
        try process.run()
        process.waitUntilExit()
        
        let errorData: Data = error.fileHandleForReading.availableData
        guard errorData.isEmpty else {
            throw EasyTierError.cliError(message: String(data: errorData, encoding: .utf8) ?? "<Failed to decode>")
        }
        guard let data: Data = try output.fileHandleForReading.readToEnd() else {
            throw NSError(domain: "EasyTier", code: -1, userInfo: [NSLocalizedDescriptionKey: "Reached EOF of CLI stdout"])
        }
        return try? JSON(data: data)
    }
    
    
    public enum EasyTierError: LocalizedError {
        /// `easytier-cli` 报错。
        case cliError(message: String)
        
        public var errorDescription: String? {
            switch self {
            case .cliError(let message):
                return String(
                    format: NSLocalizedString(
                        "EasyTierError.cliError",
                        bundle: .module,
                        comment: "EasyTier CLI 报错"
                    ),
                    message
                )
            }
        }
    }
    
    public enum Option {
        /// 是否开启仅 P2P 模式，不转发流量。
        /// `--p2p-only`
        case p2pOnly
        
        /// 最初要连接的对等节点。
        /// `-p`, `${address}`
        case peer(address: String)
    }
}

extension EasyTier {
    /// 添加端口转发规则。
    /// - Parameters:
    ///   - protocol: 使用的协议类型，默认为 `tcp`。
    ///   - bind: 本地绑定地址。
    ///   - destination: 目标地址。
    public func addPortForward(protocol: String = "tcp", bind: String, destination: String) throws {
        try callCLI("port-forward", "add", `protocol`, bind, destination)
        Logger.info("\(destination) is bound to \(bind)")
    }
    
    /// 移除端口转发规则。
    /// - Parameters:
    ///   - protocol: 使用的协议类型，默认为 `tcp`。
    ///   - bind: 本地绑定地址。
    ///   - destination: 目标地址。
    public func removePortForward(protocol: String = "tcp", bind: String) throws {
        try callCLI("port-forward", "remove", `protocol`, bind)
    }
    
    /// 获取当前连接的所有节点列表。
    /// - Returns: 包含所有已连接节点的 `Peer` 数组。
    public func peerList() throws -> [Peer] {
        let result: JSON = try callCLI("peer", "list")!
        return result.arrayValue.map { peer in
            return Peer(
                ipv4: peer["ipv4"].stringValue,
                hostname: peer["hostname"].stringValue,
                tunnel: peer["tunnel_proto"].stringValue.split(separator: ",").map(String.init)
            )
        }
    }
    
    public struct Peer {
        public let ipv4: String
        public let hostname: String
        public let tunnel: [String]
    }
}
