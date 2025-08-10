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
    
    var body: some View {
        NavigationStack {
            if isKeyValid {
                ChatView(apiKey: apiKey)
            } else {
                APIKeyView(apiKey: $apiKey, isValid: $isKeyValid)
            }
        }
    }
}

#Preview {
    StartView()
}
