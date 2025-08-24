//
//  GitHubPRService.swift
//  AIChatMac
//
//  Created by Николай Игнатов on 19.08.2025.
//

import Foundation

final class GitHubPRService {
    private let githubToken: String
    private let baseURL = "https://api.github.com"
    
    init(githubToken: String) {
        self.githubToken = githubToken
    }
    
    // MARK: - URL Parsing
    
    func parseGitHubPRURL(_ urlString: String) -> (owner: String, repo: String, prNumber: Int)? {
        // Поддерживаемые форматы:
        // https://github.com/owner/repo/pull/123
        // https://github.com/owner/repo/pull/123/files
        // https://github.com/owner/repo/pull/123#issuecomment-456
        // @https://github.com/owner/repo/pull/123
        
        // Очищаем URL от лишних символов в начале
        var cleanURLString = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Убираем символ @ в начале, если есть
        if cleanURLString.hasPrefix("@") {
            cleanURLString = String(cleanURLString.dropFirst())
        }
        
        // Убираем пробелы в начале, если есть
        cleanURLString = cleanURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let url = URL(string: cleanURLString),
              url.host == "github.com" else {
            return nil
        }
        
        let components = url.pathComponents.filter { !$0.isEmpty }
        
        // Убираем первый элемент, если это "/"
        let cleanComponents = components.first == "/" ? Array(components.dropFirst()) : components
        
        guard cleanComponents.count >= 4,
              cleanComponents[2] == "pull",
              let prNumber = Int(cleanComponents[3]) else {
            return nil
        }
        
        let owner = cleanComponents[0]
        let repo = cleanComponents[1]
        
        return (owner: owner, repo: repo, prNumber: prNumber)
    }
    
    // MARK: - Pull Request Operations
    
    func fetchPullRequest(owner: String, repo: String, prNumber: Int) async -> Result<PullRequest, Error> {
        guard let url = URL(string: "\(baseURL)/repos/\(owner)/\(repo)/pulls/\(prNumber)") else {
            return .failure(GitHubError.invalidURL)
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(githubToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure(GitHubError.invalidResponse)
            }
            
            if httpResponse.statusCode == 200 {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let pullRequest = try decoder.decode(PullRequest.self, from: data)
                return .success(pullRequest)
            } else {
                return .failure(GitHubError.httpError(httpResponse.statusCode))
            }
        } catch {
            return .failure(error)
        }
    }
    
    func fetchPullRequestFiles(owner: String, repo: String, prNumber: Int) async -> Result<[PRFile], Error> {
        guard let url = URL(string: "\(baseURL)/repos/\(owner)/\(repo)/pulls/\(prNumber)/files") else {
            return .failure(GitHubError.invalidURL)
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(githubToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure(GitHubError.invalidResponse)
            }
            
            if httpResponse.statusCode == 200 {
                let files = try JSONDecoder().decode([PRFile].self, from: data)
                return .success(files)
            } else {
                return .failure(GitHubError.httpError(httpResponse.statusCode))
            }
        } catch {
            return .failure(error)
        }
    }
    
    func fetchPullRequestDiff(owner: String, repo: String, prNumber: Int) async -> Result<String, Error> {
        guard let url = URL(string: "\(baseURL)/repos/\(owner)/\(repo)/pulls/\(prNumber)") else {
            return .failure(GitHubError.invalidURL)
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(githubToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github.v3.diff", forHTTPHeaderField: "Accept")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure(GitHubError.invalidResponse)
            }
            
            if httpResponse.statusCode == 200 {
                guard let diffString = String(data: data, encoding: .utf8) else {
                    return .failure(GitHubError.invalidData)
                }
                return .success(diffString)
            } else {
                return .failure(GitHubError.httpError(httpResponse.statusCode))
            }
        } catch {
            return .failure(error)
        }
    }
    
    // MARK: - Issue Operations
    
    func createIssue(owner: String, repo: String, issue: GitHubIssueRequest) async -> Result<GitHubIssueResponse, Error> {
        guard let url = URL(string: "\(baseURL)/repos/\(owner)/\(repo)/issues") else {
            return .failure(GitHubError.invalidURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(githubToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            let jsonData = try JSONEncoder().encode(issue)
            request.httpBody = jsonData
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure(GitHubError.invalidResponse)
            }
            
            if httpResponse.statusCode == 201 {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let issueResponse = try decoder.decode(GitHubIssueResponse.self, from: data)
                return .success(issueResponse)
            } else {
                return .failure(GitHubError.httpError(httpResponse.statusCode))
            }
        } catch {
            return .failure(error)
        }
    }
    
    func addCommentToPR(owner: String, repo: String, prNumber: Int, comment: String) async -> Result<GitHubComment, Error> {
        guard let url = URL(string: "\(baseURL)/repos/\(owner)/\(repo)/issues/\(prNumber)/comments") else {
            return .failure(GitHubError.invalidURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(githubToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let commentData = ["body": comment]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: commentData)
            request.httpBody = jsonData
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure(GitHubError.invalidResponse)
            }
            
            if httpResponse.statusCode == 201 {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let comment = try decoder.decode(GitHubComment.self, from: data)
                return .success(comment)
            } else {
                return .failure(GitHubError.httpError(httpResponse.statusCode))
            }
        } catch {
            return .failure(error)
        }
    }
}

// MARK: - Supporting Models

struct PRFile: Codable {
    let sha: String
    let filename: String
    let status: String
    let additions: Int
    let deletions: Int
    let changes: Int
    let blobUrl: String
    let rawUrl: String
    let contentsUrl: String
    let patch: String?
    
    enum CodingKeys: String, CodingKey {
        case sha, filename, status, additions, deletions, changes
        case blobUrl = "blob_url"
        case rawUrl = "raw_url"
        case contentsUrl = "contents_url"
        case patch
    }
}

struct GitHubIssueResponse: Codable {
    let id: Int
    let number: Int
    let title: String
    let body: String?
    let state: String
    let htmlUrl: String
    let createdAt: Date
    let updatedAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id, number, title, body, state
        case htmlUrl = "html_url"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct GitHubComment: Codable {
    let id: Int
    let body: String
    let user: GitHubUser
    let createdAt: Date
    let updatedAt: Date
    let htmlUrl: String
    
    enum CodingKeys: String, CodingKey {
        case id, body, user
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case htmlUrl = "html_url"
    }
}

enum GitHubError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case invalidData
    case httpError(Int)
    case apiError(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Неверный URL"
        case .invalidResponse:
            return "Неверный ответ от сервера"
        case .invalidData:
            return "Неверные данные"
        case .httpError(let code):
            return "HTTP ошибка: \(code)"
        case .apiError(let message):
            return "API ошибка: \(message)"
        }
    }
}
