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
    @Published var notionToken: String = UserDefaults.standard.string(forKey: "notionToken") ?? ""
    
    private let service: ChatService
    
    init(apiKey: String, githubToken: String = "", notionToken: String = "") {
        self.service = ChatService(apiKey: apiKey, githubToken: githubToken, notionToken: notionToken)
        self.githubToken = githubToken
        self.notionToken = notionToken
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
            
            print("📱 ChatViewModel: Отправляем сообщения в ChatService")
            print("📱 Всего сообщений: \(messages.count)")
            
            // Отправляем все сообщения через единого AI агента
            let result = await service.sendMessage(messages)
            
            if let result = result {
                print("📱 ChatViewModel: Получен ответ от ChatService")
                print("📱 Длина ответа: \(result.count) символов")
                print("📱 Первые 100 символов: \(result.prefix(100))...")
                
                // Проверяем, есть ли MCP предложения
                if hasMCPSuggestion(result) {
                    let cleanResult = stripMCPTags(result)
                    messages.append(ChatMessage(author: .aiAgent, content: cleanResult, isUser: false))
                } else {
                    messages.append(ChatMessage(author: .aiAgent, content: result, isUser: false))
                }
            } else {
                print("📱 ChatViewModel: Получен nil ответ от ChatService")
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
