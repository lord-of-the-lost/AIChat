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
    
    func sendMessage(messages: [ChatMessage]) async -> StructuredResponse? {
        guard let url = URL(string: baseURL + "chat/completions") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let systemPrompt = """
        You are an AI assistant.
        You must ALWAYS return your answer strictly in JSON format, with no extra characters, no explanations, no markdown, no code fences.

        Return data in the following format (keys and structure of the top level must always be exactly the same):

        {
          "isSuccess": Bool,
          "content": {
            "<anyKey1>": "string",
            "<anyKey2>": "string",
            ...
          },
          "error": "string or null"
        }

        Rules:
        - The top-level keys must ALWAYS be: "isSuccess", "content", and "error".
        - "content" must be an object (dictionary) with any number of key–value pairs, where keys are strings and values are strings.
        - If you can answer the user's request, set "isSuccess" to true, fill "content" with relevant data, and set "error" to null.
        - If you cannot answer, set "isSuccess" to false, set "content" to an empty object `{}`, and provide the reason in "error".
        - The output MUST be a valid JSON object with exactly this top-level structure.
        - Do not add any other text before or after JSON.

        Example:
        {
          "isSuccess": true,
          "content": {
            "languages": "Go, Python, Java",
            "summary": "Go is good for scalable backend, Python is good for ML, Java is good for enterprise."
          },
          "error": null
        }
        """
        
        let payload: [String: Any] = [
            "model": "gpt-3.5-turbo",
            "messages": [
                ["role": "system", "content": systemPrompt]
            ] + messages.map {
                ["role": $0.isUser ? "user" : "assistant", "content": $0.content]
            }
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                print("❌ Ошибка API: \(httpResponse.statusCode)")
                print(String(data: data, encoding: .utf8) ?? "нет данных")
                return StructuredResponse(isSuccess: false, content: [:], error: "API error \(httpResponse.statusCode)")
            }
            
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let choices = json["choices"] as? [[String: Any]],
               let message = choices.first?["message"] as? [String: Any],
               let content = message["content"] as? String {
                
                // 1. Пробуем распарсить как есть
                if let parsed = tryParseStructuredResponse(from: content) {
                    return parsed
                }
                
                // 2. Если не вышло — вырезаем JSON с помощью RegEx
                if let cleanedJSON = extractJSON(from: content),
                   let parsed = tryParseStructuredResponse(from: cleanedJSON) {
                    return parsed
                }
                
                // 3. Если всё сломалось — возвращаем ошибку
                return StructuredResponse(isSuccess: false, content: [:], error: "Invalid JSON from GPT")
            }
        } catch {
            print("Ошибка запроса:", error)
            return StructuredResponse(isSuccess: false, content: [:], error: error.localizedDescription)
        }
        return nil
    }
}

private extension ChatService {
    func tryParseStructuredResponse(from string: String) -> StructuredResponse? {
        guard let data = string.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(StructuredResponse.self, from: data)
    }

    func extractJSON(from text: String) -> String? {
        let pattern = "\\{(?:[^{}]|\\{[^{}]*\\})*\\}"
        if let range = text.range(of: pattern, options: .regularExpression) {
            return String(text[range])
        }
        return nil
    }
}
