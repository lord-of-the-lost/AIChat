//
//  ContentView.swift
//  AIChatMac
//
//  Created by Николай Игнатов on 19.08.2025.
//

import SwiftUI

// MARK: - MacStartView
struct MacStartView: View {
    @State private var apiKey: String = UserDefaults.standard.string(forKey: "apiKey") ?? ""
    @State private var isKeyValid = UserDefaults.standard.string(forKey: "apiKey") != nil && !UserDefaults.standard.string(forKey: "apiKey")!.isEmpty
    @State private var githubToken: String = UserDefaults.standard.string(forKey: "githubToken") ?? ""
    @State private var isGitHubTokenValid = UserDefaults.standard.string(forKey: "githubToken") != nil && !UserDefaults.standard.string(forKey: "githubToken")!.isEmpty
    
    var body: some View {
        NavigationSplitView {
            // Sidebar
            VStack {
                Image(systemName: "message.circle")
                    .font(.system(size: 40))
                    .foregroundColor(.blue)
                Text("AI Chat")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Divider()
                    .padding(.vertical)
                
                VStack(alignment: .leading, spacing: 8) {
                    Label("Функции:", systemImage: "list.bullet")
                        .font(.headline)
                    Label("Чат с AI", systemImage: "message")
                    Label("Выполнение Swift кода", systemImage: "swift")
                    Label("Работа с GitHub", systemImage: "folder")
                }
                .font(.caption)
                .foregroundColor(.secondary)
                
                Spacer()
            }
            .padding()
            .frame(minWidth: 200)
        } detail: {
            // Main content
            if isKeyValid && !apiKey.isEmpty {
                if isGitHubTokenValid && !githubToken.isEmpty && githubToken.count >= 40 && (githubToken.hasPrefix("ghp_") || githubToken.hasPrefix("github_pat_") || githubToken.hasPrefix("gho_") || githubToken.hasPrefix("ghu_") || githubToken.hasPrefix("ghs_") || githubToken.hasPrefix("ghr_")) {
                    MacChatView(apiKey: apiKey, githubToken: githubToken)
                } else {
                    MacGitHubTokenView(githubToken: $githubToken, isTokenValid: $isGitHubTokenValid)
                }
            } else {
                MacAPIKeyView(apiKey: $apiKey, isValid: $isKeyValid)
            }
        }
        .navigationSplitViewStyle(.balanced)
    }
}

// MARK: - MacAPIKeyView
struct MacAPIKeyView: View {
    @Binding var apiKey: String
    @Binding var isValid: Bool
    @State private var isValidating = false
    @State private var errorMessage = ""
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "key.fill")
                .font(.system(size: 60))
                .foregroundColor(.blue)
            
            Text("Настройка API ключа")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Введите ваш API ключ для продолжения")
                .font(.body)
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("API Ключ:")
                    .font(.headline)
                
                SecureField("Введите API ключ", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 400)
            }
            
            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.caption)
            }
            
            Button(action: validateAPI) {
                HStack {
                    if isValidating {
                        ProgressView()
                            .scaleEffect(0.7)
                    }
                    Text(isValidating ? "Проверка..." : "Проверить ключ")
                }
                .frame(minWidth: 120)
            }
            .disabled(apiKey.isEmpty || isValidating)
            .buttonStyle(.borderedProminent)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private func validateAPI() {
        isValidating = true
        errorMessage = ""
        
        Task {
            let service = ChatService(apiKey: apiKey)
            let isValidKey = await service.validateKey()
            
            await MainActor.run {
                isValidating = false
                if isValidKey {
                    UserDefaults.standard.set(apiKey, forKey: "apiKey")
                    isValid = true
                } else {
                    errorMessage = "Неверный API ключ. Проверьте правильность ввода."
                }
            }
        }
    }
}

