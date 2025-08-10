//
//  ChatMessage.swift
//  AIChat
//
//  Created by Николай Игнатов on 10.08.2025.
//

import Foundation

struct ChatMessage: Identifiable {
    let id = UUID()
    let content: String
    let isUser: Bool
}
