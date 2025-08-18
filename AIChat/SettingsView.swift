//
//  SettingsView.swift
//  AIChat
//
//  Created by Николай Игнатов on 13.08.2025.
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var githubToken = UserDefaults.standard.string(forKey: "githubToken") ?? ""
    @State private var notionToken = UserDefaults.standard.string(forKey: "notionToken") ?? ""
    @State private var showGitHubTokenView = false
    @State private var showNotionTokenView = false
    
    var body: some View {
        NavigationView {
            List {
                Section("MCP Интеграции") {
                    // GitHub Integration
                    HStack {
                        VStack(alignment: .leading) {
                            Text("GitHub MCP")
                                .font(.headline)
                            Text(githubTokenStatus)
                                .font(.caption)
                                .foregroundColor(githubToken.isEmpty ? .red : .green)
                        }
                        
                        Spacer()
                        
                        Button("Настроить") {
                            showGitHubTokenView = true
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    // Notion Integration
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Notion MCP")
                                .font(.headline)
                            Text(notionTokenStatus)
                                .font(.caption)
                                .foregroundColor(notionToken.isEmpty ? .red : .green)
                        }
                        
                        Spacer()
                        
                        Button("Настроить") {
                            showNotionTokenView = true
                        }
                        .buttonStyle(.bordered)
                    }
                }
                
                Section("Доступные MCP инструменты") {
                    if !githubToken.isEmpty {
                        MCPToolRow(
                            icon: "git.branch",
                            name: "GitHub MCP",
                            tools: [
                                "get_user_repositories",
                                "get_issues", 
                                "create_repository",
                                "create_issue"
                            ]
                        )
                    }
                    
                    if !notionToken.isEmpty {
                        MCPToolRow(
                            icon: "book.fill",
                            name: "Notion MCP",
                            tools: [
                                "search_notion_pages",
                                "get_notion_page",
                                "get_notion_page_content",
                                "create_github_issue_from_notion"
                            ]
                        )
                    }
                    
                    if githubToken.isEmpty && notionToken.isEmpty {
                        Text("Настройте интеграции для доступа к MCP инструментам")
                            .foregroundColor(.secondary)
                            .italic()
                    }
                }
                
                Section("Сценарии использования") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "arrow.right.circle.fill")
                                .foregroundColor(.blue)
                            Text("Notion → GitHub")
                                .fontWeight(.semibold)
                        }
                        
                        Text("1. Найдите страницу в Notion: \"Найди в Notion страницу проекта X\"")
                            .font(.caption)
                        Text("2. Перенесите в GitHub: \"Создай issue из этой страницы\"")
                            .font(.caption)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "git.branch")
                                .foregroundColor(.green)
                            Text("GitHub управление")
                                .fontWeight(.semibold)
                        }
                        
                        Text("• \"Покажи мои репозитории\"")
                            .font(.caption)
                        Text("• \"Покажи issues в проекте X\"")
                            .font(.caption)
                        Text("• \"Создай новый репозиторий\"")
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Настройки MCP")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Готово") {
                        dismiss()
                    }
                }
            }
        }
        .sheet(isPresented: $showGitHubTokenView) {
            GitHubTokenView(githubToken: .constant(githubToken), isTokenValid: .constant(true))
                .onDisappear {
                    githubToken = UserDefaults.standard.string(forKey: "githubToken") ?? ""
                }
        }
        .sheet(isPresented: $showNotionTokenView) {
            NotionTokenView(token: $notionToken)
                .onChange(of: notionToken) { newValue in
                    // Обновляем локальное состояние при изменении
                    notionToken = newValue
                }
                .onDisappear {
                    // Обновляем из UserDefaults на всякий случай
                    notionToken = UserDefaults.standard.string(forKey: "notionToken") ?? ""
                }
        }
    }
    
    private var githubTokenStatus: String {
        if githubToken.isEmpty {
            return "Не настроен"
        } else {
            return "Подключен ✓"
        }
    }
    
    private var notionTokenStatus: String {
        if notionToken.isEmpty {
            return "Не настроен"
        } else {
            return "Подключен ✓"
        }
    }
}

struct MCPToolRow: View {
    let icon: String
    let name: String
    let tools: [String]
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(.blue)
                Text(name)
                    .fontWeight(.semibold)
                Spacer()
                Button(action: { isExpanded.toggle() }) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                }
            }
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(tools, id: \.self) { tool in
                        HStack {
                            Image(systemName: "function")
                                .font(.caption)
                                .foregroundColor(.green)
                            Text(tool)
                                .font(.caption)
                                .monospaced()
                            Spacer()
                        }
                        .padding(.leading)
                    }
                }
                .transition(.slide)
            }
        }
    }
}

#Preview {
    SettingsView()
}
