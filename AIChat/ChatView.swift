//
//  ChatView.swift
//  AIChat
//
//  Created by Николай Игнатов on 10.08.2025.
//

import SwiftUI
import MarkdownUI

struct ChatView: View {
    let apiKey: String
    @State private var messages: [ChatMessage] = []
    @State private var inputText = ""
    @State private var isLoading = false
    private var service: ChatService { ChatService(apiKey: apiKey) }
    
    var body: some View {
        VStack {
            ScrollView {
                ForEach(messages) { message in
                    VStack(alignment: message.isUser ? .trailing : .leading) {
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
                
                if isLoading {
                    HStack {
                        ProgressView()
                        Text("Модель печатает…")
                    }
                    .padding()
                }
            }
            
            HStack {
                TextField("Ваш вопрос...", text: $inputText)
                    .textFieldStyle(.roundedBorder)
                
                Button("Отправить") {
                    sendMessage()
                }
                .disabled(inputText.isEmpty || isLoading)
            }
            .padding()
        }
        .navigationTitle("Чат с GPT")
    }
    
    func sendMessage() {
        let userMessage = ChatMessage(content: inputText, isUser: true)
        messages.append(userMessage)
        inputText = ""
        isLoading = true
        
        Task {
            if let reply = await service.sendMessage(messages: messages) {
                messages.append(ChatMessage(content: reply, isUser: false))
            }
            isLoading = false
        }
    }
}
