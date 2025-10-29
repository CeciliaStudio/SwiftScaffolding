//
//  Member.swift
//  SwiftScaffolding
//
//  Created by 温迪 on 2025/10/29.
//

import Foundation

public struct Member: Codable {
    /// 玩家名。
    public let name: String
    /// 玩家的 `machine_id`。
    public let machineID: String
    /// 玩家的联机客户端信息。
    public let vendor: String
    
    public enum CodingKeys: String, CodingKey {
        case name
        case machineID = "machine_id"
        case vendor
    }
}
