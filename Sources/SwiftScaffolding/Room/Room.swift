//
//  Room.swift
//  SwiftScaffolding
//
//  Created by 温迪 on 2025/10/29.
//

import Foundation
import Network

public final class Room {
    /// 房客列表。
    public internal(set) var members: [Member] = []
    /// Minecraft 服务器端口。
    public internal(set) var serverPort: UInt16?
}
