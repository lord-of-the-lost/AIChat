//
//  GitHubTokenView.swift
//  AIChat
//
//  Created by Николай Игнатов on 13.08.2025.
//

import SwiftUI

struct GitHubTokenView: View {
    @Binding var githubToken: String
    @Binding var isTokenValid: Bool
    @State private var isLoading = false
    @State private var errorMessage = ""
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "github")
                .font(.system(size: 60))
                .foregroundColor(.black)
            
            Text("GitHub MCP Интеграция")
                .font(.title)
                .fontWeight(.bold)
            
            Text("Для создания репозиториев через MCP необходимо настроить GitHub токен доступа")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("GitHub Personal Access Token")
                    .font(.headline)
                
                SecureField("ghp_xxxxxxxxxxxxxxxxxxxx", text: $githubToken)
                    .textFieldStyle(.roundedBorder)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                
                Text("Токен должен начинаться с 'ghp_', 'github_pat_', 'gho_', 'ghu_', 'ghs_' или 'ghr_' и содержать минимум 40 символов")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
            .padding(.horizontal)
            
            VStack(spacing: 12) {
                Button(action: validateToken) {
                    HStack {
                        if isLoading {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                        Text(isLoading ? "Проверка..." : "Проверить токен")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .disabled(githubToken.isEmpty || isLoading)
                
                if isTokenValid {
                    Button("Продолжить") {
                        UserDefaults.standard.set(githubToken, forKey: "githubToken")
                        isTokenValid = true // Убеждаемся, что токен валидный
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
            }
            .padding(.horizontal)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Как получить токен:")
                    .font(.headline)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("1. Перейдите на GitHub.com")
                    Text("2. Settings → Developer settings → Personal access tokens")
                    Text("3. Generate new token (classic)")
                    Text("4. Выберите scope: 'repo' (полный доступ к репозиториям)")
                    Text("5. Скопируйте токен и вставьте выше")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(10)
            .padding(.horizontal)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("MCP Возможности:")
                    .font(.headline)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("• Создание репозиториев")
                    Text("• Поиск репозиториев")
                    Text("• Получение информации о пользователе")
                    Text("• Полная интеграция с GitHub API")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            .padding()
            .background(Color.blue.opacity(0.1))
            .cornerRadius(10)
            .padding(.horizontal)
            
            Spacer()
        }
        .padding()
    }
    
    private func validateToken() {
        guard !githubToken.isEmpty else { return }
        
        // Проверяем базовый формат токена
        let validPrefixes = ["ghp_", "github_pat_", "gho_", "ghu_", "ghs_", "ghr_"]
        let hasValidPrefix = validPrefixes.contains { githubToken.hasPrefix($0) }
        
        guard hasValidPrefix && githubToken.count >= 40 else {
            errorMessage = "Токен должен начинаться с 'ghp_', 'github_pat_', 'gho_', 'ghu_', 'ghs_' или 'ghr_' и содержать минимум 40 символов"
            isTokenValid = false
            return
        }
        
        isLoading = true
        errorMessage = ""
        
        Task {
            let mcpService = MCPGitHubService(githubToken: githubToken)
            let result = await mcpService.getUserInfo()
            
            await MainActor.run {
                isLoading = false
                
                switch result {
                case .success(let user):
                    isTokenValid = true
                    errorMessage = ""
                case .failure(let error):
                    isTokenValid = false
                    errorMessage = "Ошибка: \(error.localizedDescription)"
                }
            }
        }
    }
}

#Preview {
    GitHubTokenView(
        githubToken: .constant(""),
        isTokenValid: .constant(false)
    )
}
