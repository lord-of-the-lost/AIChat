//
//  NotionTokenView.swift
//  AIChat
//
//  Created by Николай Игнатов on 13.08.2025.
//

import SwiftUI

struct NotionTokenView: View {
    @Binding var token: String
    @Environment(\.dismiss) private var dismiss
    @State private var tempToken: String = ""
    @State private var showInfo = false
    @State private var showSaveConfirmation = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Заголовок
                VStack(spacing: 8) {
                    Image(systemName: "book.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.blue)
                    
                    Text("Notion Integration Token")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("Подключите ваш Notion workspace для работы с MCP")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top)
                
                // Поле ввода токена
                VStack(alignment: .leading, spacing: 8) {
                    Text("Integration Token")
                        .font(.headline)
                    
                    SecureField("ntn_...", text: $tempToken)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(
                                    tempToken.isEmpty ? Color.clear : 
                                    isValidNotionToken(tempToken) ? Color.green : Color.red,
                                    lineWidth: 1
                                )
                        )
                        .onAppear {
                            tempToken = token
                        }
                    
                    HStack {
                        Text("Вставьте Internal Integration Token из настроек Notion")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        if !tempToken.isEmpty {
                            Image(systemName: isValidNotionToken(tempToken) ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(isValidNotionToken(tempToken) ? .green : .red)
                                .font(.caption)
                        }
                    }
                }
                
                // Инструкция
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("📋 Как получить токен:")
                            .font(.headline)
                        Spacer()
                        Button(action: { showInfo.toggle() }) {
                            Image(systemName: showInfo ? "chevron.up" : "chevron.down")
                        }
                    }
                    
                    if showInfo {
                        VStack(alignment: .leading, spacing: 8) {
                            instructionStep("1.", "Перейдите на https://www.notion.so/my-integrations")
                            instructionStep("2.", "Нажмите \"+ New integration\"")
                            instructionStep("3.", "Укажите название и выберите workspace")
                            instructionStep("4.", "Нажмите \"Submit\"")
                            instructionStep("5.", "Скопируйте \"Internal Integration Token\"")
                            instructionStep("6.", "Дайте доступ к нужным страницам в Notion")
                        }
                        .transition(.slide)
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)
                
                Spacer()
                
                // Кнопки
                HStack(spacing: 16) {
                    Button("Отмена") {
                        dismiss()
                    }
                    .foregroundColor(.secondary)
                    
                    Button("Сохранить") {
                        token = tempToken
                        UserDefaults.standard.set(tempToken, forKey: "notionToken")
                        showSaveConfirmation = true
                        
                        // Автоматически закрываем через короткое время
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            dismiss()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(tempToken.isEmpty || !isValidNotionToken(tempToken))
                }
            }
            .padding()
            .navigationTitle("Notion MCP")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Готово") {
                        dismiss()
                    }
                }
            }
        }
        .alert("Токен сохранен!", isPresented: $showSaveConfirmation) {
            Button("OK") { }
        } message: {
            Text("Notion токен успешно сохранен и готов к использованию")
        }
    }
    
    private func isValidNotionToken(_ token: String) -> Bool {
        return token.hasPrefix("ntn_") && token.count > 10
    }
    
    private func instructionStep(_ number: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(number)
                .fontWeight(.semibold)
                .foregroundColor(.blue)
            Text(text)
                .font(.caption)
            Spacer()
        }
    }
}

#Preview {
    NotionTokenView(token: .constant(""))
}