// MARK: - MacGitHubTokenView  
struct MacGitHubTokenView: View {
    @Binding var githubToken: String
    @Binding var isTokenValid: Bool
    @State private var isValidating = false
    @State private var errorMessage = ""
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "folder.fill")
                .font(.system(size: 60))
                .foregroundColor(.orange)
            
            Text("Настройка GitHub токена")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Введите ваш GitHub токен для работы с репозиториями")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("GitHub Token:")
                    .font(.headline)
                
                SecureField("Введите GitHub токен", text: $githubToken)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 400)
                
                Text("Токен должен начинаться с ghp_, github_pat_, gho_, ghu_, ghs_ или ghr_")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.caption)
            }
            
            Button(action: validateGitHubToken) {
                HStack {
                    if isValidating {
                        ProgressView()
                            .scaleEffect(0.7)
                    }
                    Text(isValidating ? "Проверка..." : "Сохранить токен")
                }
                .frame(minWidth: 120)
            }
            .disabled(githubToken.isEmpty || isValidating)
            .buttonStyle(.borderedProminent)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private func validateGitHubToken() {
        isValidating = true
        errorMessage = ""
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if githubToken.count >= 40 && (githubToken.hasPrefix("ghp_") || githubToken.hasPrefix("github_pat_") || githubToken.hasPrefix("gho_") || githubToken.hasPrefix("ghu_") || githubToken.hasPrefix("ghs_") || githubToken.hasPrefix("ghr_")) {
                UserDefaults.standard.set(githubToken, forKey: "githubToken")
                isTokenValid = true
            } else {
                errorMessage = "Неверный формат токена. Убедитесь, что токен правильный."
            }
            isValidating = false
        }
    }
}

// MARK: - MacChatView
struct MacChatView: View {
    @StateObject private var viewModel: MacChatViewModel
    
    init(apiKey: String, githubToken: String) {
        _viewModel = StateObject(wrappedValue: MacChatViewModel(apiKey: apiKey, githubToken: githubToken))
    }
    
