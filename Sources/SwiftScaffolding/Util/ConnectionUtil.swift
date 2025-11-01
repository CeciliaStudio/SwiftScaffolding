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
    public static func receiveData(from connection: NWConnection, length: Int) async throws -> Data {
        return try await withCheckedThrowingContinuation { continuation in
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
    
    private init() {
    }
}
