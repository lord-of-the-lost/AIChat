//
//  ChatView.swift
//  AIChat
//
//  Created by Николай Игнатов on 10.08.2025.
//

import SwiftUI

struct ChatView: View {
    @StateObject private var viewModel: ChatViewModel
    
    init(apiKey: String, githubToken: String) {
        _viewModel = StateObject(wrappedValue: ChatViewModel(apiKey: apiKey, githubToken: githubToken))
    }
    
    var body: some View {
        VStack {
            ScrollView {
                ForEach(viewModel.messages) { message in
                    VStack(alignment: message.isUser ? .trailing : .leading) {
                        Text(message.author.rawValue)
                            .font(.caption)
                            .foregroundColor(.gray)
                        
                        Text(message.content)
                            .padding()
                            .background(message.isUser ? Color.blue.opacity(0.2) : Color.gray.opacity(0.1))
                            .cornerRadius(8)
                    }
                    .frame(maxWidth: .infinity, alignment: message.isUser ? .trailing : .leading)
                    .padding(.vertical, 2)
                }
                
                if viewModel.isLoading {
                    HStack {
                        ProgressView()
                        Text(loadingText)
                    }
                    .padding()
                }
            }
            
            HStack {
                TextField("Ваш вопрос...", text: $viewModel.inputText)
                    .textFieldStyle(.roundedBorder)
                
                Button("Отправить") {
                    viewModel.sendUserMessage()
                }
                .disabled(viewModel.inputText.isEmpty || viewModel.isLoading)
            }
            .padding()
        }
        .navigationTitle("Чат с агентами")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    // Сбросить GitHub токен и вернуться к настройкам
                    UserDefaults.standard.removeObject(forKey: "githubToken")
                    // Здесь нужно обновить состояние приложения
                }) {
                    Image(systemName: "gear")
                }
            }
        }
    }
    
    private var loadingText: String {
        return "Обработка…"
    }
}
