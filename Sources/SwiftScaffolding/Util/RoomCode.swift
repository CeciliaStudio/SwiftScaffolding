//
//  RoomCode.swift
//  SwiftScaffolding
//
//  Created by 温迪 on 2025/10/30.
//

import Foundation

/// https://github.com/Scaffolding-MC/Scaffolding-MC/blob/main/README.md#联机房间码
public final class RoomCode {
    private static let charset: [Character] = "0123456789ABCDEFGHJKLMNPQRSTUVWXYZ".map { $0 }
    
    /// 生成符合 Scaffolding 规范的房间码。
    /// - Returns: 生成的房间码。
    public static func generate() -> String {
        let b: Int = 34
        var digits: [Int] = []
        var sumMod7: Int = 0
        var powMod7: Int = 1
        for _ in 0..<15 {
            let d: Int = Int.random(in: 0..<b)
            digits.append(d)
            sumMod7 = (sumMod7 + d * powMod7) % 7
            powMod7 = (powMod7 * b) % 7
        }
        let invPow15: Int = 6
        let base: Int = ((7 - (sumMod7 % 7)) * invPow15) % 7
        let kMax: Int = ((b - 1) - base) / 7
        let d15: Int = base + 7 * Int.random(in: 0...kMax)
        digits.append(d15)
        
        var code: String = ""
        for i in 0..<16 {
            let idx: Int = digits[i]
            code.append(charset[idx])
            if i == 3 || i == 7 || i == 11 { code += "-" }
        }
        return "U/" + String(code.reversed())
    }
    
    /// 验证是否是符合 Scaffolding 规范的房间码。
    /// - Parameter code: 房间码。
    /// - Returns: 一个布尔值，为 `true` 时代表该房间码符合 Scaffolding 规范。
    public static func isValid(code: String) -> Bool {
        guard code.wholeMatch(of: #/^U\/[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}$/#) != nil else {
            return false
        }
        let code: String = String(code.dropFirst(2))
        var value: Int = 0
        for char in code {
            if char == "-" { continue }
            guard let index = charset.firstIndex(of: char) else {
                return false
            }
            value = value * 34 + index
            value %= 7
        }
        return value == 0
    }
    
    private init() {
    }
}
