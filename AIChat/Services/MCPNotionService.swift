//
//  MCPNotionService.swift
//  AIChat
//
//  Created by Николай Игнатов on 13.08.2025.
//

import Foundation

// MARK: - Notion MCP Client

final class MCPNotionService {
    private let notionToken: String
    private let baseURL = "https://api.notion.com/v1"
    private let notionVersion = "2022-06-28"
    
    init(notionToken: String) {
        self.notionToken = notionToken
    }
    
    // MARK: - MCP Tool Implementations
    
    func searchPages(query: String, pageSize: Int = 10) async -> Result<NotionSearchResponse, Error> {
        guard let url = URL(string: "\(baseURL)/search") else {
            return .failure(NotionMCPError.invalidURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(notionToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(notionVersion, forHTTPHeaderField: "Notion-Version")
        
        let searchRequest = NotionSearchRequest(
            query: query,
            filter: NotionSearchFilter(value: "page", property: "object"),
            pageSize: pageSize
        )
        
        do {
            let jsonData = try JSONEncoder().encode(searchRequest)
            request.httpBody = jsonData
            
            print("🔍 Отправляем запрос поиска в Notion:")
            print("URL: \(url)")
            print("Запрос: \(query)")
            print("Размер страницы: \(pageSize)")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("❌ Неверный HTTP ответ")
                return .failure(NotionMCPError.invalidResponse)
            }
            
            print("📡 HTTP статус: \(httpResponse.statusCode)")
            
            if let responseString = String(data: data, encoding: .utf8) {
                print("📄 Ответ от Notion: \(responseString)")
            }
            
            if httpResponse.statusCode == 200 {
                // Добавляем отладочную информацию
                if let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    print("🔍 Структура ответа от Notion API:")
                    print(jsonObject)
                }
                
                let searchResponse = try JSONDecoder().decode(NotionSearchResponse.self, from: data)
                print("✅ Найдено страниц: \(searchResponse.results.count)")
                return .success(searchResponse)
            } else {
                if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let message = errorData["message"] as? String {
                    print("❌ Notion API ошибка: \(message)")
                    return .failure(NotionMCPError.apiError(message))
                } else {
                    print("❌ HTTP ошибка: \(httpResponse.statusCode)")
                    return .failure(NotionMCPError.httpError(httpResponse.statusCode))
                }
            }
        } catch {
            print("❌ Ошибка при поиске страниц: \(error)")
            return .failure(error)
        }
    }
    
    func getPageContent(pageId: String) async -> Result<NotionPage, Error> {
        guard let url = URL(string: "\(baseURL)/pages/\(pageId)") else {
            return .failure(NotionMCPError.invalidURL)
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(notionToken)", forHTTPHeaderField: "Authorization")
        request.setValue(notionVersion, forHTTPHeaderField: "Notion-Version")
        
        print("🔍 Получаем содержимое страницы Notion: \(pageId)")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure(NotionMCPError.invalidResponse)
            }
            
            print("📡 HTTP статус: \(httpResponse.statusCode)")
            
            if httpResponse.statusCode == 200 {
                let page = try JSONDecoder().decode(NotionPage.self, from: data)
                print("✅ Страница получена: \(page.id)")
                return .success(page)
            } else {
                if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let message = errorData["message"] as? String {
                    print("❌ Notion API ошибка: \(message)")
                    return .failure(NotionMCPError.apiError(message))
                } else {
                    print("❌ HTTP ошибка: \(httpResponse.statusCode)")
                    return .failure(NotionMCPError.httpError(httpResponse.statusCode))
                }
            }
        } catch {
            print("❌ Ошибка при получении страницы: \(error)")
            return .failure(error)
        }
    }
    
