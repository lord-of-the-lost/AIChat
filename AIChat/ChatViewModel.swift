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
    @Published var currentAgent: Agent = .gptDeveloper
    
    private let service: ChatService
    
    init(apiKey: String) {
        self.service = ChatService(apiKey: apiKey)
    }
    
    func sendUserMessage() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        let userMessage = ChatMessage(author: .user, content: trimmed, isUser: true)
        messages.append(userMessage)
        inputText = ""
        
        runPipeline()
    }
    
    private func runPipeline() {
        Task {
            isLoading = true
            currentAgent = .gptDeveloper
            
            // 1️⃣ Отправляем историю разработчику
            guard let devReplyRaw = await service.sendToDeveloper(messages) else {
                isLoading = false
                return
            }
            
            let cleanDevReply = stripTags(devReplyRaw)
            messages.append(ChatMessage(author: .gptDeveloper, content: cleanDevReply, isUser: false))
            
            // 2️⃣ Проверяем готовность ТЗ
            if isDeveloperSpecReady(devReplyRaw) {
                currentAgent = .gptReviewer
                
                guard let reviewReplyRaw = await service.sendToReviewer(messages) else {
                    isLoading = false
                    return
                }
                
                let cleanReviewReply = stripTags(reviewReplyRaw)
                messages.append(ChatMessage(author: .gptReviewer, content: cleanReviewReply, isUser: false))
            }
            
            isLoading = false
        }
    }
    
    /// Проверяем маркеры завершения ТЗ
    private func isDeveloperSpecReady(_ text: String) -> Bool {
        text.contains("<STATE: SPEC_READY>") &&
        text.contains("<TECH_SPEC>") &&
        text.contains("</TECH_SPEC>")
    }
    
    /// Убираем все теги `<...>`
    private func stripTags(_ text: String) -> String {
        let pattern = "<[^>]+>"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
    }
}
