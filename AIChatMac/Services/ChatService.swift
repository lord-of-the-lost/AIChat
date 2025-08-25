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
    private let githubToken: String
    private let baseURL = "https://api.proxyapi.ru/openai/v1/"
    
    init(apiKey: String, githubToken: String? = nil) {
        self.apiKey = apiKey
        self.githubToken = githubToken ?? ""
        self.aiAgent = UniversalAIAgent(apiKey: apiKey, githubToken: githubToken)
    }
    
    func sendMessage(_ messages: [ChatMessage]) async -> String? {
        // Проверяем, есть ли GitHub PR URL в последнем сообщении
        if let lastMessage = messages.last,
           lastMessage.isUser,
           let prURL = extractGitHubPRURL(from: lastMessage.content) {
            return await handleGitHubPRReview(prURL: prURL, messages: messages)
        }
        
        return await aiAgent.sendMessage(messages: messages)
    }
    
    // Метод для прямого вызова AI без проверки PR URL
    func sendDirectMessage(_ messages: [ChatMessage]) async -> String? {
        return await aiAgent.sendMessage(messages: messages)
    }
    
    // Метод для обновления AI параметров
    func updateAIParameters(temperature: Double, maxTokens: Int) {
        aiAgent.updateParameters(temperature: temperature, maxTokens: maxTokens)
    }
    
    // Метод для получения текущих AI параметров
    func getCurrentAIParameters() -> (temperature: Double, maxTokens: Int) {
        return aiAgent.getCurrentAIParameters()
    }
    
    private func extractGitHubPRURL(from text: String) -> String? {
        // Ищем GitHub PR URL в тексте
        let pattern = "https://github\\.com/[^/]+/[^/]+/pull/\\d+"
        let regex = try? NSRegularExpression(pattern: pattern)
        
        if let match = regex?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
            let urlRange = Range(match.range, in: text)!
            return String(text[urlRange])
        }
        
        return nil
    }
    
    private func handleGitHubPRReview(prURL: String, messages: [ChatMessage]) async -> String? {
        // Создаем сервисы для ревью
        let githubPRService = GitHubPRService(githubToken: githubToken)
        let codeReviewService = CodeReviewService(aiService: self, githubPRService: githubPRService)
        
        // Выполняем ревью
        let result = await codeReviewService.reviewPullRequest(from: prURL)
        
        switch result {
        case .success(let reviewResult):
            return createReviewResponse(reviewResult: reviewResult)
        case .failure(let error):
            return "❌ Ошибка при ревью PR: \(error.localizedDescription)"
        }
    }
    
    private func createReviewResponse(reviewResult: CodeReviewResult) -> String { // 'CodeReviewResult' is ambiguous for type lookup in this context
        var response = """
        ## 🔍 Ревью Pull Request завершено!
        
        ### 📋 Информация о PR:
        - **Название:** \(reviewResult.pullRequest.title)
        - **Автор:** \(reviewResult.pullRequest.user.login)
        - **Номер:** #\(reviewResult.pullRequest.number)
        - **Ветка:** \(reviewResult.pullRequest.head.ref) → \(reviewResult.pullRequest.base.ref)
        - **Изменения:** +\(reviewResult.pullRequest.additions) -\(reviewResult.pullRequest.deletions) в \(reviewResult.pullRequest.changedFiles) файлах
        
        ### 📊 Результаты ревью:
        - **Общая оценка:** \(reviewResult.review.overallScore)/100
        - **Критических проблем:** \(reviewResult.review.issues.filter { $0.severity == .critical }.count)
        - **Высокого приоритета:** \(reviewResult.review.issues.filter { $0.severity == .high }.count)
        - **Среднего приоритета:** \(reviewResult.review.issues.filter { $0.severity == .medium }.count)
        - **Низкого приоритета:** \(reviewResult.review.issues.filter { $0.severity == .low }.count)
        - **Предложений:** \(reviewResult.review.suggestions.count)
        
        ### 🚨 Созданные Issues:
        """
        
        if reviewResult.createdIssues.isEmpty {
            response += "\n- Проблем не обнаружено, issues не созданы"
        } else {
            for issue in reviewResult.createdIssues {
                response += "\n- [Issue #\(issue.number)](\(issue.htmlUrl)): \(issue.title)"
            }
        }
        
        response += """
        
        ### 💬 Комментарий к PR:
        - \(reviewResult.commentAdded ? "✅ Добавлен" : "❌ Не добавлен")
        
        ### 📝 Краткое резюме:
        \(reviewResult.review.summary)
        
        ---
        *Ревью выполнено автоматически с помощью AI*
        """
        
        return response
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
    
    // AI параметры
    private var temperature: Double = 0.7
    private var maxTokens: Int = 4000
    
    init(apiKey: String, githubToken: String? = nil) {
        self.apiKey = apiKey
        
        if let githubToken = githubToken, !githubToken.isEmpty {
            self.mcpService = MCPGitHubService(githubToken: githubToken)
        } else {
            self.mcpService = nil
        }
    }
    
    func updateParameters(temperature: Double, maxTokens: Int) {
        self.temperature = temperature
        self.maxTokens = maxTokens
    }
    
    func getCurrentAIParameters() -> (temperature: Double, maxTokens: Int) {
        return (temperature: self.temperature, maxTokens: self.maxTokens)
    }
    
    func sendMessage(messages: [ChatMessage]) async -> String? {
        guard let url = URL(string: baseURL + "chat/completions") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60 // 60 секунд таймаут
        
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
        Ты помощник. Отвечай на русском языке.
        
        ВАЖНО: Твоя температура (temperature) = \(String(format: "%.1f", temperature))
        
        При низкой температуре (0.0-0.3): будь максимально кратким и фактологическим
        При средней температуре (0.4-0.7): будь сбалансированным и дружелюбным  
        При высокой температуре (0.8-1.2): будь креативным и эмоциональным
        При очень высокой температуре (1.3+): будь максимально креативным и необычным
        """
        
        // Для тестирования temperature отправляем только последнее сообщение пользователя
        // чтобы контекст не влиял на ответ
        let lastUserMessage = messages.last { $0.isUser }
        let messagesToSend = lastUserMessage != nil ? [lastUserMessage!] : messages.suffix(1)
        
        print("📊 Отправляем \(messagesToSend.count) сообщений для тестирования temperature")
        
        let allMessages: [[String: String]] =
        [["role": "system", "content": systemPrompt]] +
        messagesToSend.map { ["role": $0.isUser ? "user" : "assistant", "content": $0.content] }
        
        var payload: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": allMessages,
            "temperature": temperature,
            "max_tokens": maxTokens,
            "top_p": 1.0,
            "frequency_penalty": 0.0,
            "presence_penalty": 0.0
        ]
        
        print("📤 Отправляем запрос к AI с параметрами: Temperature = \(temperature), MaxTokens = \(maxTokens)")
        
        // Добавляем уникальный идентификатор для избежания кэширования
        payload["user"] = "user_\(UUID().uuidString)"
        
        // Добавляем инструменты только если есть GitHub токен
        if !tools.isEmpty {
            payload["tools"] = tools
            payload["tool_choice"] = "auto"
        }
        
        // Детальное логирование payload
        print("🔍 Детали payload:")
        print("   - Model: \(payload["model"] ?? "НЕ УКАЗАН")")
        print("   - Temperature: \(payload["temperature"] ?? "НЕ УКАЗАН")")
        print("   - MaxTokens: \(payload["max_tokens"] ?? "НЕ УКАЗАН")")
        print("   - Messages count: \((payload["messages"] as? [[String: Any]])?.count ?? 0)")
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: payload, options: .prettyPrinted),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            print("📋 Полный payload JSON:")
            print(jsonString)
        }
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        return await performRequest(request: request)
    }
    
    private func performRequest(request: URLRequest) async -> String? {
        do {
            print("🌐 Отправляем HTTP запрос к AI API...")
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let http = response as? HTTPURLResponse else {
                print("❌ Неверный тип ответа от сервера")
                return nil
            }
            
            print("📡 HTTP статус: \(http.statusCode)")
            
            guard http.statusCode == 200 else {
                print("❌ HTTP ошибка: \(http.statusCode)")
                if let errorData = String(data: data, encoding: .utf8) {
                    print("📄 Ответ сервера: \(errorData)")
                }
                return nil
            }
            
            print("📄 Получен ответ от AI API (\(data.count) байт)")
            
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                print("❌ Не удалось распарсить JSON ответ")
                return nil
            }
            
            print("🔍 JSON ключи: \(json.keys.joined(separator: ", "))")
            
            guard let choices = json["choices"] as? [[String: Any]] else {
                print("❌ Нет ключа 'choices' в ответе")
                return nil
            }
            
            print("📋 Количество choices: \(choices.count)")
            
            guard let message = choices.first?["message"] as? [String: Any] else {
                print("❌ Нет ключа 'message' в первом choice")
                return nil
            }
                
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
                    print("📝 Получен контент от AI (\(content.count) символов)")
                    let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    print("✂️ Обрезанный контент (\(trimmedContent.count) символов)")
                    
                    // Проверяем на AI галлюцинации
                    if isAIGeneratedGarbage(trimmedContent) {
                        print("⚠️ Обнаружены AI галлюцинации")
                        return "❌ AI вернул некорректный ответ. Попробуйте уменьшить температуру (0.0-1.0) или повторить запрос."
                    }
                    
                    // Проверяем только на галлюцинации, не обрезаем контент
                    print("📊 Размер ответа: \(trimmedContent.count) символов (лимит: \(maxTokens * 4))")
                    
                    print("✅ Контент прошел валидацию")
                    return trimmedContent
                } else {
                    print("❌ Нет контента в сообщении")
                    print("🔍 Ключи сообщения: \(message.keys.joined(separator: ", "))")
                }
        } catch {
            print("❌ Ошибка при обработке запроса: \(error)")
            print("🔍 Тип ошибки: \(type(of: error))")
        }
        print("❌ Не удалось получить ответ от AI")
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
            "messages": [["role": "user", "content": analysisPrompt]],
            "temperature": temperature,
            "max_tokens": maxTokens
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
    
    private func isAIGeneratedGarbage(_ text: String) -> Bool {
        // Проверяем на наличие бессмысленных символов
        let garbagePatterns = [
            "\\b[A-Za-z0-9_]+\\.[A-Za-z0-9_]+\\.[A-Za-z0-9_]+\\b", // Много точек
            "\\b[A-Za-z0-9_]+_[A-Za-z0-9_]+_[A-Za-z0-9_]+\\b", // Много подчеркиваний
            "[\\u4e00-\\u9fff]", // Китайские символы
            "[\\u3040-\\u309f]", // Хирагана
            "[\\u30a0-\\u30ff]", // Катакана
            "[\\uac00-\\ud7af]", // Корейские символы
        ]
        
        for pattern in garbagePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil {
                print("🚨 Обнаружен паттерн галлюцинаций: \(pattern)")
                return true
            }
        }
        
        // Проверяем на повторяющиеся символы
        let repeatedChars = ["@@@@", "####", "$$$$", "%%%%", "^^^^", "&&&&", "****"]
        for chars in repeatedChars {
            if text.contains(chars) {
                print("🚨 Обнаружены повторяющиеся символы: \(chars)")
                return true
            }
        }
        
        // Проверяем на слишком много специальных символов
        let specialCharCount = text.filter { "!@#$%^&*()_+-=[]{}|;':\",./<>?~`".contains($0) }.count
        let totalCharCount = text.count
        if totalCharCount > 0 && Double(specialCharCount) / Double(totalCharCount) > 0.3 {
            print("🚨 Слишком много специальных символов: \(specialCharCount)/\(totalCharCount)")
            return true
        }
        
        // Проверяем на слишком длинные ответы при высокой температуре
        if text.count > 10000 {
            print("🚨 Слишком длинный ответ: \(text.count) символов")
            return true
        }
        
        return false
    }
}