    func getPageBlocks(pageId: String, pageSize: Int = 100) async -> Result<NotionBlocksResponse, Error> {
        guard let url = URL(string: "\(baseURL)/blocks/\(pageId)/children") else {
            return .failure(NotionMCPError.invalidURL)
        }
        
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "page_size", value: "\(pageSize)")
        ]
        
        guard let finalURL = components.url else {
            return .failure(NotionMCPError.invalidURL)
        }
        
        var request = URLRequest(url: finalURL)
        request.setValue("Bearer \(notionToken)", forHTTPHeaderField: "Authorization")
        request.setValue(notionVersion, forHTTPHeaderField: "Notion-Version")
        
        print("🔍 Получаем блоки страницы Notion: \(pageId)")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure(NotionMCPError.invalidResponse)
            }
            
            print("📡 HTTP статус: \(httpResponse.statusCode)")
            
            if httpResponse.statusCode == 200 {
                let blocksResponse = try JSONDecoder().decode(NotionBlocksResponse.self, from: data)
                print("✅ Получено блоков: \(blocksResponse.results.count)")
                return .success(blocksResponse)
            } else {
                if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let message = errorData["message"] as? String {
                    print("❌ Notion API ошибка: \(message)")
                    return .failure(NotionMCPError.apiError(message))
                } else {
                    print("❌ HTTP ошибка: \(httpResponse.statusCode)")
                    return .failure(NotionMCPError.httpError(httpResponse.statusCode))
                }
            }
        } catch {
            print("❌ Ошибка при получении блоков: \(error)")
            return .failure(error)
        }
    }
    
    // MARK: - MCP Tool Execution
    
    func executeTool(name: String, arguments: [String: Any]) async -> MCPResult {
        print("🔧 Notion MCP Service: Выполняем инструмент '\(name)' с аргументами: \(arguments)")
        
        switch name {
        case "search_notion_pages":
            print("🔧 Notion MCP Service: Ищем страницы...")
            return await handleSearchPages(arguments)
        case "get_notion_page":
            print("🔧 Notion MCP Service: Получаем страницу...")
            return await handleGetPage(arguments)
        case "get_notion_page_content":
            print("🔧 Notion MCP Service: Получаем содержимое страницы...")
            return await handleGetPageContent(arguments)
        case "create_github_issue_from_notion":
            print("🔧 Notion MCP Service: Создаем GitHub Issue из Notion...")
            return await handleCreateGitHubIssueFromNotion(arguments)
        case "create_multiple_github_issues_from_notion":
            print("🔧 Notion MCP Service: Создаем множественные GitHub Issues из Notion...")
            return await handleCreateMultipleGitHubIssuesFromNotion(arguments)
        case "get_database_pages":
            print("🔧 Notion MCP Service: Получаем страницы из базы данных...")
            return await handleGetDatabasePages(arguments)
        default:
            print("❌ Notion MCP Service: Неизвестный инструмент: \(name)")
            return MCPResult(content: [
                MCPContent(
                    type: "text",
                    text: "❌ Неизвестный инструмент: \(name). Доступные инструменты: search_notion_pages, get_notion_page, get_notion_page_content, create_github_issue_from_notion, create_multiple_github_issues_from_notion, get_database_pages",
                    toolCalls: nil
                )
            ])
        }
    }
    
    private func handleSearchPages(_ arguments: [String: Any]) async -> MCPResult {
        guard let query = arguments["query"] as? String else {
            return MCPResult(content: [
                MCPContent(
                    type: "text",
                    text: "❌ Ошибка: не указан поисковый запрос",
                    toolCalls: nil
                )
            ])
        }
        
        let pageSize = arguments["pageSize"] as? Int ?? 10
        
        let result = await searchPages(query: query, pageSize: pageSize)
        
        switch result {
        case .success(let searchResponse):
            if searchResponse.results.isEmpty {
                return MCPResult(content: [
                    MCPContent(
                        type: "text",
                        text: """
                        🔍 Поиск в Notion:
                        
                        По запросу "\(query)" ничего не найдено.
                        """,
                        toolCalls: nil
                    )
                ])
            }
            
            let pagesList = searchResponse.results.map { page in
                let title = extractPageTitle(from: page.properties)
                return """
                📄 \(title)
                🆔 ID: \(page.id)
                🔗 URL: \(page.url)
                📅 Создано: \(page.createdTime)
                📝 Обновлено: \(page.lastEditedTime)
                """
            }.joined(separator: "\n\n")
            
            return MCPResult(content: [
                MCPContent(
                    type: "text",
                    text: """
                    🔍 Результаты поиска в Notion по запросу "\(query)":
                    
                    Найдено страниц: \(searchResponse.results.count)
                    
                    \(pagesList)
                    """,
                    toolCalls: nil
                )
            ])
            
        case .failure(let error):
            return MCPResult(content: [
                MCPContent(
                    type: "text",
                    text: "❌ Ошибка при поиске в Notion: \(error.localizedDescription)",
                    toolCalls: nil
                )
            ])
        }
    }
    
    private func handleGetPage(_ arguments: [String: Any]) async -> MCPResult {
        guard let pageId = arguments["pageId"] as? String else {
            return MCPResult(content: [
                MCPContent(
                    type: "text",
                    text: "❌ Ошибка: не указан ID страницы",
                    toolCalls: nil
                )
            ])
        }
        
        let result = await getPageContent(pageId: pageId)
        
        switch result {
        case .success(let page):
            let title = extractPageTitle(from: page.properties)
            
            return MCPResult(content: [
                MCPContent(
                    type: "text",
                    text: """
                    📄 Страница Notion:
                    
                    📋 Название: \(title)
                    🆔 ID: \(page.id)
                    🔗 URL: \(page.url)
                    📅 Создано: \(page.createdTime)
                    📝 Обновлено: \(page.lastEditedTime)
                    """,
                    toolCalls: nil
                )
            ])
            
        case .failure(let error):
            return MCPResult(content: [
                MCPContent(
                    type: "text",
                    text: "❌ Ошибка при получении страницы: \(error.localizedDescription)",
                    toolCalls: nil
                )
            ])
        }
    }
    
    private func handleGetPageContent(_ arguments: [String: Any]) async -> MCPResult {
        guard let pageId = arguments["pageId"] as? String else {
            return MCPResult(content: [
                MCPContent(
                    type: "text",
                    text: "❌ Ошибка: не указан ID страницы",
                    toolCalls: nil
                )
            ])
        }
        
        // Получаем информацию о странице
        let pageResult = await getPageContent(pageId: pageId)
        guard case .success(let page) = pageResult else {
            return MCPResult(content: [
                MCPContent(
                    type: "text",
                    text: "❌ Ошибка при получении страницы: \(pageResult)",
                    toolCalls: nil
                )
            ])
        }
        
        // Получаем блоки (содержимое) страницы
        let blocksResult = await getPageBlocks(pageId: pageId)
        guard case .success(let blocksResponse) = blocksResult else {
            return MCPResult(content: [
                MCPContent(
                    type: "text",
                    text: "❌ Ошибка при получении содержимого страницы: \(blocksResult)",
                    toolCalls: nil
                )
            ])
        }
        
        let title = extractPageTitle(from: page.properties)
        let content = extractBlocksContent(from: blocksResponse.results)
        
        return MCPResult(content: [
            MCPContent(
                type: "text",
                text: """
                📄 Полное содержимое страницы Notion:
                
                📋 Название: \(title)
                🆔 ID: \(page.id)
                🔗 URL: \(page.url)
                📅 Создано: \(page.createdTime)
                📝 Обновлено: \(page.lastEditedTime)
                
                📄 СОДЕРЖИМОЕ:
                \(content)
                """,
                toolCalls: nil
            )
        ])
    }
    
    private func handleCreateGitHubIssueFromNotion(_ arguments: [String: Any]) async -> MCPResult {
        guard let pageId = arguments["pageId"] as? String else {
            return MCPResult(content: [
                MCPContent(
                    type: "text",
                    text: "❌ Ошибка: не указан ID страницы Notion",
                    toolCalls: nil
                )
            ])
        }
        
        guard let owner = arguments["owner"] as? String else {
            return MCPResult(content: [
                MCPContent(
                    type: "text",
                    text: "❌ Ошибка: не указан owner репозитория GitHub",
                    toolCalls: nil
                )
            ])
        }
        
        guard let repo = arguments["repo"] as? String else {
            return MCPResult(content: [
                MCPContent(
                    type: "text",
                    text: "❌ Ошибка: не указан repo репозитория GitHub",
                    toolCalls: nil
                )
            ])
        }
        
        // Получаем полное содержимое страницы Notion
        let pageResult = await getPageContent(pageId: pageId)
        guard case .success(let page) = pageResult else {
            return MCPResult(content: [
                MCPContent(
                    type: "text",
                    text: "❌ Ошибка при получении страницы Notion",
                    toolCalls: nil
                )
            ])
        }
        
        let blocksResult = await getPageBlocks(pageId: pageId)
        guard case .success(let blocksResponse) = blocksResult else {
            return MCPResult(content: [
                MCPContent(
                    type: "text",
                    text: "❌ Ошибка при получении содержимого страницы Notion",
                    toolCalls: nil
                )
            ])
        }
        
        let title = extractPageTitle(from: page.properties)
        let content = extractBlocksContent(from: blocksResponse.results)
        
        // Формируем данные для создания GitHub Issue
        let issueTitle = arguments["title"] as? String ?? title
        let issueBody = """
        **Источник:** [Страница Notion](\(page.url))
        **ID Notion:** \(pageId)
        **Создано:** \(page.createdTime)
        **Обновлено:** \(page.lastEditedTime)
        
        ---
        
        \(content)
        """
        
        return MCPResult(content: [
            MCPContent(
                type: "text",
                text: """
                📋 Подготовлены данные для создания GitHub Issue из Notion:
                
                📄 Источник: Notion страница "\(title)"
                🏷️ Название Issue: \(issueTitle)
                📁 Репозиторий: \(owner)/\(repo)
                
                📝 Содержимое Issue подготовлено с ссылкой на оригинальную страницу Notion.
                """,
                toolCalls: [
                    MCPToolCall(
                        name: "create_issue",
                        arguments: [
                            "title": issueTitle,
                            "body": issueBody,
                            "owner": owner,
                            "repo": repo
                        ]
                    )
                ]
            )
        ])
    }
    
    func getDatabasePages(databaseId: String, pageSize: Int = 100) async -> Result<NotionDatabaseQueryResponse, Error> {
        guard let url = URL(string: "\(baseURL)/databases/\(databaseId)/query") else {
            return .failure(NotionMCPError.invalidURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(notionToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(notionVersion, forHTTPHeaderField: "Notion-Version")
        
        let queryRequest = NotionDatabaseQueryRequest(pageSize: pageSize)
        
        do {
            let jsonData = try JSONEncoder().encode(queryRequest)
            request.httpBody = jsonData
            
            print("🔍 Отправляем запрос к базе данных Notion:")
            print("URL: \(url)")
            print("Database ID: \(databaseId)")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("❌ Неверный HTTP ответ")
                return .failure(NotionMCPError.invalidResponse)
            }
            
            print("📡 HTTP статус: \(httpResponse.statusCode)")
            
            if let responseString = String(data: data, encoding: .utf8) {
                print("📄 Ответ от Notion: \(responseString)")
            }
            
            if httpResponse.statusCode == 200 {
                let databaseResponse = try JSONDecoder().decode(NotionDatabaseQueryResponse.self, from: data)
                print("✅ Получено записей из базы: \(databaseResponse.results.count)")
                return .success(databaseResponse)
            } else {
                if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let message = errorData["message"] as? String {
                    print("❌ Notion API ошибка: \(message)")
                    return .failure(NotionMCPError.apiError(message))
                } else {
                    print("❌ HTTP ошибка: \(httpResponse.statusCode)")
                    return .failure(NotionMCPError.httpError(httpResponse.statusCode))
                }
            }
        } catch {
            print("❌ Ошибка при запросе к базе данных: \(error)")
            return .failure(error)
        }
    }
    
    private func handleGetDatabasePages(_ arguments: [String: Any]) async -> MCPResult {
        guard let databaseId = arguments["databaseId"] as? String else {
            return MCPResult(content: [
                MCPContent(
                    type: "text",
                    text: "❌ Ошибка: не указан ID базы данных",
                    toolCalls: nil
                )
            ])
        }
        
        let pageSize = arguments["pageSize"] as? Int ?? 100
        
        let result = await getDatabasePages(databaseId: databaseId, pageSize: pageSize)
        
        switch result {
        case .success(let databaseResponse):
            if databaseResponse.results.isEmpty {
                return MCPResult(content: [
                    MCPContent(
                        type: "text",
                        text: """
                        📊 База данных Notion:
                        
                        База данных пуста или не содержит доступных записей.
                        """,
                        toolCalls: nil
                    )
                ])
            }
            
            let pagesList = databaseResponse.results.map { page in
                let title = extractPageTitle(from: page.properties)
                return """
                📄 \(title)
                🆔 ID: \(page.id)
                🔗 URL: \(page.url)
                📅 Создано: \(page.createdTime)
                📝 Обновлено: \(page.lastEditedTime)
                """
            }.joined(separator: "\n\n")
            
            return MCPResult(content: [
                MCPContent(
                    type: "text",
                    text: """
                    📊 Записи из базы данных Notion:
                    
                    Найдено записей: \(databaseResponse.results.count)
                    
                    \(pagesList)
                    """,
                    toolCalls: nil
                )
            ])
            
        case .failure(let error):
            return MCPResult(content: [
                MCPContent(
                    type: "text",
                    text: "❌ Ошибка при получении записей из базы данных: \(error.localizedDescription)",
                    toolCalls: nil
                )
            ])
        }
    }
    
    private func handleCreateMultipleGitHubIssuesFromNotion(_ arguments: [String: Any]) async -> MCPResult {
        guard let pageId = arguments["pageId"] as? String else {
            return MCPResult(content: [
                MCPContent(
                    type: "text",
                    text: "❌ Ошибка: не указан ID страницы Notion",
                    toolCalls: nil
                )
            ])
        }
        
        guard let owner = arguments["owner"] as? String else {
            return MCPResult(content: [
                MCPContent(
                    type: "text",
                    text: "❌ Ошибка: не указан owner репозитория GitHub",
                    toolCalls: nil
                )
            ])
        }
        
        guard let repo = arguments["repo"] as? String else {
            return MCPResult(content: [
                MCPContent(
                    type: "text",
                    text: "❌ Ошибка: не указан repo репозитория GitHub",
                    toolCalls: nil
                )
            ])
        }
        
        // Получаем полное содержимое страницы Notion
        let pageResult = await getPageContent(pageId: pageId)
        guard case .success(let page) = pageResult else {
            return MCPResult(content: [
                MCPContent(
                    type: "text",
                    text: "❌ Ошибка при получении страницы Notion",
                    toolCalls: nil
                )
            ])
        }
        
        let blocksResult = await getPageBlocks(pageId: pageId)
        guard case .success(let blocksResponse) = blocksResult else {
            return MCPResult(content: [
                MCPContent(
                    type: "text",
                    text: "❌ Ошибка при получении содержимого страницы Notion",
                    toolCalls: nil
                )
            ])
        }
        
        let title = extractPageTitle(from: page.properties)
        
        // Извлекаем отдельные задачи из списков
        let issues = extractIssuesFromBlocks(blocks: blocksResponse.results, sourceTitle: title, sourceUrl: page.url)
        
        if issues.isEmpty {
            return MCPResult(content: [
                MCPContent(
                    type: "text",
                    text: """
                    ℹ️ На странице Notion "\(title)" не найдено отдельных задач для создания Issues.
                    
                    Страница содержит обычный текст, но не содержит:
                    • Списков с задачами (bulleted/numbered)
                    • To-do элементов
                    • Отдельных заголовков с задачами
                    
                    Используйте create_github_issue_from_notion для создания одного Issue из всего содержимого.
                    """,
                    toolCalls: nil
                )
            ])
        }
        
        // Создаем множественные toolCalls для каждой задачи
        let toolCalls = issues.map { issue in
            MCPToolCall(
                name: "create_issue",
                arguments: [
                    "title": issue.title,
                    "body": issue.body,
                    "owner": owner,
                    "repo": repo
                ]
            )
        }
        
        return MCPResult(content: [
            MCPContent(
                type: "text",
                text: """
                📋 Найдено \(issues.count) отдельных задач в Notion странице "\(title)":
                
                \(issues.enumerated().map { index, issue in
                    "\(index + 1). \(issue.title)"
                }.joined(separator: "\n"))
                
                📄 Источник: [Страница Notion](\(page.url))
                
                🚀 Создаю отдельные GitHub Issues для каждой задачи...
                """,
                toolCalls: toolCalls
            )
        ])
    }
    
    // MARK: - Helper Methods
    
    private func extractPageTitle(from properties: [String: NotionProperty]) -> String {
        // Ищем title в свойствах (обычно это ключ "title")
        if let titleProperty = properties["title"] {
            if case .title(let titleArray) = titleProperty {
                let title = titleArray.compactMap { richText in
                    switch richText {
                    case .text(let textContent):
                        return textContent.content
                    }
                }.joined()
                
                if !title.isEmpty {
                    return title
                }
            }
        }
        
        // Если не нашли title, ищем любое title свойство
        for (_, property) in properties {
            if case .title(let titleArray) = property {
                let title = titleArray.compactMap { richText in
                    switch richText {
                    case .text(let textContent):
                        return textContent.content
                    }
                }.joined()
                
                if !title.isEmpty {
                    return title
                }
            }
        }
        
        return "Без названия"
    }
    
    private func extractBlocksContent(from blocks: [NotionBlock]) -> String {
        var content: [String] = []
        
        for block in blocks {
            switch block.type {
            case "paragraph":
                if let paragraph = block.paragraph {
                    let text = extractRichTextContent(from: paragraph.richText)
                    if !text.isEmpty {
                        content.append(text)
                    }
                }
            case "heading_1":
                if let heading = block.heading1 {
                    let text = extractRichTextContent(from: heading.richText)
                    if !text.isEmpty {
                        content.append("# \(text)")
                    }
                }
            case "heading_2":
                if let heading = block.heading2 {
                    let text = extractRichTextContent(from: heading.richText)
                    if !text.isEmpty {
                        content.append("## \(text)")
                    }
                }
            case "heading_3":
                if let heading = block.heading3 {
                    let text = extractRichTextContent(from: heading.richText)
                    if !text.isEmpty {
                        content.append("### \(text)")
                    }
                }
            case "bulleted_list_item":
                if let listItem = block.bulletedListItem {
                    let text = extractRichTextContent(from: listItem.richText)
                    if !text.isEmpty {
                        content.append("• \(text)")
                    }
                }
            case "numbered_list_item":
                if let listItem = block.numberedListItem {
                    let text = extractRichTextContent(from: listItem.richText)
                    if !text.isEmpty {
                        content.append("1. \(text)")
                    }
                }
            case "to_do":
                if let todo = block.toDo {
                    let text = extractRichTextContent(from: todo.richText)
                    let checkbox = todo.checked ? "☑️" : "☐"
                    if !text.isEmpty {
                        content.append("\(checkbox) \(text)")
                    }
                }
            case "code":
                if let code = block.code {
                    let text = extractRichTextContent(from: code.richText)
                    if !text.isEmpty {
                        content.append("```\(code.language ?? "")\n\(text)\n```")
                    }
                }
            case "quote":
                if let quote = block.quote {
                    let text = extractRichTextContent(from: quote.richText)
                    if !text.isEmpty {
                        content.append("> \(text)")
                    }
                }
            default:
                // Для неизвестных типов блоков просто игнорируем
                continue
            }
        }
        
        return content.joined(separator: "\n\n")
    }
    
    private func extractRichTextContent(from richTextArray: [NotionRichText]) -> String {
        return richTextArray.compactMap { richText in
            switch richText {
            case .text(let textContent):
                return textContent.content
            }
        }.joined()
    }
    
    private func extractIssuesFromBlocks(blocks: [NotionBlock], sourceTitle: String, sourceUrl: String) -> [IssueData] {
        var issues: [IssueData] = []
        var currentContext = ""
        
        for block in blocks {
            switch block.type {
            case "heading_1", "heading_2", "heading_3":
                // Сохраняем заголовки как контекст
                if let heading = block.heading1 ?? block.heading2 ?? block.heading3 {
                    currentContext = extractRichTextContent(from: heading.richText)
                }
                
            case "bulleted_list_item":
                if let listItem = block.bulletedListItem {
                    let text = extractRichTextContent(from: listItem.richText)
                    if !text.isEmpty && looksLikeIssue(text) {
                        let issue = createIssueFromText(
                            text: text,
                            context: currentContext,
                            sourceTitle: sourceTitle,
                            sourceUrl: sourceUrl
                        )
                        issues.append(issue)
                    }
                }
                
            case "numbered_list_item":
                if let listItem = block.numberedListItem {
                    let text = extractRichTextContent(from: listItem.richText)
                    if !text.isEmpty && looksLikeIssue(text) {
                        let issue = createIssueFromText(
                            text: text,
                            context: currentContext,
                            sourceTitle: sourceTitle,
                            sourceUrl: sourceUrl
                        )
                        issues.append(issue)
                    }
                }
                
            case "to_do":
                if let todo = block.toDo {
                    let text = extractRichTextContent(from: todo.richText)
                    if !text.isEmpty {
                        let issue = createIssueFromText(
                            text: text,
                            context: currentContext,
                            sourceTitle: sourceTitle,
                            sourceUrl: sourceUrl
                        )
                        issues.append(issue)
                    }
                }
                
            default:
                continue
            }
        }
        
        return issues
    }
    
    private func looksLikeIssue(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        
        // Ключевые слова, которые указывают на задачу/проблему
        let issueKeywords = [
            "bug", "issue", "problem", "error", "crash", "fix", "todo",
            "баг", "ошибка", "проблема", "исправить", "задача", "сделать",
            "app", "приложение", "не работает", "doesn't work", "broken"
        ]
        
        // Если текст содержит ключевые слова или выглядит как задача
        return issueKeywords.contains { lowercased.contains($0) } || 
               text.count > 10 || // Достаточно длинный текст
               text.contains(":") // Содержит двоеточие (часто в описаниях задач)
    }
    
    private func createIssueFromText(text: String, context: String, sourceTitle: String, sourceUrl: String) -> IssueData {
        // Создаем краткий заголовок из первых слов
        let title = createTitleFromText(text)
        
        // Создаем подробное описание
        let body = """
        **Источник:** [Notion: \(sourceTitle)](\(sourceUrl))
        \(context.isEmpty ? "" : "**Раздел:** \(context)")
        
        ## Описание
        \(text)
        
        ---
        *Автоматически создано из Notion*
        """
        
        return IssueData(title: title, body: body)
    }
    
    private func createTitleFromText(_ text: String) -> String {
        // Убираем лишние символы и берем первые несколько слов
        let cleaned = text
            .replacingOccurrences(of: "- ", with: "")
            .replacingOccurrences(of: "• ", with: "")
            .replacingOccurrences(of: "1. ", with: "")
            .replacingOccurrences(of: "2. ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Берем первые 60 символов или до первого переноса строки
        let maxLength = 60
        if cleaned.count <= maxLength {
            return cleaned
        }
        
        // Ищем последний пробел перед лимитом, чтобы не обрезать слово
        let truncated = String(cleaned.prefix(maxLength))
        if let lastSpace = truncated.lastIndex(of: " ") {
            return String(truncated[..<lastSpace])
        }
        
        return truncated
    }
}

// MARK: - Data Models

struct IssueData {
    let title: String
    let body: String
}

struct NotionSearchRequest: Codable {
    let query: String
    let filter: NotionSearchFilter
    let pageSize: Int
    
    enum CodingKeys: String, CodingKey {
        case query, filter
        case pageSize = "page_size"
    }
}

struct NotionSearchFilter: Codable {
    let value: String
    let property: String
}

struct NotionSearchResponse: Codable {
    let results: [NotionPage]
    let nextCursor: String?
    let hasMore: Bool
    
    enum CodingKeys: String, CodingKey {
        case results
        case nextCursor = "next_cursor"
        case hasMore = "has_more"
    }
}

struct NotionPage: Codable {
    let id: String
    let createdTime: String
    let lastEditedTime: String
    let url: String
    let properties: [String: NotionProperty]
    
    enum CodingKeys: String, CodingKey {
        case id, url, properties
        case createdTime = "created_time"
        case lastEditedTime = "last_edited_time"
    }
}

enum NotionProperty: Codable {
    case title([NotionRichText])
    case unknown
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Пытаемся получить тип свойства
        if let type = try? container.decode(String.self, forKey: .type) {
            switch type {
            case "title":
                // Для title свойства данные находятся в ключе "title" как массив
                if let titleArray = try? container.decode([NotionRichText].self, forKey: .title) {
                    self = .title(titleArray)
                } else {
                    self = .title([])
                }
            default:
                self = .unknown
            }
        } else {
            self = .unknown
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        switch self {
        case .title(let richText):
            try container.encode("title", forKey: .type)
            try container.encode(richText, forKey: .title)
        case .unknown:
            try container.encode("unknown", forKey: .type)
        }
    }
    
    private enum CodingKeys: String, CodingKey {
        case type, title
    }
}

enum NotionRichText: Codable {
    case text(NotionTextContent)
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        
        switch type {
        case "text":
            let text = try container.decode(NotionTextContent.self, forKey: .text)
            self = .text(text)
        default:
            // Для неизвестных типов создаем пустой текст
            self = .text(NotionTextContent(content: ""))
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        switch self {
        case .text(let textContent):
            try container.encode("text", forKey: .type)
            try container.encode(textContent, forKey: .text)
        }
    }
    
    private enum CodingKeys: String, CodingKey {
        case type, text
    }
}

struct NotionTextContent: Codable {
    let content: String
}

struct NotionBlocksResponse: Codable {
    let results: [NotionBlock]
    let nextCursor: String?
    let hasMore: Bool
    
    enum CodingKeys: String, CodingKey {
        case results
        case nextCursor = "next_cursor"
        case hasMore = "has_more"
    }
}

struct NotionBlock: Codable {
    let id: String
    let type: String
    let paragraph: NotionParagraph?
    let heading1: NotionHeading?
    let heading2: NotionHeading?
    let heading3: NotionHeading?
    let bulletedListItem: NotionListItem?
    let numberedListItem: NotionListItem?
    let toDo: NotionToDo?
    let code: NotionCode?
    let quote: NotionQuote?
    
    enum CodingKeys: String, CodingKey {
        case id, type, paragraph
        case heading1 = "heading_1"
        case heading2 = "heading_2"
        case heading3 = "heading_3"
        case bulletedListItem = "bulleted_list_item"
        case numberedListItem = "numbered_list_item"
        case toDo = "to_do"
        case code, quote
    }
}

struct NotionParagraph: Codable {
    let richText: [NotionRichText]
    
    enum CodingKeys: String, CodingKey {
        case richText = "rich_text"
    }
}

struct NotionHeading: Codable {
    let richText: [NotionRichText]
    
    enum CodingKeys: String, CodingKey {
        case richText = "rich_text"
    }
}

struct NotionListItem: Codable {
    let richText: [NotionRichText]
    
    enum CodingKeys: String, CodingKey {
        case richText = "rich_text"
    }
}

struct NotionToDo: Codable {
    let richText: [NotionRichText]
    let checked: Bool
    
    enum CodingKeys: String, CodingKey {
        case richText = "rich_text"
        case checked
    }
}

struct NotionCode: Codable {
    let richText: [NotionRichText]
    let language: String?
    
    enum CodingKeys: String, CodingKey {
        case richText = "rich_text"
        case language
    }
}

struct NotionQuote: Codable {
    let richText: [NotionRichText]
    
    enum CodingKeys: String, CodingKey {
        case richText = "rich_text"
    }
}

struct NotionDatabaseQueryRequest: Codable {
    let pageSize: Int
    
    enum CodingKeys: String, CodingKey {
        case pageSize = "page_size"
    }
}

struct NotionDatabaseQueryResponse: Codable {
    let results: [NotionPage]
    let nextCursor: String?
    let hasMore: Bool
    
    enum CodingKeys: String, CodingKey {
        case results
        case nextCursor = "next_cursor"
        case hasMore = "has_more"
    }
}

enum NotionMCPError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(Int)
    case apiError(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Неверный URL"
        case .invalidResponse:
            return "Неверный ответ от сервера"
        case .httpError(let code):
            return "HTTP ошибка: \(code)"
        case .apiError(let message):
            return "Notion API ошибка: \(message)"
        }
    }
}
