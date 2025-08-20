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
    private let aiAgent: UniversalAIAgent
    private let apiKey: String
    private let baseURL = "https://api.proxyapi.ru/openai/v1/"
    
    init(apiKey: String, githubToken: String? = nil) {
        self.apiKey = apiKey
        self.aiAgent = UniversalAIAgent(apiKey: apiKey, githubToken: githubToken)
    }
    
    func sendMessage(_ messages: [ChatMessage]) async -> String? {
        await aiAgent.sendMessage(messages: messages)
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
}

// MARK: - Universal AI Agent
final class UniversalAIAgent: AIService {
    private let apiKey: String
    private let baseURL = "https://api.proxyapi.ru/openai/v1/"
    private let mcpService: MCPGitHubService?
    
    init(apiKey: String, githubToken: String? = nil) {
        self.apiKey = apiKey
        
        if let githubToken = githubToken, !githubToken.isEmpty {
            self.mcpService = MCPGitHubService(githubToken: githubToken)
        } else {
            self.mcpService = nil
        }
    }
    
    func sendMessage(messages: [ChatMessage]) async -> String? {
        guard let url = URL(string: baseURL + "chat/completions") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Определяем доступные MCP инструменты
        var tools: [[String: Any]] = []
        
        if mcpService != nil {
            tools = [
                [
                    "type": "function",
                    "function": [
                        "name": "get_user_repositories",
                        "description": "Получает список репозиториев текущего пользователя GitHub",
                        "parameters": [
                            "type": "object",
                            "properties": [
                                "page": [
                                    "type": "integer",
                                    "description": "Номер страницы (по умолчанию 1)"
                                ],
                                "perPage": [
                                    "type": "integer", 
                                    "description": "Количество репозиториев на странице (по умолчанию 30)"
                                ]
                            ],
                            "required": []
                        ]
                    ]
                ],
                [
                    "type": "function",
                    "function": [
                        "name": "get_issues",
                        "description": "Получает список Issues из GitHub репозитория",
                        "parameters": [
                            "type": "object",
                            "properties": [
                                "owner": [
                                    "type": "string",
                                    "description": "Владелец репозитория"
                                ],
                                "repo": [
                                    "type": "string",
                                    "description": "Название репозитория"
                                ],
                                "state": [
                                    "type": "string",
                                    "description": "Состояние Issues: 'open', 'closed', 'all' (по умолчанию 'open')"
                                ]
                            ],
                            "required": ["owner", "repo"]
                        ]
                    ]
                ],
                [
                    "type": "function",
                    "function": [
                        "name": "create_repository",
                        "description": "Создает новый GitHub репозиторий",
                        "parameters": [
                            "type": "object",
                            "properties": [
                                "name": [
                                    "type": "string",
                                    "description": "Название репозитория"
                                ],
                                "description": [
                                    "type": "string",
                                    "description": "Описание репозитория"
                                ],
                                "isPrivate": [
                                    "type": "boolean",
                                    "description": "Приватный репозиторий (по умолчанию false)"
                                ]
                            ],
                            "required": ["name"]
                        ]
                    ]
                ]
            ]
        }
        
        let systemPrompt = """
        ROLE: Universal AI Assistant with GitHub MCP Integration and Swift Code Execution
        PURPOSE: Be a helpful conversational AI that can work with GitHub via MCP tools and execute Swift code.

        LANGUAGE RULES:
        - All communication MUST be in Russian.
        - Be friendly, helpful, and conversational.
        - Provide informative and engaging responses on any topic.

        SWIFT CODE EXECUTION:
        - When user provides Swift code or asks to write/test Swift code, automatically detect and execute it.
        - Look for Swift keywords: func, let, var, import, print, class, struct, enum, etc.
        - Code execution happens automatically in the background.
        - Always explain what the code does before or after execution.
        - If code has errors, explain them clearly and suggest fixes.
        
        SWIFT CODE DETECTION:
        - Code blocks with ```swift or ```
        - Messages containing Swift keywords
        - Requests like "напиши код", "создай функцию", "проверь этот код"
        
        GITHUB MCP INTEGRATION:
        - When user mentions GitHub-related topics (repositories, issues, projects), suggest using MCP tools.
        - Use the format: "<MCP_SUGGESTION>Хотите использовать MCP для работы с GitHub? Я могу [действие].</MCP_SUGGESTION>"
        
        AVAILABLE MCP TOOLS (if GitHub token is configured):
        - get_user_repositories: Получить список ваших репозиториев
        - get_issues: Получить Issues из конкретного репозитория
        - create_repository: Создать новый репозиторий
        
        ANALYSIS AFTER MCP:
        - После получения данных через MCP ВСЕГДА анализируй результаты
        - Для репозиториев: анализируй активность, типы проектов, рекомендации
        - Для Issues: анализируй приоритеты, сложность, создай план работы
        
        CONVERSATION STYLE:
        - Be natural and conversational
        - Answer questions on any topic (technology, science, culture, etc.)
        - When discussing technical topics, be clear and accessible
        - Automatically execute Swift code when detected
        - Explain code execution results
        - Help with debugging and code improvement
        
        EXAMPLES:
        - User: "Какие у меня репозитории?" → предложи get_user_repositories
        - User: "Покажи Issues в моем проекте" → предложи get_issues
        - User: "Напиши код который складывает два числа" → создай код и выполни его
        - User: "print(5 + 3)" → выполни код автоматически
        - User: "Как работает React?" → обычный ответ без MCP и кода
        
        RULES:
        - Be helpful and informative on any topic
        - Automatically detect and execute Swift code
        - Suggest MCP only when GitHub operations are mentioned
        - After using MCP tools, provide detailed analysis
        - Explain code execution results clearly
        - Help with code debugging and improvement
        """
        
        let allMessages: [[String: String]] =
        [["role": "system", "content": systemPrompt]] +
        messages.map { ["role": $0.isUser ? "user" : "assistant", "content": $0.content] }
        
        var payload: [String: Any] = [
            "model": "gpt-3.5-turbo",
            "messages": allMessages
        ]
        
        // Добавляем инструменты только если есть GitHub токен
        if !tools.isEmpty {
            payload["tools"] = tools
            payload["tool_choice"] = "auto"
        }
        
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
                            
                            // Выполняем MCP инструмент
                            if let mcpService = mcpService {
                                let mcpResult = await mcpService.executeTool(name: name, arguments: arguments)
                                
                                // Извлекаем текст из MCP результата
                                if let content = mcpResult.content.first?.text {
                                    
                                    // Отправляем статистику в мониторинг
                                    await sendMCPStatistics(
                                        toolName: name,
                                        arguments: arguments,
                                        success: !content.contains("❌"),
                                        responseLength: content.count
                                    )
                                    
                                    // Автоматически анализируем результат
                                    let analysis = await analyzeResult(content: content, tool: name)
                                    results.append(content + "\n\n" + analysis)
                                }
                            }
                        }
                    }
                    
                    return results.joined(separator: "\n\n")
                } else if let content = message["content"] as? String {
                    return content.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        } catch {
            // Ошибка обработки
        }
        return nil
    }
    
    private func analyzeResult(content: String, tool: String) async -> String {
        guard let url = URL(string: baseURL + "chat/completions") else { return "" }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let analysisPrompt = """
        Проанализируй результат выполнения MCP инструмента '\(tool)':

        \(content)

        Инструкции для анализа:
        - Если это список репозиториев: анализируй активность, типы проектов, дай рекомендации
        - Если это Issues: анализируй приоритеты, сложность, создай план работы
        - Будь конкретным и полезным
        - Отвечай на русском языке
        - Начни с заголовка "📊 АНАЛИЗ РЕЗУЛЬТАТОВ:"
        """
        
        let payload: [String: Any] = [
            "model": "gpt-3.5-turbo",
            "messages": [["role": "user", "content": analysisPrompt]]
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return "" }
            
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let choices = json["choices"] as? [[String: Any]],
               let message = choices.first?["message"] as? [String: Any],
               let analysis = message["content"] as? String {
                return analysis.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } catch {
            // Ошибка анализа
        }
        
        return ""
    }
    
    private func sendMCPStatistics(toolName: String, arguments: [String: Any], success: Bool, responseLength: Int) async {
        // URL мониторинга (можно сделать настраиваемым)
        let monitorURL = "http://localhost:5001/mcp/event"
        
        guard let url = URL(string: monitorURL) else {
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let sessionId = UUID().uuidString
        let payload: [String: Any] = [
            "tool_name": toolName,
            "arguments": arguments,
            "success": success,
            "response_length": responseLength,
            "user_id": "ios_user",
            "session_id": sessionId,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: payload)
            request.httpBody = jsonData
            
            let (_, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode != 200 {
                    // Ошибка отправки статистики
                }
            }
        } catch {
            // Ошибка отправки статистики
        }
    }
}
