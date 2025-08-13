//
//  ChatService.swift
//  AIChat
//
//  Created by Николай Игнатов on 10.08.2025.
//

import Foundation

protocol AIService {
    func sendMessage(messages: [ChatMessage]) async -> String?
}

final class ChatService {
    private let developerAgent: AIService
    private let reviewerAgent: AIService
    private let apiKey: String
    private let baseURL = "https://api.proxyapi.ru/openai/v1/"
    
    init(apiKey: String) {
        self.apiKey = apiKey
        self.developerAgent = DeveloperAgent(baseURL: baseURL, apiKey: apiKey)
        self.reviewerAgent = ReviewerAgent(baseURL: baseURL, apiKey: apiKey)
    }
    
    func sendToDeveloper(_ messages: [ChatMessage]) async -> String? {
        await developerAgent.sendMessage(messages: messages)
    }
    
    func sendToReviewer(_ messages: [ChatMessage]) async -> String? {
        await reviewerAgent.sendMessage(messages: messages)
    }
    
    func validateKey() async -> Bool {
        guard let url = URL(string: baseURL + "models") else { return false }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                return httpResponse.statusCode == 200
            }
        } catch {
            return false
        }
        return false
    }
    
    /// Вызывает сначала разработчика, потом ревьюера
    func sendSequentially(_ messages: [ChatMessage]) async -> [ChatMessage] {
        var updatedMessages = messages
        
        if let devReply = await sendToDeveloper(updatedMessages) {
            let devMessage = ChatMessage(author: .gptDeveloper, content: devReply, isUser: false)
            updatedMessages.append(devMessage)
            
            if let reviewReply = await sendToReviewer(updatedMessages) {
                let reviewMessage = ChatMessage(author: .gptReviewer, content: reviewReply, isUser: false)
                updatedMessages.append(reviewMessage)
            }
        }
        
        return updatedMessages
    }
}

// MARK: - Agent 1
final class DeveloperAgent: AIService {
    private let apiKey: String
    private let baseURL: String
    
    init(baseURL: String, apiKey: String) {
        self.baseURL = baseURL
        self.apiKey = apiKey
    }
    
    func sendMessage(messages: [ChatMessage]) async -> String? {
        guard let url = URL(string: baseURL + "chat/completions") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let systemPrompt = """
        You are an experienced iOS developer working on a design system.
        
        LANGUAGE RULES:
        - All communication (interview questions, clarifications, explanations) MUST be in Russian.
        - The full text of the technical specification inside <TECH_SPEC> MUST also be entirely in Russian (no English, except variable/class names).
        - Any code snippets MUST be in English.
        
        COMMUNICATION PROTOCOL (MANDATORY):
        - While interviewing, your response MUST start with exactly "<STATE: INTERVIEW>" on the first line,
          then ask exactly ONE concise question to gather requirements for a new UI component.
        - When you have enough information to compile a complete technical specification (TS),
          your response MUST start with exactly "<STATE: SPEC_READY>" on the first line,
          and then include the final spec wrapped strictly like:
          <TECH_SPEC>
          ... full and final TS ...
          </TECH_SPEC>
        
        Interview goals:
        - Clarify: component name, purpose/use cases, required props/configurations, styling rules,
          accessibility requirements, edge cases, platform constraints, integration points.
        
        Rules:
        - Ask one question at a time during INTERVIEW state.
        - Do NOT provide code.
        - Do NOT switch back to INTERVIEW after SPEC_READY.
        - Never include both states in one message.
        - Keep the spec clear and implementation-ready.
        """
        
        let allMessages: [[String: String]] =
        [["role": "system", "content": systemPrompt]] +
        messages.map { ["role": $0.isUser ? "user" : "assistant", "content": $0.content] }
        
        let payload: [String: Any] = [
            "model": "gpt-3.5-turbo",
            "messages": allMessages
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        return await performRequest(request: request)
    }
    
    private func performRequest(request: URLRequest) async -> String? {
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let choices = json["choices"] as? [[String: Any]],
               let message = choices.first?["message"] as? [String: Any],
               let content = message["content"] as? String {
                return content.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } catch {
            print("❌ Agent1 Error:", error)
        }
        return nil
    }
}

// MARK: - Agent 2
final class ReviewerAgent: AIService {
    private let apiKey: String
    private let baseURL: String
    
    init(baseURL: String, apiKey: String) {
        self.baseURL = baseURL
        self.apiKey = apiKey
    }
    
    func sendMessage(messages: [ChatMessage]) async -> String? {
        guard let url = URL(string: baseURL + "chat/completions") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let systemPrompt = """
        ROLE: ReviewerAgent
        PURPOSE: Review the technical specification <TECH_SPEC> prepared by DeveloperAgent.

        RULES:
        - Input: A dialogue history that MUST contain a <TECH_SPEC> block.
        - If <TECH_SPEC> is missing, malformed, or empty:
          1. Respond ONLY with:
             <STATE: REVIEW_ERROR>
             Причина: <кратко на русском, что пошло не так>
          2. Do NOT attempt to generate code or assumptions in this case.
        - If <TECH_SPEC> exists but is incomplete or unclear:
          1. Respond with:
             <STATE: REVIEW_REQUEST>
             Комментарии: <список уточнений или недостающих деталей на русском>
        - If <TECH_SPEC> is complete and clear:
          1. Respond with:
             <STATE: REVIEW_READY>
             <REVIEW_RESULT>
             ...текст ревью и/или код...
             </REVIEW_RESULT>

        LANGUAGE RULES:
        - All non-code text must be in Russian.
        - Code examples must be in English.
        - Never return an empty message. Always include a state tag and some content.
        """
        
        let allMessages: [[String: String]] =
        [["role": "system", "content": systemPrompt]] +
        messages.map { ["role": $0.isUser ? "user" : "assistant", "content": $0.content] }
        
        let payload: [String: Any] = [
            "model": "gpt-3.5-turbo",
            "messages": allMessages
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        return await performRequest(request: request)
    }
    
    private func performRequest(request: URLRequest) async -> String? {
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let choices = json["choices"] as? [[String: Any]],
               let message = choices.first?["message"] as? [String: Any],
               let content = message["content"] as? String {
                return content.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } catch {
            print("❌ Agent2 Error:", error)
        }
        return nil
    }
}
