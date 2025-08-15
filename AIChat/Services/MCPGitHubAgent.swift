//
//  MCPGitHubAgent.swift
//  AIChat
//
//  Created by Николай Игнатов on 13.08.2025.
//

import Foundation

final class MCPGitHubAgent: AIService {
    private let apiKey: String
    private let baseURL: String
    private let mcpService: MCPGitHubService
    
    init(baseURL: String, apiKey: String, githubToken: String) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.mcpService = MCPGitHubService(githubToken: githubToken)
    }
    
    func sendMessage(messages: [ChatMessage]) async -> String? {
        guard let url = URL(string: baseURL + "chat/completions") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Определяем доступные MCP инструменты
        let tools = [
            [
                "type": "function",
                "function": [
                    "name": "create_repository",
                    "description": "Создает новый GitHub репозиторий. ВСЕГДА используй этот инструмент для создания репозиториев.",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "name": [
                                "type": "string",
                                "description": "Название репозитория (обязательно)"
                            ],
                            "description": [
                                "type": "string",
                                "description": "Описание репозитория (необязательно, может быть null)"
                            ],
                            "isPrivate": [
                                "type": "boolean",
                                "description": "Приватный репозиторий (по умолчанию false - публичный)"
                            ]
                        ],
                        "required": ["name"]
                    ]
                ]
            ],
            [
                "type": "function",
                "function": [
                    "name": "get_user_info",
                    "description": "Получает информацию о текущем пользователе GitHub",
                    "parameters": [
                        "type": "object",
                        "properties": [:],
                        "required": []
                    ]
                ]
            ],
            [
                "type": "function",
                "function": [
                    "name": "search_repositories",
                    "description": "Поиск репозиториев на GitHub",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "query": [
                                "type": "string",
                                "description": "Поисковый запрос"
                            ],
                            "page": [
                                "type": "integer",
                                "description": "Номер страницы"
                            ],
                            "perPage": [
                                "type": "integer",
                                "description": "Количество результатов на странице"
                            ]
                        ],
                        "required": ["query"]
                    ]
                ]
            ]
        ]
        
        let systemPrompt = """
        ROLE: MCP GitHub Agent
        PURPOSE: Process GitHub commands using MCP (Model Context Protocol) tools.

        AVAILABLE MCP TOOLS:
        - create_repository: Создает новый GitHub репозиторий
        - get_user_info: Получает информацию о текущем пользователе GitHub
        - search_repositories: Поиск репозиториев на GitHub

        RULES:
        - ВСЕГДА используй MCP инструменты для выполнения команд
        - НЕ отвечай текстом, если можешь использовать инструмент
        - Для создания репозитория ВСЕГДА используй create_repository
        - Извлекай название репозитория из команды пользователя
        - Если описание не указано, используй null
        - Если приватность не указана, используй false (публичный)
        - Отвечай на русском языке
        - Выполняй команды немедленно, не задавай дополнительных вопросов
        """
        
        let allMessages: [[String: Any]] =
        [["role": "system", "content": systemPrompt]] +
        messages.map { ["role": $0.isUser ? "user" : "assistant", "content": $0.content] }
        
        var payload: [String: Any] = [
            "model": "gpt-3.5-turbo",
            "messages": allMessages,
            "tools": tools,
            "tool_choice": "required"
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
               let message = choices.first?["message"] as? [String: Any] {
                
                // Проверяем, есть ли tool_calls (MCP инструменты)
                if let toolCalls = message["tool_calls"] as? [[String: Any]] {
                    var results: [String] = []
                    
                    for toolCall in toolCalls {
                        if let function = toolCall["function"] as? [String: Any],
                           let name = function["name"] as? String,
                           let argumentsString = function["arguments"] as? String,
                           let argumentsData = argumentsString.data(using: .utf8),
                           let arguments = try? JSONSerialization.jsonObject(with: argumentsData) as? [String: Any] {
                            
                            print("🔧 MCP Agent: Вызываем инструмент '\(name)' с аргументами: \(arguments)")
                            
                            // Выполняем MCP инструмент
                            let mcpResult = await mcpService.executeTool(name: name, arguments: arguments)
                            
                            // Извлекаем текст из MCP результата
                            if let content = mcpResult.content.first?.text {
                                print("🔧 MCP Agent: Получен результат: \(content)")
                                results.append(content)
                            }
                        }
                    }
                    
                    return results.joined(separator: "\n\n")
                } else if let content = message["content"] as? String {
                    print("⚠️ AI не использовал инструменты, парсим команду вручную")
                    return await parseAndExecuteCommand(content)
                }
            }
        } catch {
            print("❌ MCP GitHub Agent Error:", error)
        }
        return nil
    }
    
    private func parseAndExecuteCommand(_ command: String) async -> String {
        print("🔧 Парсим команду: \(command)")
        
        let lowercased = command.lowercased()
        
        // Парсим создание репозитория
        if lowercased.contains("создай репозиторий") || lowercased.contains("create repository") {
            let words = command.components(separatedBy: .whitespaces)
            var repoName = ""
            var description: String? = nil
            var isPrivate = false
            
            // Ищем название после "репозиторий" или "repository"
            if let repoIndex = words.firstIndex(where: { $0.lowercased() == "репозиторий" || $0.lowercased() == "repository" }) {
                if repoIndex + 1 < words.count {
                    repoName = words[repoIndex + 1]
                }
            }
            
            // Проверяем на приватность
            if lowercased.contains("приватный") || lowercased.contains("private") {
                isPrivate = true
            }
            
            // Извлекаем описание (все что после "с названием" или "with name")
            if let nameIndex = command.range(of: "с названием") ?? command.range(of: "with name") {
                let afterName = String(command[nameIndex.upperBound...])
                if let descStart = afterName.firstIndex(where: { $0 != " " }) {
                    description = String(afterName[descStart...])
                }
            }
            
            // Если название не найдено, используем первое слово после команды
            if repoName.isEmpty {
                let cleanCommand = command.replacingOccurrences(of: "создай репозиторий", with: "")
                    .replacingOccurrences(of: "create repository", with: "")
                    .trimmingCharacters(in: .whitespaces)
                repoName = cleanCommand.components(separatedBy: .whitespaces).first ?? "new-repo"
            }
            
            print("🔧 Парсинг завершен: название=\(repoName), описание=\(description ?? "nil"), приватный=\(isPrivate)")
            
            // Выполняем создание репозитория
            let mcpResult = await mcpService.executeTool(name: "create_repository", arguments: [
                "name": repoName,
                "description": description as Any,
                "isPrivate": isPrivate
            ])
            
            return mcpResult.content.first?.text ?? "❌ Ошибка создания репозитория"
        }
        
        return "❌ Не удалось распознать команду: \(command)"
    }
}