    var body: some View {
        HSplitView {
            // Левая панель - история чата
            VStack {
                HStack {
                    Text("История чата")
                        .font(.headline)
                    Spacer()
                    Button(action: viewModel.clearChat) {
                        Image(systemName: "trash")
                    }
                }
                .padding()
                
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(viewModel.messages) { message in
                            MessageRowView(message: message)
                        }
                    }
                    .padding(.horizontal)
                }
                
                Divider()
                
                // Поле ввода
                VStack {
                    HStack(alignment: .bottom) {
                        ExpandingTextEditor(
                            text: $viewModel.inputText,
                            placeholder: "Введите ваш вопрос или Swift код..."
                        )
                        
                        Button(action: viewModel.sendUserMessage) {
                            Image(systemName: "paperplane.fill")
                        }
                        .disabled(viewModel.inputText.isEmpty || viewModel.isLoading)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.return, modifiers: [.command])
                    }
                    
                    if viewModel.isLoading {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("Обработка...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
            }
            .frame(minWidth: 400)
            
            // Правая панель - результаты выполнения кода
            VStack {
                HStack {
                    Text("Результаты выполнения")
                        .font(.headline)
                    Spacer()
                    if viewModel.isExecutingCode {
                        ProgressView()
                            .scaleEffect(0.7)
                    }
                }
                .padding()
                
                ScrollView {
                    if let result = viewModel.lastExecutionResult {
                        ExecutionResultView(result: result)
                            .padding()
                    } else if let executionDiagnostics = viewModel.executionDiagnostics {
                        VStack(alignment: .leading) {
                            Text("🔍 Диагностика выполнения")
                                .font(.headline)
                                .foregroundColor(.blue)
                            
                            ScrollView {
                                Text(executionDiagnostics)
                                    .font(.system(.caption, design: .monospaced))
                                    .padding(8)
                                    .background(Color.gray.opacity(0.1))
                                    .cornerRadius(6)
                            }
                            
                            HStack {
                                Button("Обновить диагностику") {
                                    viewModel.runExecutionDiagnostics()
                                }
                                .buttonStyle(.borderedProminent)
                                
                                Button("Docker диагностика") {
                                    viewModel.runDockerDiagnostics()
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .padding()
                    } else if let dockerDiagnostics = viewModel.dockerDiagnostics {
                        VStack(alignment: .leading) {
                            Text("🔧 Диагностика Docker")
                                .font(.headline)
                                .foregroundColor(.orange)
                            
                            ScrollView {
                                Text(dockerDiagnostics)
                                    .font(.system(.caption, design: .monospaced))
                                    .padding(8)
                                    .background(Color.gray.opacity(0.1))
                                    .cornerRadius(6)
                            }
                            
                            HStack {
                                Button("Обновить Docker") {
                                    viewModel.runDockerDiagnostics()
                                }
                                .buttonStyle(.borderedProminent)
                                
                                Button("Общая диагностика") {
                                    viewModel.runExecutionDiagnostics()
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .padding()
                    } else {
                        VStack {
                            Image(systemName: "swift")
                                .font(.system(size: 40))
                                .foregroundColor(.orange)
                            Text("Здесь будут показаны результаты выполнения Swift кода")
                                .font(.body)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                            
                            VStack(spacing: 8) {
                                Button("🔍 Диагностика выполнения") {
                                    viewModel.runExecutionDiagnostics()
                                }
                                .buttonStyle(.borderedProminent)
                                
                                Button("🐳 Диагностика Docker") {
                                    viewModel.runDockerDiagnostics()
                                }
                                .buttonStyle(.bordered)
                            }
                            .padding(.top)
                        }
                        .padding()
                    }
                }
            }
            .frame(minWidth: 300)
        }
        .navigationTitle("AI Chat - Swift Playground")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: resetSettings) {
                    Image(systemName: "gear")
                }
            }
        }
    }
    
    private func resetSettings() {
        UserDefaults.standard.removeObject(forKey: "apiKey")
        UserDefaults.standard.removeObject(forKey: "githubToken")
        
        // Перезапускаем приложение
        if let window = NSApplication.shared.windows.first {
            window.contentView = NSHostingView(rootView: MacStartView())
        }
    }
}

// MARK: - MessageRowView
struct MessageRowView: View {
    let message: ChatMessage
    
    var body: some View {
        VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
            HStack {
                if !message.isUser {
                    Image(systemName: "cpu")
                        .foregroundColor(.blue)
                }
                
                Text(message.author.rawValue)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if message.isUser {
                    Image(systemName: "person.circle")
                        .foregroundColor(.green)
                }
            }
            
            HStack {
                if message.isUser {
                    Spacer()
                }
                
                VStack(alignment: .leading) {
                    Text(message.content)
                        .padding(12)
                        .background(message.isUser ? Color.blue.opacity(0.15) : Color.gray.opacity(0.1))
                        .cornerRadius(12)
                        .font(.system(.body, design: .default))
                }
                .frame(maxWidth: 300, alignment: message.isUser ? .trailing : .leading)
                
                if !message.isUser {
                    Spacer()
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - ExecutionResultView
struct ExecutionResultView: View {
    let result: SwiftExecutionResult
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Статус
            HStack {
                Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(result.success ? .green : .red)
                Text(result.success ? "Успешно выполнено" : "Ошибка выполнения")
                    .font(.headline)
                    .foregroundColor(result.success ? .green : .red)
            }
            
            // Код
            VStack(alignment: .leading, spacing: 4) {
                Text("Код:")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Text(result.code)
                    .font(.system(.body, design: .monospaced))
                    .padding(8)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(6)
            }
            
            // Вывод
            if !result.output.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Результат:")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    Text(result.output)
                        .font(.system(.body, design: .monospaced))
                        .padding(8)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(6)
                }
            }
            
            // Ошибки
            if !result.error.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ошибка:")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    Text(result.error)
                        .font(.system(.body, design: .monospaced))
                        .padding(8)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(6)
                }
            }
            
            // Время выполнения
            HStack {
                Text("Время выполнения:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("\(String(format: "%.2f", result.executionTime))s")
                    .font(.caption)
                    .fontWeight(.medium)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

#Preview {
    MacStartView()
}
