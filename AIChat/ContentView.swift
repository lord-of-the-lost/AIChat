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
    
    var body: some View {
        NavigationStack {
            if isKeyValid {
                if isGitHubTokenValid && githubToken.count >= 40 && (githubToken.hasPrefix("ghp_") || githubToken.hasPrefix("github_pat_") || githubToken.hasPrefix("gho_") || githubToken.hasPrefix("ghu_") || githubToken.hasPrefix("ghs_") || githubToken.hasPrefix("ghr_")) {
                    ChatView(apiKey: apiKey, githubToken: githubToken)
                } else {
                    GitHubTokenView(githubToken: $githubToken, isTokenValid: $isGitHubTokenValid)
                }
            } else {
                APIKeyView(apiKey: $apiKey, isValid: $isKeyValid)
            }
        }
    }
}

#Preview {
    StartView()
}
