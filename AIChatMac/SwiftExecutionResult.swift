//
//  SwiftExecutionResult.swift
//  AIChatMac
//
//  Created by Николай Игнатов on 19.08.2025.
//

import Foundation

struct SwiftExecutionResult {
    let success: Bool
    let code: String
    let output: String
    let error: String
    let executionTime: TimeInterval
    let timestamp: Date
    
    init(success: Bool, code: String, output: String = "", error: String = "", executionTime: TimeInterval = 0) {
        self.success = success
        self.code = code
        self.output = output
        self.error = error
        self.executionTime = executionTime
        self.timestamp = Date()
    }
}
