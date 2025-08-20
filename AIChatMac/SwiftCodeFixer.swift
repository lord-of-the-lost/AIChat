import Foundation

struct SwiftFixResult {
    let success: Bool
    let fixedCode: String
    let explanation: String
    let error: String
    let executionTime: TimeInterval
}

final class SwiftCodeFixer {
    private let chatService: ChatService
    
    init(chatService: ChatService) {
        self.chatService = chatService
    }
    
    func fixCode(sourceCode: String, testCode: String, testOutput: String, testErrors: String) async -> SwiftFixResult {
        let startTime = Date()
        
        let prompt = """
        Исправь следующий Swift код на основе результатов тестов.
        
        Исходный код:
        \(sourceCode)
        
        Тесты:
        \(testCode)
        
        Результаты выполнения тестов:
        \(testOutput)
        
        Ошибки тестов:
        \(testErrors)
        
        Проанализируй ошибки и исправь код так, чтобы все тесты прошли успешно.
        Верни только исправленный код без дополнительных комментариев.
        """
        
        do {
            let message = ChatMessage(author: .user, content: prompt, isUser: true)
            let response = await chatService.sendMessage([message])
            let fixedCode = extractSwiftCode(from: response ?? "")
            
            if fixedCode.isEmpty {
                return SwiftFixResult(
                    success: false,
                    fixedCode: sourceCode,
                    explanation: "Не удалось исправить код",
                    error: "Пустой ответ от AI",
                    executionTime: Date().timeIntervalSince(startTime)
                )
            }
            
            return SwiftFixResult(
                success: true,
                fixedCode: fixedCode,
                explanation: "Код исправлен на основе результатов тестов",
                error: "",
                executionTime: Date().timeIntervalSince(startTime)
            )
        } catch {
            return SwiftFixResult(
                success: false,
                fixedCode: sourceCode,
                explanation: "Ошибка при исправлении кода",
                error: error.localizedDescription,
                executionTime: Date().timeIntervalSince(startTime)
            )
        }
    }
    
    private func extractSwiftCode(from text: String) -> String {
        // Ищем код в блоках ```swift или ```
        let patterns = [
            "```swift\\s*([\\s\\S]*?)\\s*```",
            "```\\s*([\\s\\S]*?)\\s*```"
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
                let range = Range(match.range(at: 1), in: text)!
                return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        
        // Если не нашли блоки кода, возвращаем весь текст
        return text
    }
}
