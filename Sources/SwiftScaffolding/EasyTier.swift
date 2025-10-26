//
//  EasyTier.swift
//  SwiftScaffolding
//
//  Created by 温迪 on 2025/10/26.
//

import Foundation
import SwiftyJSON

public final class EasyTier {
    /// `easytier-core` 的路径。
    private let coreURL: URL
    
    /// `easytier-cli` 的路径。
    private let cliURL: URL
    
    /// `easytier-core` 日志路径，为 `nil` 时不输出日志。
    private let logURL: URL?
    
    /// `easytier-core` 进程。
    public private(set) var process: Process?
    
    public init(coreURL: URL, cliURL: URL, logURL: URL?) {
        self.coreURL = coreURL
        self.cliURL = cliURL
        self.logURL = logURL
    }
    
    public func launch(_ args: [String]) throws {
        let process: Process = Process()
        process.executableURL = coreURL
        process.arguments = args
        
        if let logURL = logURL {
            if !FileManager.default.fileExists(atPath: logURL.path) {
                FileManager.default.createFile(atPath: logURL.path, contents: nil)
            }
            let handle: FileHandle = try FileHandle(forWritingTo: logURL)
            process.standardOutput = handle
            process.standardError = handle
        } else {
            process.standardOutput = nil
            process.standardError = nil
        }
        
        try process.run()
        self.process = process
    }
    
    public func callCLI(_ args: String...) throws -> JSON {
        let process: Process = Process()
        process.executableURL = cliURL
        process.arguments = ["--output", "json"] + args
        
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
        return try JSON(data: data)
    }
    
    
    public enum EasyTierError: Error {
        /// `easytier-core` 进程已存在。
        case processAlreadyExists
        
        /// `easytier-cli` 报错。
        case cliError(message: String)
    }
}
