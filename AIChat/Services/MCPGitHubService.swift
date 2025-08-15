//
//  MCPGitHubService.swift
//  AIChat
//
//  Created by Николай Игнатов on 13.08.2025.
//

import Foundation

// MARK: - MCP Protocol Structures

struct MCPResult: Codable {
    let content: [MCPContent]
}

struct MCPContent: Codable {
    let type: String
    let text: String?
    let toolCalls: [MCPToolCall]?
}

struct MCPToolCall: Codable {
    let name: String
    let arguments: [String: String]
}

// MARK: - GitHub MCP Client

final class MCPGitHubService {
    private let githubToken: String
    private let baseURL = "https://api.github.com"
    
    init(githubToken: String) {
        self.githubToken = githubToken
    }
    
    // MARK: - MCP Tool Implementations
    
    func createRepository(name: String, description: String?, isPrivate: Bool = false) async -> Result<GitHubResponse, Error> {
        guard let url = URL(string: "\(baseURL)/user/repos") else {
            return .failure(GitHubMCPError.invalidURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(githubToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        
        let repository = GitHubRepository(
            name: name,
            description: description,
            isPrivate: isPrivate,
            autoInit: true
        )
        
        do {
            let jsonData = try JSONEncoder().encode(repository)
            request.httpBody = jsonData
            
            print("🔍 Отправляем запрос на создание репозитория:")
            print("URL: \(url)")
            print("Название: \(name)")
            print("Описание: \(description ?? "Не указано")")
            print("Приватный: \(isPrivate)")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("❌ Неверный HTTP ответ")
                return .failure(GitHubMCPError.invalidResponse)
            }
            
            print("📡 HTTP статус: \(httpResponse.statusCode)")
            
            if let responseString = String(data: data, encoding: .utf8) {
                print("📄 Ответ от GitHub: \(responseString)")
            }
            
            if httpResponse.statusCode == 201 {
                let repository = try JSONDecoder().decode(GitHubResponse.self, from: data)
                print("✅ Репозиторий успешно создан: \(repository.name)")
                return .success(repository)
            } else {
                if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let message = errorData["message"] as? String {
                    print("❌ GitHub API ошибка: \(message)")
                    return .failure(GitHubMCPError.apiError(message))
                } else {
                    print("❌ HTTP ошибка: \(httpResponse.statusCode)")
                    return .failure(GitHubMCPError.httpError(httpResponse.statusCode))
                }
            }
        } catch {
            print("❌ Ошибка при создании репозитория: \(error)")
            return .failure(error)
        }
    }
    
    func getUserInfo() async -> Result<GitHubUser, Error> {
        guard let url = URL(string: "\(baseURL)/user") else {
            return .failure(GitHubMCPError.invalidURL)
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(githubToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure(GitHubMCPError.invalidResponse)
            }
            
            if httpResponse.statusCode == 200 {
                let user = try JSONDecoder().decode(GitHubUser.self, from: data)
                return .success(user)
            } else {
                return .failure(GitHubMCPError.httpError(httpResponse.statusCode))
            }
        } catch {
            return .failure(error)
        }
    }
    
    func searchRepositories(query: String, page: Int = 1, perPage: Int = 30) async -> Result<GitHubSearchResponse, Error> {
        var components = URLComponents(string: "\(baseURL)/search/repositories")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "per_page", value: "\(perPage)")
        ]
        
        guard let url = components.url else {
            return .failure(GitHubMCPError.invalidURL)
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(githubToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure(GitHubMCPError.invalidResponse)
            }
            
            if httpResponse.statusCode == 200 {
                let searchResponse = try JSONDecoder().decode(GitHubSearchResponse.self, from: data)
                return .success(searchResponse)
            } else {
                if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let message = errorData["message"] as? String {
                    return .failure(GitHubMCPError.apiError(message))
                } else {
                    return .failure(GitHubMCPError.httpError(httpResponse.statusCode))
                }
            }
        } catch {
            return .failure(error)
        }
    }
    
    // MARK: - MCP Tool Execution
    
    func executeTool(name: String, arguments: [String: Any]) async -> MCPResult {
        print("🔧 MCP Service: Выполняем инструмент '\(name)' с аргументами: \(arguments)")
        
        switch name {
        case "create_repository":
            print("🔧 MCP Service: Создаем репозиторий...")
            return await handleCreateRepository(arguments)
        case "get_user_info":
            print("🔧 MCP Service: Получаем информацию о пользователе...")
            return await handleGetUserInfo()
        case "search_repositories":
            print("🔧 MCP Service: Ищем репозитории...")
            return await handleSearchRepositories(arguments)
        default:
            print("❌ MCP Service: Неизвестный инструмент: \(name)")
            return MCPResult(content: [
                MCPContent(
                    type: "text",
                    text: "❌ Неизвестный инструмент: \(name)",
                    toolCalls: nil
                )
            ])
        }
    }
    
