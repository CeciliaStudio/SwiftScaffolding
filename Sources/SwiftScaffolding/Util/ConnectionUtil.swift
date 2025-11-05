//
//  ConnectionUtil.swift
//  SwiftScaffolding
//
//  Created by 温迪 on 2025/11/1.
//

import Foundation
import Network

public final class ConnectionUtil {
    /// 从连接异步接收指定长度的数据。
    /// - Parameters:
    ///   - connection: 目标连接。
    ///   - length: 数据长度。
    /// - Returns: 接收到的数据。
    public static func receiveData(from connection: NWConnection, length: Int, timeout: Int = 10) async throws -> Data {
        if length == 0 { return Data() }
        return try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { continuation in
                    connection.receive(minimumIncompleteLength: length, maximumLength: length) { data, _, _, error in
                        if let error = error {
                            continuation.resume(throwing: error)
                            return
                        }
                        guard let data = data, data.count == length else {
                            continuation.resume(throwing: ConnectionError.orderlyShutdown)
                            return
                        }
                        continuation.resume(returning: data)
                    }
                }
            }
            group.addTask {
                try await Task.sleep(for: .seconds(timeout))
                throw ConnectionError.timeout
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
    
    private init() {
    }
}
