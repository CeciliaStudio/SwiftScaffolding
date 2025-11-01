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
    /// 玩家类型。
    public let kind: Kind
    
    public enum Kind: String, Codable {
        case host = "HOST"
        case guest = "GUEST"
    }
    
    public enum CodingKeys: String, CodingKey {
        case name
        case machineID = "machine_id"
        case vendor
        case kind
    }
    
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decode(String.self, forKey: .name)
        self.machineID = try container.decode(String.self, forKey: .machineID)
        self.vendor = try container.decode(String.self, forKey: .vendor)
        self.kind = try container.decodeIfPresent(Member.Kind.self, forKey: .kind) ?? .guest
    }
    
    public init(name: String, machineID: String, vendor: String, kind: Kind) {
        self.name = name
        self.machineID = machineID
        self.vendor = vendor
        self.kind = kind
    }
}
