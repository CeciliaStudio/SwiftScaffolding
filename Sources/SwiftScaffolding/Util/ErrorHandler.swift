//
//  ErrorHandler.swift
//  SwiftScaffolding
//
//  Created by 温迪 on 2025/11/1.
//

import Foundation

/// 异步错误处理协议。
public protocol ErrorHandler {
    /// 处理库产生的错误，例如记录到日志系统。
    /// - Parameter error: 错误对象。
    func handle(_ error: Error) -> Void
}
