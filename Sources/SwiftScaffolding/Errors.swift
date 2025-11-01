//
//  Errors.swift
//  SwiftScaffolding
//
//  Created by 温迪 on 2025/10/30.
//

import Foundation

public enum ConnectionError: Error {
    case invalidPort
    case timeout
    case cancelled
    case missingConnection
    case invalidConnectionState
    case orderlyShutdown
}

public enum RoomCodeError: Error {
    case invalidRoomCode
}
