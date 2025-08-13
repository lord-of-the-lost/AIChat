//
//  ChatView.swift
//  AIChat
//
//  Created by Николай Игнатов on 10.08.2025.
//

import SwiftUI
import MarkdownUI

struct ChatView: View {
    @StateObject private var viewModel: ChatViewModel
    
    init(apiKey: String) {
        _viewModel = StateObject(wrappedValue: ChatViewModel(apiKey: apiKey))
    }
    
    var body: some View {
        VStack {
            ScrollView {
                ForEach(viewModel.messages) { message in
                    VStack(alignment: message.isUser ? .trailing : .leading) {
                        Text(message.author.rawValue)
                            .font(.caption)
                            .foregroundColor(.gray)
                        
                        if message.isUser {
                            Text(message.content)
                                .padding()
                                .background(Color.blue.opacity(0.2))
                                .cornerRadius(8)
                        } else {
                            Markdown(message.content)
                                .padding()
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(8)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: message.isUser ? .trailing : .leading)
                    .padding(.vertical, 2)
                }
                
                if viewModel.isLoading {
                    HStack {
                        ProgressView()
                        Text(viewModel.currentAgent == .gptDeveloper ? "Developer думает…" : "Reviewer думает…")
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
    }
}
