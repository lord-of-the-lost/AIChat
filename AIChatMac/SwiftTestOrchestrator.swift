import Foundation

struct TestIteration {
    let iteration: Int
    let sourceCode: String
    let testCode: String
    let testSuite: SwiftTestSuite
    let fixResult: SwiftFixResult?
    let timestamp: Date
}

struct TestOrchestrationResult {
    let success: Bool
    let finalSourceCode: String
    let finalTestCode: String
    let iterations: [TestIteration]
    let totalIterations: Int
    let totalExecutionTime: TimeInterval
    let finalTestSuite: SwiftTestSuite
    let error: String?
}

final class SwiftTestOrchestrator {
    private let testGenerator: SwiftTestGenerator
    private let testRunner: SwiftTestRunner
    private let codeFixer: SwiftCodeFixer
    
    private let maxIterations = 5 // Максимальное количество попыток исправления
    
    init(chatService: ChatService, swiftExecutionService: SwiftExecutionService) {
        self.testGenerator = SwiftTestGenerator(chatService: chatService)
        self.testRunner = SwiftTestRunner(swiftExecutionService: swiftExecutionService)
        self.codeFixer = SwiftCodeFixer(chatService: chatService)
    }
    
    func orchestrateTesting(for sourceCode: String) async -> TestOrchestrationResult {
        let startTime = Date()
        var iterations: [TestIteration] = []
        var currentSourceCode = sourceCode
        var currentTestCode = ""
        
        // Очищаем исходный код от лишнего текста
        let cleanedSourceCode = cleanSourceCode(sourceCode)
        currentSourceCode = cleanedSourceCode
        
        // Шаг 1: Генерируем тесты
        let testGenerationResult = await testGenerator.generateTests(for: cleanedSourceCode)
        
        if !testGenerationResult.success {
            return TestOrchestrationResult(
                success: false,
                finalSourceCode: currentSourceCode,
                finalTestCode: "",
                iterations: [],
                totalIterations: 0,
                totalExecutionTime: Date().timeIntervalSince(startTime),
                finalTestSuite: SwiftTestSuite(
                    sourceCode: currentSourceCode,
                    testCode: "",
                    testResults: [],
                    allTestsPassed: false,
                    totalTests: 0,
                    passedTests: 0,
                    failedTests: 0
                ),
                error: "Ошибка генерации тестов: \(testGenerationResult.error)"
            )
        }
        
        currentTestCode = testGenerationResult.testCode
        
        // Цикл тестирования и исправления
        for iteration in 1...maxIterations {
            // Выполняем тесты
            let testSuite = await testRunner.runTests(sourceCode: currentSourceCode, testCode: currentTestCode)
            
            // Создаем запись итерации
            let testIteration = TestIteration(
                iteration: iteration,
                sourceCode: currentSourceCode,
                testCode: currentTestCode,
                testSuite: testSuite,
                fixResult: nil,
                timestamp: Date()
            )
            
            iterations.append(testIteration)
            
            // Если все тесты прошли, завершаем
            if testSuite.allTestsPassed {
                return TestOrchestrationResult(
                    success: true,
                    finalSourceCode: currentSourceCode,
                    finalTestCode: currentTestCode,
                    iterations: iterations,
                    totalIterations: iteration,
                    totalExecutionTime: Date().timeIntervalSince(startTime),
                    finalTestSuite: testSuite,
                    error: nil
                )
            }
            
            // Если достигли максимального количества итераций, завершаем
            if iteration >= maxIterations {
                return TestOrchestrationResult(
                    success: false,
                    finalSourceCode: currentSourceCode,
                    finalTestCode: currentTestCode,
                    iterations: iterations,
                    totalIterations: iteration,
                    totalExecutionTime: Date().timeIntervalSince(startTime),
                    finalTestSuite: testSuite,
                    error: "Достигнуто максимальное количество попыток исправления (\(maxIterations))"
                )
            }
            
            // Исправляем код
            let fixResult = await codeFixer.fixCode(
                sourceCode: currentSourceCode,
                testCode: currentTestCode,
                testOutput: testSuite.testResults.map { $0.output }.joined(separator: "\n"),
                testErrors: testSuite.testResults.compactMap { $0.error }.joined(separator: "\n")
            )
            
            // Обновляем запись итерации с результатом исправления
            iterations[iterations.count - 1] = TestIteration(
                iteration: iteration,
                sourceCode: currentSourceCode,
                testCode: currentTestCode,
                testSuite: testSuite,
                fixResult: fixResult,
                timestamp: Date()
            )
            
            if fixResult.success {
                currentSourceCode = fixResult.fixedCode
            } else {
                // Если не удалось исправить код, завершаем
                return TestOrchestrationResult(
                    success: false,
                    finalSourceCode: currentSourceCode,
                    finalTestCode: currentTestCode,
                    iterations: iterations,
                    totalIterations: iteration,
                    totalExecutionTime: Date().timeIntervalSince(startTime),
                    finalTestSuite: testSuite,
                    error: "Ошибка исправления кода: \(fixResult.error)"
                )
            }
        }
        
        // Не должны сюда дойти
        return TestOrchestrationResult(
            success: false,
            finalSourceCode: currentSourceCode,
            finalTestCode: currentTestCode,
            iterations: iterations,
            totalIterations: maxIterations,
            totalExecutionTime: Date().timeIntervalSince(startTime),
            finalTestSuite: SwiftTestSuite(
                sourceCode: currentSourceCode,
                testCode: currentTestCode,
                testResults: [],
                allTestsPassed: false,
                totalTests: 0,
                passedTests: 0,
                failedTests: 0
            ),
            error: "Неожиданная ошибка в цикле тестирования"
        )
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
