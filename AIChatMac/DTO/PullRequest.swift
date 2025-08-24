//
//  PullRequest.swift
//  AIChatMac
//
//  Created by Николай Игнатов on 19.08.2025.
//

import Foundation

struct PullRequest: Identifiable, Codable {
    let id: Int
    let number: Int
    let title: String
    let body: String?
    let state: String
    let user: GitHubUser
    let head: PRBranch
    let base: PRBranch
    let additions: Int
    let deletions: Int
    let changedFiles: Int
    let createdAt: Date
    let updatedAt: Date
    let htmlUrl: String
    let diffUrl: String
    let patchUrl: String
    let commitsUrl: String
    let commentsUrl: String
    let reviewCommentsUrl: String
    let statusesUrl: String
    
    enum CodingKeys: String, CodingKey {
        case id, number, title, body, state, user, head, base
        case additions, deletions
        case changedFiles = "changed_files"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case htmlUrl = "html_url"
        case diffUrl = "diff_url"
        case patchUrl = "patch_url"
        case commitsUrl = "commits_url"
        case commentsUrl = "comments_url"
        case reviewCommentsUrl = "review_comments_url"
        case statusesUrl = "statuses_url"
    }
}

struct PRBranch: Codable {
    let label: String
    let ref: String
    let sha: String
    let user: GitHubUser
    let repo: GitHubRepository
}

struct CodeReview: Identifiable, Codable {
    let id = UUID()
    let prId: Int
    let prNumber: Int
    let issues: [CodeIssue]
    let warnings: [CodeWarning]
    let suggestions: [CodeSuggestion]
    let overallScore: Int
    let reviewDate: Date
    let summary: String
}

struct CodeIssue: Identifiable, Codable {
    let id = UUID()
    let type: IssueType
    let severity: Severity
    let file: String?
    let line: Int?
    let message: String
    let suggestion: String?
    let codeSnippet: String?
}

struct CodeWarning: Identifiable, Codable {
    let id = UUID()
    let type: WarningType
    let file: String?
    let line: Int?
    let message: String
    let suggestion: String?
}

struct CodeSuggestion: Identifiable, Codable {
    let id = UUID()
    let type: SuggestionType
    let file: String?
    let line: Int?
    let message: String
    let code: String?
}

enum IssueType: String, CaseIterable, Codable {
    case security = "Безопасность"
    case performance = "Производительность"
    case codeStyle = "Стиль кода"
    case documentation = "Документация"
    case testCoverage = "Покрытие тестами"
    case bug = "Ошибка"
    case architecture = "Архитектура"
    case naming = "Именование"
}

enum WarningType: String, CaseIterable, Codable {
    case codeStyle = "Стиль кода"
    case performance = "Производительность"
    case documentation = "Документация"
    case bestPractice = "Лучшие практики"
}

enum SuggestionType: String, CaseIterable, Codable {
    case refactoring = "Рефакторинг"
    case optimization = "Оптимизация"
    case documentation = "Документация"
    case testing = "Тестирование"
}

enum Severity: String, CaseIterable, Codable {
    case low = "Низкий"
    case medium = "Средний"
    case high = "Высокий"
    case critical = "Критический"
    
    var emoji: String {
        switch self {
        case .low: return "🔵"
        case .medium: return "🟡"
        case .high: return "🟠"
        case .critical: return "🔴"
        }
    }
}

struct GitHubIssueRequest: Codable {
    let title: String
    let body: String
    let labels: [String]
    let assignees: [String]?
    
    init(title: String, body: String, labels: [String] = [], assignees: [String]? = nil) {
        self.title = title
        self.body = body
        self.labels = labels
        self.assignees = assignees
    }
}
