//
//  ContentView.swift
//  AIChat
//
//  Created by Николай Игнатов on 10.08.2025.
//

import SwiftUI

struct StartView: View {
    @State private var apiKey: String = UserDefaults.standard.string(forKey: "apiKey") ?? ""
    @State private var isKeyValid = false
    @State private var githubToken: String = UserDefaults.standard.string(forKey: "githubToken") ?? ""
    @State private var isGitHubTokenValid = false
    @State private var notionToken: String = UserDefaults.standard.string(forKey: "notionToken") ?? ""
    @State private var isNotionTokenValid = false
    
    var body: some View {
        NavigationStack {
            if isKeyValid {
                if isGitHubTokenValid && githubToken.count >= 40 && (githubToken.hasPrefix("ghp_") || githubToken.hasPrefix("github_pat_") || githubToken.hasPrefix("gho_") || githubToken.hasPrefix("ghu_") || githubToken.hasPrefix("ghs_") || githubToken.hasPrefix("ghr_")) {
                    if isNotionTokenValid && notionToken.hasPrefix("ntn_") {
                        ChatView(apiKey: apiKey, githubToken: githubToken, notionToken: notionToken)
                    } else {
                        NotionTokenView(token: $notionToken)
                            .onChange(of: notionToken) { newValue in
                                if newValue.hasPrefix("ntn_") {
                                    isNotionTokenValid = true
                                }
                            }
                            .onDisappear {
                                if notionToken.hasPrefix("ntn_") {
                                    isNotionTokenValid = true
                                }
                            }
                    }
                } else {
                    GitHubTokenView(githubToken: $githubToken, isTokenValid: $isGitHubTokenValid)
                        .onChange(of: githubToken) { newValue in
                            if newValue.count >= 40 {
                                let validPrefixes = ["ghp_", "github_pat_", "gho_", "ghu_", "ghs_", "ghr_"]
                                if validPrefixes.contains(where: { newValue.hasPrefix($0) }) {
                                    isGitHubTokenValid = true
                                }
                            }
                        }
                }
            } else {
                APIKeyView(apiKey: $apiKey, isValid: $isKeyValid)
            }
        }
        .onAppear {
            // Валидируем сохраненные токены при запуске
            if notionToken.hasPrefix("ntn_") {
                isNotionTokenValid = true
            }
            
            if githubToken.count >= 40 {
                let validPrefixes = ["ghp_", "github_pat_", "gho_", "ghu_", "ghs_", "ghr_"]
                if validPrefixes.contains(where: { githubToken.hasPrefix($0) }) {
                    isGitHubTokenValid = true
                }
            }
        }
    }
}

#Preview {
    StartView()
}
