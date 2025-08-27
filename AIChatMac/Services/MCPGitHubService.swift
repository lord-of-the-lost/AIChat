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
            id: 0, // Будет установлено сервером
            name: name,
            fullName: "", // Будет установлено сервером
            description: description,
            isPrivate: isPrivate,
            htmlUrl: "", // Будет установлено сервером
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
    
    func getUserRepositories(page: Int = 1, perPage: Int = 30) async -> Result<[GitHubResponse], Error> {
        var components = URLComponents(string: "\(baseURL)/user/repos")!
        components.queryItems = [
            URLQueryItem(name: "sort", value: "updated"),
            URLQueryItem(name: "direction", value: "desc"),
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "per_page", value: "\(perPage)")
        ]
        
        guard let url = components.url else {
            return .failure(GitHubMCPError.invalidURL)
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(githubToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        
        print("🔍 Получаем репозитории пользователя")
        print("URL: \(url)")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure(GitHubMCPError.invalidResponse)
            }
            
            print("📡 HTTP статус: \(httpResponse.statusCode)")
            
            if httpResponse.statusCode == 200 {
                let repositories = try JSONDecoder().decode([GitHubResponse].self, from: data)
                print("✅ Получено \(repositories.count) репозиториев")
                return .success(repositories)
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
            print("❌ Ошибка при получении репозиториев: \(error)")
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
    
    func getIssues(owner: String, repo: String, state: String = "open", page: Int = 1, perPage: Int = 30) async -> Result<[GitHubIssue], Error> {
        var components = URLComponents(string: "\(baseURL)/repos/\(owner)/\(repo)/issues")!
        components.queryItems = [
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "per_page", value: "\(perPage)")
        ]
        
        guard let url = components.url else {
            return .failure(GitHubMCPError.invalidURL)
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(githubToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        
        print("🔍 Получаем Issues для репозитория \(owner)/\(repo)")
        print("URL: \(url)")
        print("Состояние: \(state)")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure(GitHubMCPError.invalidResponse)
            }
            
            print("📡 HTTP статус: \(httpResponse.statusCode)")
            
            if httpResponse.statusCode == 200 {
                let issues = try JSONDecoder().decode([GitHubIssue].self, from: data)
                print("✅ Получено \(issues.count) Issues")
                return .success(issues)
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
            print("❌ Ошибка при получении Issues: \(error)")
            return .failure(error)
        }
    }
    
    // MARK: - Git Operations
    
    func getRepositoryInfo(owner: String, repo: String) async -> Result<GitHubRepositoryInfo, Error> {
        let url = URL(string: "\(baseURL)/repos/\(owner)/\(repo)")!
        
        var request = URLRequest(url: url)
        request.setValue("token \(githubToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        
        print("🔍 Проверяем доступ к репозиторию: \(owner)/\(repo)")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                print("📡 HTTP статус: \(httpResponse.statusCode)")
            }
            
            print("📋 Ответ: \(String(data: data, encoding: .utf8) ?? "Unknown")")
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                let errorData = String(data: data, encoding: .utf8) ?? "Unknown error"
                print("❌ GitHub API ошибка: \(errorData)")
                return .failure(GitHubMCPError.httpError((response as? HTTPURLResponse)?.statusCode ?? -1))
            }
            
            let repositoryInfo = try JSONDecoder().decode(GitHubRepositoryInfo.self, from: data)
            print("✅ Репозиторий найден: \(repositoryInfo.name)")
            print("📋 Default branch: \(repositoryInfo.defaultBranch)")
            print("🔒 Приватный: \(repositoryInfo.isPrivate)")
            
            return .success(repositoryInfo)
        } catch {
            print("❌ Ошибка получения информации о репозитории: \(error)")
            return .failure(error)
        }
    }
    
    func createBranch(owner: String, repo: String, branchName: String, baseBranch: String = "main") async -> Result<Void, Error> {
        // Сначала получаем SHA последнего коммита в базовой ветке
        let commitResult = await getLatestCommit(owner: owner, repo: repo, branch: baseBranch)
        
        switch commitResult {
        case .success(let commit):
            // Создаем новую ветку
            guard let url = URL(string: "\(baseURL)/repos/\(owner)/\(repo)/git/refs") else {
                return .failure(GitHubMCPError.invalidURL)
            }
            
                    var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("token \(githubToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let payload: [String: Any] = [
                "ref": "refs/heads/\(branchName)",
                "sha": commit.sha
            ]
            
            do {
                request.httpBody = try JSONSerialization.data(withJSONObject: payload)
                
                let (data, response) = try await URLSession.shared.data(for: request)
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    return .failure(GitHubMCPError.invalidResponse)
                }
                
                if httpResponse.statusCode == 201 {
                    print("✅ Ветка \(branchName) создана успешно")
                    return .success(())
                } else if httpResponse.statusCode == 422 {
                    // Ветка уже существует
                    print("⚠️ Ветка \(branchName) уже существует, продолжаем...")
                    return .success(())
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
                return .failure(error)
            }
            
        case .failure(let error):
            return .failure(error)
        }
    }
    
    func createFile(owner: String, repo: String, path: String, content: String, message: String, branch: String = "main") async -> Result<GitHubFileResponse, Error> {
        guard let url = URL(string: "\(baseURL)/repos/\(owner)/\(repo)/contents/\(path)") else {
            return .failure(GitHubMCPError.invalidURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("token \(githubToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let payload: [String: Any] = [
            "message": message,
            "content": Data(content.utf8).base64EncodedString(),
            "branch": branch
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            
            print("🔍 Создаем файл \(path) в репозитории \(owner)/\(repo)")
            print("URL: \(url)")
            print("Ветка: \(branch)")
            print("Сообщение: \(message)")
            print("Payload: \(payload)")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure(GitHubMCPError.invalidResponse)
            }
            
            print("📡 HTTP статус: \(httpResponse.statusCode)")
            print("📡 Response data: \(String(data: data, encoding: .utf8) ?? "Unknown")")
            
            if httpResponse.statusCode == 201 {
                let fileResponse = try JSONDecoder().decode(GitHubFileResponse.self, from: data)
                print("✅ Файл \(path) создан успешно")
                return .success(fileResponse)
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
            print("❌ Ошибка при создании файла: \(error)")
            return .failure(error)
        }
    }
    
    func createPullRequest(owner: String, repo: String, title: String, body: String, headBranch: String, baseBranch: String = "main") async -> Result<GitHubPullRequest, Error> {
        guard let url = URL(string: "\(baseURL)/repos/\(owner)/\(repo)/pulls") else {
            return .failure(GitHubMCPError.invalidURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("token \(githubToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let payload: [String: Any] = [
            "title": title,
            "body": body,
            "head": headBranch,
            "base": baseBranch
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            
            print("🔍 Создаем Pull Request в репозитории \(owner)/\(repo)")
            print("Заголовок: \(title)")
            print("Ветка: \(headBranch) → \(baseBranch)")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure(GitHubMCPError.invalidResponse)
            }
            
            print("📡 HTTP статус: \(httpResponse.statusCode)")
            
            if httpResponse.statusCode == 201 {
                let pullRequest = try JSONDecoder().decode(GitHubPullRequest.self, from: data)
                print("✅ Pull Request создан успешно: #\(pullRequest.number)")
                return .success(pullRequest)
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
            print("❌ Ошибка при создании Pull Request: \(error)")
            return .failure(error)
        }
    }
    
    private func getLatestCommit(owner: String, repo: String, branch: String) async -> Result<GitHubCommit, Error> {
        guard let url = URL(string: "\(baseURL)/repos/\(owner)/\(repo)/commits/\(branch)") else {
            return .failure(GitHubMCPError.invalidURL)
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(githubToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure(GitHubMCPError.invalidResponse)
            }
            
            if httpResponse.statusCode == 200 {
                let commit = try JSONDecoder().decode(GitHubCommit.self, from: data)
                return .success(commit)
            } else {
                return .failure(GitHubMCPError.httpError(httpResponse.statusCode))
            }
        } catch {
            return .failure(error)
        }
    }
    
    // MARK: - MCP Tool Execution
    
    func executeTool(name: String, arguments: [String: Any]) async -> MCPResult {
        switch name {
        case "create_repository":
            return await handleCreateRepository(arguments)
        case "get_user_info":
            return await handleGetUserInfo()
        case "get_user_repositories":
            return await handleGetUserRepositories(arguments)
        case "search_repositories":
            return await handleSearchRepositories(arguments)
        case "get_issues":
            return await handleGetIssues(arguments)
        default:
            return MCPResult(content: [
                MCPContent(
                    type: "text",
                    text: "❌ Неизвестный инструмент: \(name). Доступные инструменты: create_repository, get_user_info, get_user_repositories, search_repositories, get_issues",
                    toolCalls: nil
                )
            ])
        }
    }
    
    private func handleCreateRepository(_ arguments: [String: Any]) async -> MCPResult {
        guard let name = arguments["name"] as? String else {
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
    
    private func handleGetUserRepositories(_ arguments: [String: Any]) async -> MCPResult {
        let page = arguments["page"] as? Int ?? 1
        let perPage = arguments["perPage"] as? Int ?? 30
        
        let result = await getUserRepositories(page: page, perPage: perPage)
        
        switch result {
        case .success(let repositories):
            if repositories.isEmpty {
                return MCPResult(content: [
                    MCPContent(
                        type: "text",
                        text: """
                        📁 Ваши репозитории:
                        
                        У вас пока нет репозиториев.
                        """,
                        toolCalls: nil
                    )
                ])
            }
            
            let reposList = repositories.map { repo in
                """
                📁 \(repo.name)
                🔗 \(repo.htmlUrl)
                📋 \(repo.description ?? "Без описания")
                🔒 \(repo.isPrivate ? "Приватный" : "Публичный")
                📅 Обновлен: \(repo.createdAt)
                """
            }.joined(separator: "\n\n")
            
            return MCPResult(content: [
                MCPContent(
                    type: "text",
                    text: """
                    📁 Ваши репозитории (последние обновленные):
                    
                    Всего репозиториев: \(repositories.count)
                    
                    \(reposList)
                    """,
                    toolCalls: nil
                )
            ])
            
        case .failure(let error):
            return MCPResult(content: [
                MCPContent(
                    type: "text",
                    text: "❌ Ошибка при получении репозиториев: \(error.localizedDescription)",
                    toolCalls: nil
                )
            ])
        }
    }
    
    private func handleGetIssues(_ arguments: [String: Any]) async -> MCPResult {
        guard let owner = arguments["owner"] as? String else {
            return MCPResult(content: [
                MCPContent(
                    type: "text",
                    text: "❌ Не указан owner репозитория",
                    toolCalls: nil
                )
            ])
        }
        
        guard let repo = arguments["repo"] as? String else {
            return MCPResult(content: [
                MCPContent(
                    type: "text",
                    text: "❌ Не указан repo репозитория",
                    toolCalls: nil
                )
            ])
        }
        
        let state = arguments["state"] as? String ?? "open"
        
        let result = await getIssues(owner: owner, repo: repo, state: state)
        
        switch result {
        case .success(let issues):
            if issues.isEmpty {
                return MCPResult(content: [
                    MCPContent(
                        type: "text",
                        text: """
                        📋 Issues в репозитории \(owner)/\(repo):
                        
                        Нет открытых Issues в репозитории.
                        """,
                        toolCalls: nil
                    )
                ])
            }
            
            let issuesList = issues.map { issue in
                """
                🔢 #\(issue.number) - \(issue.title)
                📝 \(issue.body ?? "Без описания")
                👤 Автор: \(issue.user.login)
                📅 Создан: \(issue.createdAt)
                🔗 URL: \(issue.htmlUrl)
                """
            }.joined(separator: "\n\n")
            
            return MCPResult(content: [
                MCPContent(
                    type: "text",
                    text: """
                    📋 Issues в репозитории \(owner)/\(repo):
                    
                    Всего Issues: \(issues.count)
                    
                    \(issuesList)
                    """,
                    toolCalls: nil
                )
            ])
            
        case .failure(let error):
            return MCPResult(content: [
                MCPContent(
                    type: "text",
                    text: "❌ Ошибка при получении Issues: \(error.localizedDescription)",
                    toolCalls: nil
                )
            ])
        }
    }
}

// MARK: - Data Models

struct GitHubRepository: Codable {
    let id: Int
    let name: String
    let fullName: String
    let description: String?
    let isPrivate: Bool
    let htmlUrl: String
    let autoInit: Bool?
    
    enum CodingKeys: String, CodingKey {
        case id, name, description
        case fullName = "full_name"
        case isPrivate = "private"
        case htmlUrl = "html_url"
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
    let htmlUrl: String?
    
    enum CodingKeys: String, CodingKey {
        case login, id, name, email
        case avatarUrl = "avatar_url"
        case htmlUrl = "html_url"
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

struct GitHubIssue: Codable {
    let id: Int
    let number: Int
    let title: String
    let body: String?
    let state: String
    let htmlUrl: String
    let createdAt: String
    let updatedAt: String
    let user: GitHubIssueUser
    let labels: [GitHubLabel]
    
    enum CodingKeys: String, CodingKey {
        case id, number, title, body, state
        case htmlUrl = "html_url"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case user, labels
    }
}

struct GitHubIssueUser: Codable {
    let login: String
    let id: Int
    let avatarUrl: String
    
    enum CodingKeys: String, CodingKey {
        case login, id
        case avatarUrl = "avatar_url"
    }
}

struct GitHubLabel: Codable {
    let id: Int
    let name: String
    let color: String
    let description: String?
}

struct GitHubFileResponse: Codable {
    let content: GitHubFileContent
    let commit: GitHubFileCommit
    
    struct GitHubFileContent: Codable {
        let name: String
        let path: String
        let sha: String
        let size: Int
        let url: String
        let htmlUrl: String
        let gitUrl: String
        let downloadUrl: String?
        let type: String
        let content: String?
        let encoding: String?
        
        enum CodingKeys: String, CodingKey {
            case name, path, sha, size, url, type, content, encoding
            case htmlUrl = "html_url"
            case gitUrl = "git_url"
            case downloadUrl = "download_url"
        }
    }
    
    struct GitHubFileCommit: Codable {
        let sha: String
        let url: String
        let htmlUrl: String
        let author: GitHubCommitAuthor
        let committer: GitHubCommitAuthor
        let message: String
        
        enum CodingKeys: String, CodingKey {
            case sha, url, message, author, committer
            case htmlUrl = "html_url"
        }
    }
}

struct GitHubPullRequest: Codable {
    let id: Int
    let number: Int
    let title: String
    let body: String?
    let state: String
    let htmlUrl: String
    let createdAt: String
    let updatedAt: String
    let user: GitHubUser
    let head: GitHubPRBranch
    let base: GitHubPRBranch
    
    enum CodingKeys: String, CodingKey {
        case id, number, title, body, state, user, head, base
        case htmlUrl = "html_url"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct GitHubPRBranch: Codable {
    let label: String
    let ref: String
    let sha: String
    let user: GitHubUser?
    let repo: GitHubRepository?
}

struct GitHubRepositoryInfo: Codable {
    let id: Int
    let name: String
    let fullName: String
    let isPrivate: Bool
    let defaultBranch: String
    let description: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case fullName = "full_name"
        case isPrivate = "private"
        case defaultBranch = "default_branch"
        case description
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
