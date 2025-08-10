//
//  APIKeyView.swift
//  AIChat
//
//  Created by Николай Игнатов on 10.08.2025.
//

import SwiftUI

struct APIKeyView: View {
    @Binding var apiKey: String
    @Binding var isValid: Bool
    @State private var isChecking = false
    @State private var error: String?
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Введите API ключ OpenAI")
                .font(.title2)
            
            TextField("sk-...", text: $apiKey)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding(.horizontal)
            
            if let error = error {
                Text(error).foregroundColor(.red)
            }
            
            Button {
                checkAPIKey()
            } label: {
                if isChecking {
                    ProgressView()
                } else {
                    Text("Продолжить")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(apiKey.isEmpty)
        }
        .padding()
    }
    
    private func checkAPIKey() {
        isChecking = true
        error = nil
        
        Task {
            let success = await ChatService(apiKey: apiKey).validateKey()
            DispatchQueue.main.async {
                isChecking = false
                if success {
                    UserDefaults.standard.set(apiKey, forKey: "apiKey")
                    isValid = true
                } else {
                    error = "Ключ недействителен"
                }
            }
        }
    }
}
