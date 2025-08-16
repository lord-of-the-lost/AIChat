//
//  ChatViewModel.swift
//  AIChat
//
//  Created by Николай Игнатов on 13.08.2025.
//

import Foundation

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var inputText = ""
    @Published var isLoading = false
    @Published var currentAgent: Agent = .aiAgent
    @Published var githubToken: String = UserDefaults.standard.string(forKey: "githubToken") ?? ""
    
    private let service: ChatService
    
    init(apiKey: String, githubToken: String = "") {
        self.service = ChatService(apiKey: apiKey, githubToken: githubToken)
        self.githubToken = githubToken
    }
    
    func sendUserMessage() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        let userMessage = ChatMessage(author: .user, content: trimmed, isUser: true)
        messages.append(userMessage)
        inputText = ""
        
        // Отправляем все сообщения через единого AI агента
        processMessage()
    }
    
    private func processMessage() {
        Task {
            isLoading = true
            currentAgent = .aiAgent
            
            // Отправляем все сообщения через единого AI агента
            let result = await service.sendMessage(messages)
            
            if let result = result {
                // Проверяем, есть ли MCP предложения
                if hasMCPSuggestion(result) {
                    let cleanResult = stripMCPTags(result)
                    messages.append(ChatMessage(author: .aiAgent, content: cleanResult, isUser: false))
                } else {
                    messages.append(ChatMessage(author: .aiAgent, content: result, isUser: false))
                }
            }
            
            isLoading = false
        }
    }
    
    /// Убираем теги MCP предложений
    private func stripMCPTags(_ text: String) -> String {
        let pattern = "<MCP_SUGGESTION>.*?</MCP_SUGGESTION>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
    }
    
    /// Проверяем наличие MCP предложения
    private func hasMCPSuggestion(_ text: String) -> Bool {
        text.contains("<MCP_SUGGESTION>") && text.contains("</MCP_SUGGESTION>")
    }
}
