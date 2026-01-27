//
//  Errors.swift
//  SwiftScaffolding
//
//  Created by 温迪 on 2025/10/30.
//

import Foundation

public enum ConnectionError: LocalizedError {
    case invalidPort
    case timeout
    case cancelled
    case missingConnection
    case invalidConnectionState
    case failedToAllocatePort
    
    public var errorDescription: String? {
        switch self {
        case .invalidPort:
            return NSLocalizedString(
                "ConnectionError.invalidPort",
                bundle: Bundle.module,
                comment: "联机中心返回了一个非法端口号"
            )
        case .timeout:
            return NSLocalizedString(
                "ConnectionError.timeout",
                bundle: Bundle.module,
                comment: "接收数据或建立连接超时"
            )
        case .cancelled:
            return NSLocalizedString(
                "ConnectionError.connectionClosed",
                bundle: Bundle.module,
                comment: "连接被关闭"
            )
        case .missingConnection, .invalidConnectionState:
            return NSLocalizedString(
                "ConnectionError.connectionIsNotReady",
                bundle: Bundle.module,
                comment: "未建立连接，或者连接状态异常"
            )
        case .failedToAllocatePort:
            return NSLocalizedString(
                "ConnectionError.failedToAllocatePort",
                bundle: Bundle.module,
                comment: "端口分配失败"
            )
        }
    }
}

public enum RoomCodeError: LocalizedError {
    case invalidRoomCode
    
    public var errorDescription: String? {
        return NSLocalizedString(
            "RoomCodeError.invalidRoomCode",
            bundle: Bundle.module,
            comment: "房间码无效"
        )
    }
}
