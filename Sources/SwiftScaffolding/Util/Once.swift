//
//  Once.swift
//  SwiftScaffolding
//
//  Created by 温迪 on 2026/1/28.
//

actor Once {
    private var done: Bool = false
    func run(_ body: () -> Void) {
        guard !done else { return }
        done = true
        body()
    }
}
