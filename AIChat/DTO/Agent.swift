//
//  Agent.swift
//  AIChat
//
//  Created by Николай Игнатов on 13.08.2025.
//

enum Agent: String, CaseIterable, Identifiable {
    case user = "Вы"
    case gptDeveloper = "Developer Agent"
    case gptReviewer = "Reviewer Agent"
    case mcpGitHubAgent = "GitHub MCP Agent"
    
    var id: String { rawValue }
}
