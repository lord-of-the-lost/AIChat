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
    
    init(apiKey: String, githubToken: String? = nil, notionToken: String? = nil) {
        self.apiKey = apiKey
        self.aiAgent = UniversalAIAgent(apiKey: apiKey, githubToken: githubToken, notionToken: notionToken)
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
    private let mcpGitHubService: MCPGitHubService?
    private let mcpNotionService: MCPNotionService?
    
    init(apiKey: String, githubToken: String? = nil, notionToken: String? = nil) {
        self.apiKey = apiKey
        
        if let githubToken = githubToken, !githubToken.isEmpty {
            self.mcpGitHubService = MCPGitHubService(githubToken: githubToken)
        } else {
            self.mcpGitHubService = nil
        }
        
        if let notionToken = notionToken, !notionToken.isEmpty {
            self.mcpNotionService = MCPNotionService(notionToken: notionToken)
        } else {
            self.mcpNotionService = nil
        }
    }
    
    func sendMessage(messages: [ChatMessage]) async -> String? {
        print("🚀 НАЧАЛО ОБРАБОТКИ СООБЩЕНИЯ:")
        print("Количество сообщений в истории: \(messages.count)")
        if let lastMessage = messages.last {
            print("Последнее сообщение от \(lastMessage.author.rawValue): \(lastMessage.content.prefix(100))...")
        }
        
        guard let url = URL(string: baseURL + "chat/completions") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Определяем доступные MCP инструменты
        var tools: [[String: Any]] = []
        
        if mcpGitHubService != nil {
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
                ],
                [
                    "type": "function",
                    "function": [
                        "name": "create_issue",
                        "description": "Создает новый Issue в GitHub репозитории",
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
                                "title": [
                                    "type": "string",
                                    "description": "Название Issue"
                                ],
                                "body": [
                                    "type": "string",
                                    "description": "Описание Issue"
                                ],
                                "labels": [
                                    "type": "array",
                                    "items": ["type": "string"],
                                    "description": "Массив меток для Issue"
                                ]
                            ],
                            "required": ["owner", "repo", "title"]
                        ]
                    ]
                ]
            ]
        }
        
        if mcpNotionService != nil {
            let notionTools: [[String: Any]] = [
                [
                    "type": "function",
                    "function": [
                        "name": "search_notion_pages",
                        "description": "Ищет страницы в Notion по текстовому запросу",
                        "parameters": [
                            "type": "object",
                            "properties": [
                                "query": [
                                    "type": "string",
                                    "description": "Поисковый запрос"
                                ],
                                "pageSize": [
                                    "type": "integer",
                                    "description": "Количество результатов (по умолчанию 10)"
                                ]
                            ],
                            "required": ["query"]
                        ]
                    ]
                ],
                [
                    "type": "function",
                    "function": [
                        "name": "get_notion_page",
                        "description": "Получает информацию о странице Notion по ID",
                        "parameters": [
                            "type": "object",
                            "properties": [
                                "pageId": [
                                    "type": "string",
                                    "description": "ID страницы Notion"
                                ]
                            ],
                            "required": ["pageId"]
                        ]
                    ]
                ],
                [
                    "type": "function",
                    "function": [
                        "name": "get_notion_page_content",
                        "description": "Получает полное содержимое страницы Notion включая все блоки",
                        "parameters": [
                            "type": "object",
                            "properties": [
                                "pageId": [
                                    "type": "string",
                                    "description": "ID страницы Notion"
                                ]
                            ],
                            "required": ["pageId"]
                        ]
                    ]
                ],
                [
                    "type": "function",
                    "function": [
                        "name": "create_github_issue_from_notion",
                        "description": "Создает GitHub Issue на основе содержимого страницы Notion",
                        "parameters": [
                            "type": "object",
                            "properties": [
                                "pageId": [
                                    "type": "string",
                                    "description": "ID страницы Notion"
                                ],
                                "owner": [
                                    "type": "string",
                                    "description": "Владелец GitHub репозитория"
                                ],
                                "repo": [
                                    "type": "string",
                                    "description": "Название GitHub репозитория"
                                ],
                                "title": [
                                    "type": "string",
                                    "description": "Название Issue (опционально, по умолчанию использует название страницы)"
                                ]
                            ],
                            "required": ["pageId", "owner", "repo"]
                        ]
                    ]
                ],
                [
                    "type": "function",
                    "function": [
                        "name": "create_multiple_github_issues_from_notion",
                        "description": "Создает отдельные GitHub Issues для каждой задачи из списков в Notion странице",
                        "parameters": [
                            "type": "object",
                            "properties": [
                                "pageId": [
                                    "type": "string",
                                    "description": "ID страницы Notion"
                                ],
                                "owner": [
                                    "type": "string",
                                    "description": "Владелец GitHub репозитория"
                                ],
                                "repo": [
                                    "type": "string",
                                    "description": "Название GitHub репозитория"
                                ]
                            ],
                            "required": ["pageId", "owner", "repo"]
                        ]
                    ]
                ],
                [
                    "type": "function",
                    "function": [
                        "name": "get_database_pages",
                        "description": "Получает все записи из базы данных Notion",
                        "parameters": [
                            "type": "object",
                            "properties": [
                                "databaseId": [
                                    "type": "string",
                                    "description": "ID базы данных Notion"
                                ],
                                "pageSize": [
                                    "type": "integer",
                                    "description": "Количество записей для получения (по умолчанию 100)"
                                ]
                            ],
                            "required": ["databaseId"]
                        ]
                    ]
                ]
            ]
            tools.append(contentsOf: notionTools)
        }
        
        let systemPrompt = """
        ROLE: Universal AI Assistant with GitHub and Notion MCP Integration
        PURPOSE: Be a helpful conversational AI that can work with GitHub and Notion via MCP tools when needed.

        LANGUAGE RULES:
        - All communication MUST be in Russian.
        - Be friendly, helpful, and conversational.
        - Provide informative and engaging responses on any topic.

        MCP INTEGRATION:
        - When user mentions GitHub-related topics (repositories, issues, projects), suggest using GitHub MCP tools.
        - When user mentions Notion-related topics (pages, projects, notes), suggest using Notion MCP tools.
        - When user wants to transfer data from Notion to GitHub, use both MCP services together.
        
        SMART TOOL CHAINING RULES:
        - При запросе "создай GitHub Issues из Notion [название]" выполни ПОЛНУЮ цепочку:
          1. search_notion_pages с названием проекта
          2. Для каждой найденной страницы: get_notion_page_content 
          3. ВАЖНО: Если страница содержит списки задач - используй create_multiple_github_issues_from_notion
          4. Если страница содержит общий текст - используй create_github_issue_from_notion
        - create_multiple_github_issues_from_notion создает ОТДЕЛЬНОЕ Issue для каждого пункта списка
        - create_github_issue_from_notion создает ОДНО Issue из всего содержимого
        - НЕ останавливайся после первого инструмента - продолжай автоматически
        - Если пользователь указал репозиторий в формате owner/repo - используй эти данные для создания Issues
        
        AVAILABLE GITHUB MCP TOOLS:
        - get_user_repositories: Получить список ваших репозиториев
        - get_issues: Получить Issues из конкретного репозитория
        - create_repository: Создать новый репозиторий
        - create_issue: Создать новый Issue в репозитории
        
        AVAILABLE NOTION MCP TOOLS:
        - search_notion_pages: Найти страницы в Notion по запросу
        - get_notion_page: Получить информацию о странице
        - get_notion_page_content: Получить полное содержимое страницы
        - get_database_pages: Получить все записи из базы данных Notion
        - create_github_issue_from_notion: Создать одно GitHub Issue из всей страницы Notion
        - create_multiple_github_issues_from_notion: Создать отдельные GitHub Issues для каждой задачи из списков
        
        WORKFLOW FOR NOTION TO GITHUB TRANSFER:
        1. Поиск страницы в Notion (search_notion_pages)
        2. Получение полного содержимого (get_notion_page_content)
        3. Создание GitHub Issue (create_github_issue_from_notion)
        
        AUTOMATIC CHAIN EXECUTION:
        - При запросе "создай GitHub Issues из Notion" ВСЕГДА выполняй полную цепочку:
          1. search_notion_pages для поиска
          2. get_notion_page_content для каждой найденной страницы
          3. create_github_issue_from_notion для создания Issues
        - НЕ останавливайся после поиска, продолжай автоматически
        - Если пользователь просит создать Issues из Notion - это означает выполнить ВСЮ цепочку
        
        ANALYSIS AFTER MCP:
        - После получения данных через MCP ВСЕГДА анализируй результаты
        - Для репозиториев: анализируй активность, типы проектов, рекомендации
        - Для Issues: анализируй приоритеты, сложность, создай план работы
        - Для страниц Notion: анализируй содержимое, структуру, возможности переноса
        
        CONVERSATION STYLE:
        - Be natural and conversational
        - Answer questions on any topic (technology, science, culture, etc.)
        - When discussing technical topics, be clear and accessible
        - Suggest MCP when relevant operations are mentioned
        - Keep responses natural and engaging
        
        EXAMPLES:
        - User: "Найди в Notion страницу проекта X" → search_notion_pages
        - User: "Создай отдельные GitHub Issues из списка в Notion" → search_notion_pages + create_multiple_github_issues_from_notion
        - User: "Создай GitHub Issues из Notion проекта X" → search_notion_pages + get_notion_page_content + create_multiple_github_issues_from_notion (если есть списки)
        - User: "Перенеси страницу Notion в GitHub Issues" → get_notion_page_content + create_github_issue_from_notion (одно Issue)
        - User: "Какие у меня репозитории?" → get_user_repositories
        - User: "Как работает React?" → обычный ответ без MCP
        
        CONTEXT-AWARE EXAMPLES:
        - Turn 1: User: "Найди в Notion страницу ios-app" → search_notion_pages, получи pageId: "2537a253-1e5b-8049-a039-d54134dde19f"
        - Turn 2: User: "Создай GitHub Issues из содержимого в репозиторий X/Y" → НЕ ищи заново! Используй известный pageId с create_multiple_github_issues_from_notion
        - Turn 3: User: "Создай Issues из найденной страницы" → используй pageId из Turn 1
        
        ПРИМЕР ПРАВИЛЬНОЙ ПАМЯТИ:
        История содержит: "🆔 ID: 2537a253-1e5b-8049-a039-d54134dde19f"
        → При запросе "создай Issues" используй этот ID напрямую, НЕ ищи заново
        
        CRITICAL INSTRUCTION FOR NOTION-TO-GITHUB TRANSFER:
        Когда пользователь просит "создать GitHub Issues из Notion", выполни ЭТУ ПОСЛЕДОВАТЕЛЬНОСТЬ:
        1. Используй search_notion_pages для поиска
        2. После получения результатов - ОБЯЗАТЕЛЬНО используй get_notion_page_content для каждой найденной страницы
        3. После получения содержимого - ОБЯЗАТЕЛЬНО используй create_github_issue_from_notion
        НЕ ОСТАНАВЛИВАЙСЯ после поиска! Продолжай цепочку автоматически!
        
        CONTEXT AWARENESS:
        - **КРИТИЧЕСКИ ВАЖНО**: Всегда проверяй историю диалога на наличие ранее найденных Notion pageId
        - Если пользователь упоминает "содержимое", "из содержимого", "из найденной страницы" - ищи в истории диалога последние найденные Notion страницы  
        - **НИКОГДА НЕ ПОВТОРЯЙ search_notion_pages** если pageId уже известен из истории диалога
        - Когда видишь в предыдущих сообщениях "🆔 ID: [pageId]" - извлекай этот pageId и используй напрямую
        - При запросе создания GitHub Issues после поиска Notion - используй ранее найденный pageId с create_multiple_github_issues_from_notion
        - **ПРАВИЛО ПАМЯТИ**: Одна страница найдена = используй её ID, не ищи заново
        
        RULES:
        - Be helpful and informative on any topic
        - Execute complete tool chains when user requests Notion-to-GitHub transfer
        - After using MCP tools, provide detailed analysis
        - Don't force integrations when not relevant
        - When transferring from Notion to GitHub, extract and format content appropriately
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
        // Логируем запрос к OpenAI
        if let httpBody = request.httpBody,
           let requestString = String(data: httpBody, encoding: .utf8) {
            print("🤖 ЗАПРОС К OPENAI API:")
            print(String(repeating: "=", count: 50))
            
            // Парсим JSON для красивого вывода
            if let requestJson = try? JSONSerialization.jsonObject(with: httpBody) as? [String: Any] {
                if let messages = requestJson["messages"] as? [[String: Any]] {
                    print("📝 Сообщения в диалоге:")
                    for (index, message) in messages.enumerated() {
                        let role = message["role"] as? String ?? "unknown"
                        let content = message["content"] as? String ?? ""
                        print("[\(index)] \(role.uppercased()):")
                        print(content.prefix(200))
                        if content.count > 200 {
                            print("... (обрезано)")
                        }
                        print("---")
                    }
                }
                
                if let tools = requestJson["tools"] as? [[String: Any]] {
                    print("🔧 Доступные инструменты:")
                    for tool in tools {
                        if let function = tool["function"] as? [String: Any],
                           let name = function["name"] as? String {
                            print("- \(name)")
                        }
                    }
                }
            }
            print(String(repeating: "=", count: 50))
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return nil 
            }
            
            // Логируем ответ от OpenAI
            if let responseString = String(data: data, encoding: .utf8) {
                print("🤖 ОТВЕТ ОТ OPENAI API:")
                
                if let responseJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if let choices = responseJson["choices"] as? [[String: Any]],
                       let message = choices.first?["message"] as? [String: Any] {
                        
                        if let content = message["content"] as? String {
                            print("💬 Текстовый ответ:")
                            print(content.prefix(300))
                            if content.count > 300 {
                                print("... (обрезано)")
                            }
                        }
                        
                        if let toolCalls = message["tool_calls"] as? [[String: Any]] {
                            print("🔧 Запрошенные инструменты:")
                            for (index, toolCall) in toolCalls.enumerated() {
                                if let function = toolCall["function"] as? [String: Any],
                                   let name = function["name"] as? String,
                                   let argumentsString = function["arguments"] as? String {
                                    print("[\(index + 1)] \(name)")
                                    print("Аргументы: \(argumentsString)")
                                }
                            }
                        }
                    }
                }
                print(String(repeating: "=", count: 50))
            }
            
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
                            
                            print("🔧 AI Agent: Вызываем MCP инструмент '\(name)' с аргументами: \(arguments)")
                            
                            // Определяем какой MCP сервис использовать
                            var mcpResult: MCPResult?
                            
                            if isGitHubTool(name) && mcpGitHubService != nil {
                                mcpResult = await mcpGitHubService!.executeTool(name: name, arguments: arguments)
                            } else if isNotionTool(name) && mcpNotionService != nil {
                                mcpResult = await mcpNotionService!.executeTool(name: name, arguments: arguments)
                            }
                            
                            // Обрабатываем результат
                            if let result = mcpResult,
                               let content = result.content.first?.text {
                                print("🔧 AI Agent: Получен результат MCP: \(content)")
                                
                                // Проверяем, есть ли toolCalls для цепочки вызовов
                                if let toolCalls = result.content.first?.toolCalls, !toolCalls.isEmpty {
                                    // Выполняем цепочку вызовов (например, create_github_issue_from_notion → create_issue)
                                    for toolCall in toolCalls {
                                        if isGitHubTool(toolCall.name) && mcpGitHubService != nil {
                                            let chainResult = await mcpGitHubService!.executeTool(name: toolCall.name, arguments: toolCall.arguments)
                                            if let chainContent = chainResult.content.first?.text {
                                                results.append(content + "\n\n" + chainContent)
                                                // Анализируем только конечный результат
                                                let analysis = await analyzeResult(content: chainContent, tool: toolCall.name)
                                                results.append(analysis)
                                            }
                                        }
                                    }
                                } else {
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
            print("❌ Universal AI Agent Error:", error)
        }
        return nil
    }
    
    private func analyzeResult(content: String, tool: String) async -> String {
        print("📊 ЗАПРОС АНАЛИЗА РЕЗУЛЬТАТОВ:")
        print("Инструмент: \(tool)")
        print("Содержимое: \(content.prefix(200))...")
        
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
        - Если это поиск Notion страниц: проанализируй найденные страницы и предложи следующие шаги
        - Если это содержимое Notion: проанализируй структуру и возможности для создания Issues
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
            print("❌ Analysis Error:", error)
        }
        
        return ""
    }
    
    private func isGitHubTool(_ name: String) -> Bool {
        return ["get_user_repositories", "get_issues", "create_repository", "create_issue"].contains(name)
    }
    
    private func isNotionTool(_ name: String) -> Bool {
        return ["search_notion_pages", "get_notion_page", "get_notion_page_content", "create_github_issue_from_notion", "create_multiple_github_issues_from_notion", "get_database_pages"].contains(name)
    }
}
