//
//  MacChatViewModel.swift
//  AIChatMac
//
//  Created by Николай Игнатов on 19.08.2025.
//

import Foundation

@MainActor
final class MacChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var inputText = ""
    @Published var isLoading = false
    @Published var isExecutingCode = false
    @Published var isTestingCode = false
    @Published var lastExecutionResult: SwiftExecutionResult?
    @Published var lastTestResult: TestOrchestrationResult?
    @Published var lastReviewResult: CodeReviewResult?
    @Published var dockerDiagnostics: String?
    @Published var executionDiagnostics: String?
    @Published var githubToken: String
    @Published var reviewProgress: Double = 0.0
    @Published var isReviewing = false
    
    // AI параметры для тестирования
    @Published var aiTemperature: Double = 0.7
    @Published var aiMaxTokens: Int = 4000
    @Published var showAISettings = false
    
    private let chatService: ChatService
    private let swiftExecutionService: SwiftExecutionService
    private let testOrchestrator: SwiftTestOrchestrator
    
    init(apiKey: String, githubToken: String = "") {
        self.chatService = ChatService(apiKey: apiKey, githubToken: githubToken)
        self.swiftExecutionService = SwiftExecutionService()
        self.testOrchestrator = SwiftTestOrchestrator(chatService: chatService, swiftExecutionService: swiftExecutionService)
        self.githubToken = githubToken
    }
    
    func sendUserMessage() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        let userMessage = ChatMessage(author: .user, content: trimmed, isUser: true)
        messages.append(userMessage)
        inputText = ""
        
        processMessage(userMessage: userMessage)
    }
    
    func clearChat() {
        messages.removeAll()
        lastExecutionResult = nil
        lastTestResult = nil
        lastReviewResult = nil
        dockerDiagnostics = nil
        executionDiagnostics = nil
        reviewProgress = 0.0
        isReviewing = false
    }
    
    func cleanupOldMessages() {
        let maxMessages = 30
        if messages.count > maxMessages {
            let messagesToRemove = messages.count - maxMessages
            messages.removeFirst(messagesToRemove)
            print("🧹 Удалено \(messagesToRemove) старых сообщений")
        }
    }
    
    func updateReviewProgress(_ progress: Double) {
        reviewProgress = progress
    }
    
    func startReview() {
        isReviewing = true
        reviewProgress = 0.0
    }
    
    func finishReview() {
        isReviewing = false
        reviewProgress = 1.0
    }
    
    func updateAITemperature(_ temperature: Double) {
        aiTemperature = temperature
        // Обновляем параметры в ChatService
        chatService.updateAIParameters(temperature: temperature, maxTokens: aiMaxTokens)
    }
    
    func updateAIMaxTokens(_ maxTokens: Int) {
        aiMaxTokens = maxTokens
        // Обновляем параметры в ChatService
        chatService.updateAIParameters(temperature: aiTemperature, maxTokens: maxTokens)
    }
    
    func runDockerDiagnostics() {
        // Очищаем другие диагностики
        executionDiagnostics = nil
        Task {
            let diagnostics = await DockerDiagnostics.diagnoseDockerIssues()
            dockerDiagnostics = diagnostics
        }
    }
    
    func runExecutionDiagnostics() {
        // Очищаем другие диагностики
        dockerDiagnostics = nil
        Task {
            let diagnostics = await generateExecutionDiagnostics()
            executionDiagnostics = diagnostics
        }
    }
    
    private func generateExecutionDiagnostics() async -> String {
        var report = "🔍 ДИАГНОСТИКА ВЫПОЛНЕНИЯ SWIFT КОДА\n\n"
        
        // 1. Проверяем MCP Docker сервис
        report += "🐳 MCP Docker сервис:\n"
        let mcpService = MCPDockerService()
        let mcpAvailable = await mcpService.checkHealth()
        if mcpAvailable {
            report += "  ✅ MCP Docker доступен на localhost:5002\n"
        } else {
            report += "  ❌ MCP Docker недоступен (Connection refused)\n"
            report += "  ℹ️ Это нормально - используется fallback\n"
        }
        report += "\n"
        
        // 2. Проверяем Native Swift
        report += "🍎 Native Swift исполнитель:\n"
        let possibleSwiftPaths = [
            "/usr/bin/swift",
            "/usr/local/bin/swift", 
            "/opt/homebrew/bin/swift"
        ]
        
        for path in possibleSwiftPaths {
            let exists = FileManager.default.fileExists(atPath: path)
            report += "  \(path): \(exists ? "✅ Найден" : "❌ Не найден")\n"
            
            if exists {
                // Проверяем версию Swift
                let process = Process()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = ["--version"]
                
                let pipe = Pipe()
                process.standardOutput = pipe
                
                do {
                    try process.run()
                    process.waitUntilExit()
                    
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    if let version = String(data: data, encoding: .utf8) {
                        report += "    Версия: \(version.trimmingCharacters(in: .whitespacesAndNewlines))\n"
                    }
                } catch {
                    report += "    Ошибка проверки версии: \(error.localizedDescription)\n"
                }
                break
            }
        }
        report += "\n"
        
        // 3. Проверяем Sandbox статус
        report += "🔒 Sandbox статус:\n"
        let entitlementsPath = Bundle.main.path(forResource: "AIChatMac", ofType: "entitlements")
        if let entitlementsPath = entitlementsPath {
            report += "  📄 Entitlements файл: найден\n"
            do {
                let content = try String(contentsOfFile: entitlementsPath)
                if content.contains("<false/>") {
                    report += "  🔓 App Sandbox: ОТКЛЮЧЕН (правильно)\n"
                } else {
                    report += "  🔒 App Sandbox: ВКЛЮЧЕН (может быть проблема)\n"
                }
            } catch {
                report += "  ❌ Не удалось прочитать entitlements\n"
            }
        } else {
            report += "  ❌ Entitlements файл не найден\n"
        }
        report += "\n"
        
        // 4. Тестовое выполнение
        report += "🧪 Тестовое выполнение:\n"
        let testCode = "print(\"Диагностический тест\")\nlet x = 2 + 2\nprint(\"2 + 2 = \\(x)\")"
        let executor = NativeSwiftExecutor()
        let result = await executor.executeSwiftCode(testCode)
        
        report += "  Код: print(\"Диагностический тест\"); let x = 2 + 2; print(\"2 + 2 = \\(x)\")\n"
        report += "  Результат: \(result.success ? "✅ Успех" : "❌ Ошибка")\n"
        if result.success {
            report += "  Вывод: \(result.output.trimmingCharacters(in: .whitespacesAndNewlines))\n"
        } else {
            report += "  Ошибка: \(result.error)\n"
        }
        report += "  Время: \(String(format: "%.3f", result.executionTime))s\n"
        
        return report
    }
    
    private func processMessage(userMessage: ChatMessage) {
        Task {
            isLoading = true
            
            // Очищаем старые сообщения для избежания переполнения
            cleanupOldMessages()
            
            // Обновляем параметры AI перед отправкой сообщения
            chatService.updateAIParameters(temperature: aiTemperature, maxTokens: aiMaxTokens)
            print("🤖 AI параметры обновлены: Temperature = \(aiTemperature), MaxTokens = \(aiMaxTokens)")
            
            // Проверяем, есть ли GitHub PR URL в сообщении
            if let prURL = extractGitHubPRURL(from: userMessage.content) {
                await reviewGitHubPR(prURL: prURL)
            } else {
                // Проверяем, есть ли Swift код в сообщении
                let containsSwiftCode = detectSwiftCode(in: userMessage.content)
                let shouldTest = shouldRunTests(for: userMessage.content)
                
                if containsSwiftCode && shouldTest {
                    // Если обнаружен Swift код и запрошено тестирование
                    await runSwiftTests(from: userMessage.content)
                } else if containsSwiftCode {
                    // Если обнаружен Swift код, выполняем его
                    await executeSwiftCode(from: userMessage.content)
                }
                
                // Отправляем все сообщения через AI агент
                print("📤 Отправляем \(messages.count) сообщений в AI...")
                let result = await chatService.sendMessage(messages)
                
                if let result = result {
                    print("✅ Получен ответ от AI (\(result.count) символов)")
                    let aiMessage = ChatMessage(author: .aiAgent, content: result, isUser: false)
                    messages.append(aiMessage)
                } else {
                    print("❌ Не получен ответ от AI")
                    let errorMessage = ChatMessage(author: .system, content: "❌ Не удалось получить ответ от AI. Попробуйте повторить запрос.", isUser: false)
                    messages.append(errorMessage)
                }
            }
            
            isLoading = false
        }
    }
    
    private func extractGitHubPRURL(from text: String) -> String? {
        // Ищем GitHub PR URL в тексте
        let pattern = "https://github\\.com/[^/]+/[^/]+/pull/\\d+"
        let regex = try? NSRegularExpression(pattern: pattern)
        
        if let match = regex?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
            let urlRange = Range(match.range, in: text)!
            return String(text[urlRange])
        }
        
        return nil
    }
    
    private func reviewGitHubPR(prURL: String) async {
        // Начинаем ревью
        startReview()
        
        // Создаем сервисы для ревью
        let githubPRService = GitHubPRService(githubToken: githubToken)
        let codeReviewService = CodeReviewService(aiService: chatService, githubPRService: githubPRService)
        
        // Выполняем ревью с отслеживанием прогресса
        let result = await codeReviewService.reviewPullRequest(from: prURL, progressCallback: { progress in
            Task { @MainActor in
                self.updateReviewProgress(progress)
            }
        })
        
        // Завершаем ревью
        finishReview()
        
        switch result {
        case .success(let reviewResult):
            lastReviewResult = reviewResult
            
            // Добавляем результат ревью в чат
            let reviewMessage = formatReviewResult(reviewResult)
            let systemMessage = ChatMessage(author: .system, content: reviewMessage, isUser: false)
            messages.append(systemMessage)
            
        case .failure(let error):
            let errorMessage = "❌ Ошибка при ревью PR: \(error.localizedDescription)"
            let errorChatMessage = ChatMessage(author: .system, content: errorMessage, isUser: false)
            messages.append(errorChatMessage)
        }
    }
    
    private func formatReviewResult(_ result: CodeReviewResult) -> String {
        var message = """
        ## 🔍 Ревью Pull Request завершено!
        
        ### 📋 Информация о PR:
        - **Название:** \(result.pullRequest.title)
        - **Автор:** \(result.pullRequest.user.login)
        - **Номер:** #\(result.pullRequest.number)
        - **Ветка:** \(result.pullRequest.head.ref) → \(result.pullRequest.base.ref)
        - **Изменения:** +\(result.pullRequest.additions) -\(result.pullRequest.deletions) в \(result.pullRequest.changedFiles) файлах
        
        ### 📊 Результаты ревью:
        - **Общая оценка:** \(result.review.overallScore)/100
        - **Критических проблем:** \(result.review.issues.filter { $0.severity == .critical }.count)
        - **Высокого приоритета:** \(result.review.issues.filter { $0.severity == .high }.count)
        - **Среднего приоритета:** \(result.review.issues.filter { $0.severity == .medium }.count)
        - **Низкого приоритета:** \(result.review.issues.filter { $0.severity == .low }.count)
        - **Предложений:** \(result.review.suggestions.count)
        
        ### 🚨 Созданные Issues:
        """
        
        if result.createdIssues.isEmpty {
            message += "\n- Проблем не обнаружено, issues не созданы"
        } else {
            for issue in result.createdIssues {
                message += "\n- [Issue #\(issue.number)](\(issue.htmlUrl)): \(issue.title)"
            }
        }
        
        message += """
        
        ### 💬 Комментарий к PR:
        - \(result.commentAdded ? "✅ Добавлен" : "❌ Не добавлен")
        
        ### 📝 Краткое резюме:
        \(result.review.summary)
        
        ---
        *Ревью выполнено автоматически с помощью AI*
        """
        
        return message
    }
    
    private func detectSwiftCode(in text: String) -> Bool {
        let swiftKeywords = ["func ", "let ", "var ", "import ", "print(", "class ", "struct ", "enum "]
        let lowerText = text.lowercased()
        
        return swiftKeywords.contains { keyword in
            lowerText.contains(keyword)
        }
    }
    
    private func shouldRunTests(for text: String) -> Bool {
        let testKeywords = ["тест", "test", "проверь", "проверить", "unit", "юнит"]
        let lowerText = text.lowercased()
        
        return testKeywords.contains { keyword in
            lowerText.contains(keyword)
        }
    }
    
    private func executeSwiftCode(from text: String) async {
        isExecutingCode = true
        
        // Извлекаем Swift код из сообщения
        let extractedCode = extractSwiftCode(from: text)
        
        if !extractedCode.isEmpty {
            let result = await swiftExecutionService.executeSwiftCode(extractedCode)
            lastExecutionResult = result
            
            // Добавляем результат выполнения в чат
            let resultMessage = formatExecutionResult(result)
            let systemMessage = ChatMessage(author: .system, content: resultMessage, isUser: false)
            messages.append(systemMessage)
        }
        
        isExecutingCode = false
    }
    
    private func runSwiftTests(from text: String) async {
        isTestingCode = true
        
        // Извлекаем Swift код из сообщения
        let extractedCode = extractSwiftCode(from: text)
        
        if !extractedCode.isEmpty {
            let result = await testOrchestrator.orchestrateTesting(for: extractedCode)
            lastTestResult = result
            
            // Добавляем результат тестирования в чат
            let resultMessage = formatTestResult(result)
            let systemMessage = ChatMessage(author: .system, content: resultMessage, isUser: false)
            messages.append(systemMessage)
        }
        
        isTestingCode = false
    }
    
    private func extractSwiftCode(from text: String) -> String {
        // Ищем код в блоках ```swift или просто ```
        let patterns = [
            "```swift\\n([\\s\\S]*?)```",
            "```\\n([\\s\\S]*?)```",
            // Если нет блоков, берем все содержимое как код
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
                let range = Range(match.range(at: 1), in: text)!
                return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        
        // Если нет блоков кода, проверяем на наличие Swift ключевых слов
        let swiftKeywords = ["func ", "let ", "var ", "import ", "print(", "class ", "struct ", "enum "]
        let lowerText = text.lowercased()
        
        if swiftKeywords.contains(where: { lowerText.contains($0) }) {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        return ""
    }
    
    private func formatExecutionResult(_ result: SwiftExecutionResult) -> String {
        var formatted = "## 🔧 Результат выполнения Swift кода\n\n"
        
        formatted += "**Статус:** "
        formatted += result.success ? "✅ Успешно" : "❌ Ошибка"
        formatted += "\n\n"
        
        formatted += "**Код:**\n```swift\n\(result.code)\n```\n\n"
        
        if !result.output.isEmpty {
            formatted += "**Результат:**\n```\n\(result.output)\n```\n\n"
        }
        
        if !result.error.isEmpty {
            formatted += "**Ошибка:**\n```\n\(result.error)\n```\n\n"
        }
        
        formatted += "**Время выполнения:** \(String(format: "%.2f", result.executionTime))s"
        
        return formatted
    }
    
    private func formatTestResult(_ result: TestOrchestrationResult) -> String {
        var formatted = "🧪 РЕЗУЛЬТАТ АВТОМАТИЧЕСКОГО ТЕСТИРОВАНИЯ\n\n"
        
        formatted += "Статус: "
        formatted += result.success ? "✅ Все тесты прошли успешно" : "❌ Тесты не прошли"
        formatted += "\n\n"
        
        formatted += "Итераций: \(result.totalIterations)\n"
        formatted += "Общее время: \(String(format: "%.2f", result.totalExecutionTime))s\n\n"
        
        if let error = result.error {
            formatted += "Ошибка: \(error)\n\n"
        }
        
        formatted += "Финальный код:\n\(result.finalSourceCode)\n\n"
        
        formatted += "Сгенерированные тесты:\n\(result.finalTestCode)\n\n"
        
        // Детали по итерациям
        formatted += "Детали итераций:\n"
        for (index, iteration) in result.iterations.enumerated() {
            formatted += "\nИтерация \(index + 1):\n"
            formatted += "- Тестов: \(iteration.testSuite.totalTests)\n"
            formatted += "- Успешно: \(iteration.testSuite.passedTests)\n"
            formatted += "- Неудачно: \(iteration.testSuite.failedTests)\n"
            
            if let fixResult = iteration.fixResult {
                formatted += "- Код исправлен: \(fixResult.success ? "Да" : "Нет")\n"
                if !fixResult.explanation.isEmpty {
                    formatted += "- Объяснение: \(fixResult.explanation)\n"
                }
            }
        }
        
        return formatted
    }
}