    private func handleCreateRepository(_ arguments: [String: Any]) async -> MCPResult {
        print("🔧 handleCreateRepository: Начинаем обработку аргументов: \(arguments)")
        
        guard let name = arguments["name"] as? String else {
            print("❌ handleCreateRepository: Не указано название репозитория")
            return MCPResult(content: [
                MCPContent(
                    type: "text",
                    text: "❌ Ошибка: не указано название репозитория",
                    toolCalls: nil
                )
            ])
        }
        
        let description = arguments["description"] as? String
        let isPrivate = arguments["isPrivate"] as? Bool ?? false
        
        print("🔧 handleCreateRepository: Параметры репозитория:")
        print("  - Название: \(name)")
        print("  - Описание: \(description ?? "Не указано")")
        print("  - Приватный: \(isPrivate)")
        
        let result = await createRepository(
            name: name,
            description: description,
            isPrivate: isPrivate
        )
        
        switch result {
        case .success(let repository):
            return MCPResult(content: [
                MCPContent(
                    type: "text",
                    text: """
                    ✅ Репозиторий успешно создан!
                    
                    📁 Название: \(repository.name)
                    🔗 URL: \(repository.htmlUrl)
                    📋 Описание: \(repository.description ?? "Не указано")
                    🔒 Приватный: \(repository.isPrivate ? "Да" : "Нет")
                    📅 Создан: \(repository.createdAt)
                    
                    Для клонирования используйте:
                    git clone \(repository.cloneUrl)
                    """,
                    toolCalls: nil
                )
            ])
            
        case .failure(let error):
            return MCPResult(content: [
                MCPContent(
                    type: "text",
                    text: "❌ Ошибка при создании репозитория: \(error.localizedDescription)",
                    toolCalls: nil
                )
            ])
        }
    }
    
    private func handleGetUserInfo() async -> MCPResult {
        let result = await getUserInfo()
        
        switch result {
        case .success(let user):
            return MCPResult(content: [
                MCPContent(
                    type: "text",
                    text: """
                    👤 Информация о пользователе GitHub:
                    
                    🏷️ Логин: \(user.login)
                    📝 Имя: \(user.name ?? "Не указано")
                    📧 Email: \(user.email ?? "Не указан")
                    🆔 ID: \(user.id)
                    """,
                    toolCalls: nil
                )
            ])
            
        case .failure(let error):
            return MCPResult(content: [
                MCPContent(
                    type: "text",
                    text: "❌ Ошибка при получении информации о пользователе: \(error.localizedDescription)",
                    toolCalls: nil
                )
            ])
        }
    }
    
    private func handleSearchRepositories(_ arguments: [String: Any]) async -> MCPResult {
        guard let query = arguments["query"] as? String else {
            return MCPResult(content: [
                MCPContent(
                    type: "text",
                    text: "❌ Ошибка: не указан поисковый запрос",
                    toolCalls: nil
                )
            ])
        }
        
        let page = arguments["page"] as? Int ?? 1
        let perPage = arguments["perPage"] as? Int ?? 10
        
        let result = await searchRepositories(
            query: query,
            page: page,
            perPage: perPage
        )
        
        switch result {
        case .success(let searchResponse):
            let repositories = searchResponse.items.prefix(5) // Показываем первые 5
            let repoList = repositories.map { repo in
                """
                📁 \(repo.name)
                🔗 \(repo.htmlUrl)
                📋 \(repo.description ?? "Без описания")
                """
            }.joined(separator: "\n\n")
            
            return MCPResult(content: [
                MCPContent(
                    type: "text",
                    text: """
                    🔍 Результаты поиска репозиториев для "\(query)":
                    
                    Всего найдено: \(searchResponse.totalCount)
                    
                    \(repoList)
                    """,
                    toolCalls: nil
                )
            ])
            
        case .failure(let error):
            return MCPResult(content: [
                MCPContent(
                    type: "text",
                    text: "❌ Ошибка при поиске репозиториев: \(error.localizedDescription)",
                    toolCalls: nil
                )
            ])
        }
    }
}

// MARK: - Data Models

struct GitHubRepository: Codable {
    let name: String
    let description: String?
    let isPrivate: Bool
    let autoInit: Bool
    
    enum CodingKeys: String, CodingKey {
        case name, description
        case isPrivate = "private"
        case autoInit = "auto_init"
    }
}

struct GitHubResponse: Codable {
    let id: Int
    let name: String
    let fullName: String
    let description: String?
    let htmlUrl: String
    let cloneUrl: String
    let isPrivate: Bool
    let createdAt: String
    
    enum CodingKeys: String, CodingKey {
        case id, name, description
        case isPrivate = "private"
        case fullName = "full_name"
        case htmlUrl = "html_url"
        case cloneUrl = "clone_url"
        case createdAt = "created_at"
    }
}

struct GitHubUser: Codable {
    let login: String
    let id: Int
    let name: String?
    let email: String?
    let avatarUrl: String
    
    enum CodingKeys: String, CodingKey {
        case login, id, name, email
        case avatarUrl = "avatar_url"
    }
}

struct GitHubSearchResponse: Codable {
    let totalCount: Int
    let items: [GitHubResponse]
    
    enum CodingKeys: String, CodingKey {
        case totalCount = "total_count"
        case items
    }
}

enum GitHubMCPError: LocalizedError {
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
            return "GitHub API ошибка: \(message)"
        }
    }
}
