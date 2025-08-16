//
//  Agent.swift
//  AIChat
//
//  Created by Николай Игнатов on 13.08.2025.
//

enum Agent: String, CaseIterable, Identifiable {
    case user = "Вы"
    case aiAgent = "AI Assistant"
    
    var id: String { rawValue }
}
