//
//  Errors.swift
//  SwiftScaffolding
//
//  Created by 温迪 on 2025/10/30.
//

import Foundation

public enum ConnectionError: LocalizedError, Equatable {
    case invalidPort
    case timeout
    case cancelled
    case missingConnection
    case invalidConnectionState
    case failedToAllocatePort
    case noEnoughBytes
    case failedToDecodeString
    
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
        case .noEnoughBytes:
            return NSLocalizedString(
                "ConnectionError.noEnoughBytes",
                bundle: Bundle.module,
                comment: "ByteBuffer 读取即将越界"
            )
        case .failedToDecodeString:
            return NSLocalizedString(
                "ConnectionError.failedToDecodeString",
                bundle: Bundle.module,
                comment: "解析 UTF-8 字符串失败"
            )
        }
    }
}

public enum RoomError: LocalizedError {
    case invalidRoomCode
    case roomClosed
    case playerInfoMismatch
    
    public var errorDescription: String? {
        switch self {
        case .invalidRoomCode:
            return NSLocalizedString(
                "RoomError.invalidRoomCode",
                bundle: Bundle.module,
                comment: "房间码无效"
            )
        case .roomClosed:
            return NSLocalizedString(
                "RoomError.roomClosed",
                bundle: Bundle.module,
                comment: "c:ping 超时"
            )
        case .playerInfoMismatch:
            return NSLocalizedString(
                "RoomError.playerInfoMismatch",
                bundle: Bundle.module,
                comment: "两次 c:player_ping 发送的信息不一致"
            )
        }
    }
}
