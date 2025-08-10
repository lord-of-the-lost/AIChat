//
//  ChatService.swift
//  AIChat
//
//  Created by Николай Игнатов on 10.08.2025.
//

import Foundation

final class ChatService {
    private let apiKey: String
    private let baseURL = "https://api.proxyapi.ru/openai/v1/"
    init(apiKey: String) { self.apiKey = apiKey }
    
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
    
    func sendMessage(messages: [ChatMessage]) async -> String? {
        guard let url = URL(string: baseURL + "chat/completions") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let payload: [String: Any] = [
            "model": "gpt-3.5-turbo",
            "messages": messages.map {
                ["role": $0.isUser ? "user" : "assistant", "content": $0.content]
            }
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                print("❌ Ошибка API: \(httpResponse.statusCode)")
                print(String(data: data, encoding: .utf8) ?? "нет данных")
                return "Ошибка: \(httpResponse.statusCode)"
            }
            
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                print("📩 Ответ API:", json)
                if let choices = json["choices"] as? [[String: Any]],
                   let message = choices.first?["message"] as? [String: Any],
                   let content = message["content"] as? String {
                    return content.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        } catch {
            print("Ошибка запроса:", error)
        }
        return nil
    }
}
