import Foundation

struct SwiftTestResult {
    let success: Bool
    let testCode: String
    let output: String
    let error: String
    let executionTime: TimeInterval
}

struct SwiftTestSuite {
    let sourceCode: String
    let testCode: String
    let testResults: [TestResult]
    let allTestsPassed: Bool
    let totalTests: Int
    let passedTests: Int
    let failedTests: Int
}

struct TestResult {
    let testName: String
    let passed: Bool
    let output: String
    let error: String?
    let executionTime: TimeInterval
}

final class SwiftTestGenerator {
    private let chatService: ChatService
    
    init(chatService: ChatService) {
        self.chatService = chatService
    }
    
    func generateTests(for sourceCode: String) async -> SwiftTestResult {
        let startTime = Date()
        
        let prompt = """
        Создай ТОЛЬКО unit тесты для следующего Swift кода используя XCTest framework.
        НЕ создавай репозитории, НЕ создавай файлы, НЕ используй GitHub.
        ТОЛЬКО код тестов.
        
        Код для тестирования:
        \(sourceCode)
        
        Создай ТОЛЬКО код тестов. Пример:
        
        import XCTest
        
        class SimpleCalculatorTests: XCTestCase {
            func testAdd() {
                let calculator = SimpleCalculator()
                XCTAssertEqual(calculator.add(2, 3), 5, "Сложение 2 + 3 должно равняться 5")
            }
            
            func testSubtract() {
                let calculator = SimpleCalculator()
                XCTAssertEqual(calculator.subtract(5, 3), 2, "Вычитание 5 - 3 должно равняться 2")
            }
        }
        
        ВАЖНО: 
        - ТОЛЬКО код тестов, ничего больше
        - Используй XCTest framework
        - НЕ используй XCTMain или allTests
        - НЕ создавай репозитории
        - НЕ используй GitHub
        - НЕ добавляй сложные конструкции
        - Только простые XCTAssertEqual тесты
        - Имена методов тестов должны начинаться с "test"
        - Тестируй ВСЕ публичные методы класса
        - Включай edge cases и граничные условия
        - Для каждого метода создавай несколько тестов с разными сценариями
        """
        
        do {
            let message = ChatMessage(author: .user, content: prompt, isUser: true)
            let response = await chatService.sendMessage([message])
            
            let testCode = extractSwiftCode(from: response ?? "")
            
            if testCode.isEmpty {
                return SwiftTestResult(
                    success: false,
                    testCode: "",
                    output: "",
                    error: "AI не сгенерировал тесты или создал репозиторий вместо тестов",
                    executionTime: Date().timeIntervalSince(startTime)
                )
            }
            
            return SwiftTestResult(
                success: true,
                testCode: testCode,
                output: "Тесты успешно сгенерированы",
                error: "",
                executionTime: Date().timeIntervalSince(startTime)
            )
        } catch {
            return SwiftTestResult(
                success: false,
                testCode: "",
                output: "",
                error: "Ошибка генерации тестов: \(error.localizedDescription)",
                executionTime: Date().timeIntervalSince(startTime)
            )
        }
    }
    
    private func extractSwiftCode(from text: String) -> String {
        // Проверяем, не является ли ответ markdown с репозиторием
        if text.contains("✅ Репозиторий успешно создан") || 
           text.contains("📁 Название:") || 
           text.contains("🔗 URL:") ||
           text.contains("📋 Описание:") {
            return ""
        }
        
        // Ищем код в блоках ```swift или ```
        let patterns = [
            "```swift\\s*([\\s\\S]*?)\\s*```",
            "```\\s*([\\s\\S]*?)\\s*```"
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
                let range = Range(match.range(at: 1), in: text)!
                let extracted = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !extracted.isEmpty {
                    return extracted
                }
            }
        }
        
        // Если не нашли блоки кода, проверяем на наличие Swift кода
        if text.contains("import XCTest") || text.contains("class") && text.contains("XCTestCase") {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // Если ничего не нашли, возвращаем пустую строку
        return ""
    }
    
    private func cleanSourceCode(_ code: String) -> String {
        // Удаляем лишний текст в начале
        let lines = code.components(separatedBy: .newlines)
        var cleanedLines: [String] = []
        var foundCode = false
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Пропускаем пустые строки и комментарии в начале
            if !foundCode && (trimmed.isEmpty || trimmed.hasPrefix("//") || trimmed.lowercased().contains("протестируй") || trimmed.lowercased().contains("проверь")) {
                continue
            }
            
            // Если нашли класс, struct, enum, func, let, var - начинаем код
            if trimmed.hasPrefix("class ") || trimmed.hasPrefix("struct ") || trimmed.hasPrefix("enum ") || 
               trimmed.hasPrefix("func ") || trimmed.hasPrefix("let ") || trimmed.hasPrefix("var ") || 
               trimmed.hasPrefix("import ") {
                foundCode = true
            }
            
            if foundCode {
                cleanedLines.append(line)
            }
        }
        
        return cleanedLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
