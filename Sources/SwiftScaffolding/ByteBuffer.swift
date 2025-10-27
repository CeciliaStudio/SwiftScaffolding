//
//  ByteBuffer.swift
//  SwiftScaffolding
//
//  Created by 温迪 on 2025/10/27.
//

import Foundation

public class ByteBuffer {
    public private(set) var data: Data
    private var index: Int
    
    // MARK: - 初始化
    
    /// 构造一个 `ByteBuffer` 用于读取数据包内容
    /// - Parameter data: 数据包内容
    public init(data: Data) {
        self.data = data
        self.index = 0
    }
    
    /// 构造一个 `ByteBuffer` 用于写入数据
    public init() {
        self.data = Data()
        self.index = 0
    }
    
    // MARK: - 读取
    
    /// 读取 `n` 个字节的数据
    /// - Parameter length: 读取的数据长度
    /// - Returns: 长度为 `length` 字节的 `Data`
    public func readData(length: Int) -> Data {
        if length == 0 { return Data() }
        defer { index += length }
        return data.subdata(in: index..<index + length)
    }
    
    /// 读取一个 `UInt8`
    /// - Returns: UInt8
    public func readUInt8() -> UInt8 {
        let data: Data = readData(length: 1)
        let value: UInt8 = data.withUnsafeBytes { $0.load(as: UInt8.self) }
        return value
    }
    
    /// 读取一个 `UInt16`（大端序）
    /// - Returns: UInt16
    public func readUInt16() -> UInt16 {
        let data: Data = readData(length: 2)
        let value: UInt16 = data.withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }
        return value
    }
    
    /// 读取一个 `UInt32`（大端序）
    /// - Returns: UInt32
    public func readUInt32() -> UInt32 {
        let data: Data = readData(length: 4)
        let value: UInt32 = data.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        return value
    }
    
    // MARK: - 写入
    
    /// 写入一段 `Data`
    /// - Parameter data: 写入的 `Data`
    public func writeData(_ data: Data) {
        self.data.append(data)
    }
    
    /// 写入一个 UInt8
    /// - Parameter value: 要写入的 UInt8
    public func writeUInt8(_ value: UInt8) {
        var v: UInt8 = value
        let d: Data = Data(bytes: &v, count: MemoryLayout<UInt8>.size)
        writeData(d)
    }
    
    /// 写入一个 UInt16（大端序）
    /// - Parameter value: 要写入的 UInt16
    public func writeUInt16(_ value: UInt16) {
        var v: UInt16 = value.bigEndian
        let d: Data = Data(bytes: &v, count: MemoryLayout<UInt16>.size)
        writeData(d)
    }
    
    /// 写入一个 UInt32（大端序）
    /// - Parameter value: 要写入的 UInt32
    public func writeUInt32(_ value: UInt32) {
        var v: UInt32 = value.bigEndian
        let d: Data = Data(bytes: &v, count: MemoryLayout<UInt32>.size)
        writeData(d)
    }
}
