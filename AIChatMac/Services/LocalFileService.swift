import Foundation

struct LocalFileFix {
    let filePath: String
    let content: String
    let description: String
    let diff: String
}

struct LocalFixResult {
    let status: LocalFixStatus
    let message: String
    let createdFiles: [String]
    let errors: [String]
}

enum LocalFixStatus {
    case success
    case partialSuccess
    case failed
    case needsMoreInfo
}

class LocalFileService {
    private let aiService: ChatService
    
    init(aiService: ChatService) {
        self.aiService = aiService
    }
    
    func fixLocalIssue(
        directoryPath: String,
        issueDescription: String
    ) async -> LocalFixResult {
        
        print("🔧 Начинаем исправление локальной проблемы")
        print("📁 Директория: \(directoryPath)")
        print("📋 Описание проблемы: \(issueDescription)")
        
        // 1. Проверяем существование директории
        guard FileManager.default.fileExists(atPath: directoryPath) else {
            return LocalFixResult(
                status: .failed,
                message: "❌ Директория не существует: \(directoryPath)",
                createdFiles: [],
                errors: ["Директория не найдена"]
            )
        }
        
        // 2. Анализируем проблему
        let issueAnalysis = analyzeLocalIssue(issueDescription: issueDescription, directoryPath: directoryPath)
        
        // 3. Генерируем фикс
        let fix = await generateLocalFix(issueAnalysis: issueAnalysis, directoryPath: directoryPath, issueDescription: issueDescription)
        
        // 4. Создаем файлы
        let result = await createLocalFiles(fix: fix, directoryPath: directoryPath)
        
        return result
    }
    
    private func analyzeLocalIssue(issueDescription: String, directoryPath: String) -> String {
        let lowercasedDescription = issueDescription.lowercased()
        
        if lowercasedDescription.contains("github actions") || 
           lowercasedDescription.contains("ci/cd") ||
           lowercasedDescription.contains("билдится") ||
           lowercasedDescription.contains("build") {
            return "github_actions"
        } else if lowercasedDescription.contains("security") ||
                  lowercasedDescription.contains("безопасн") {
            return "security"
        } else if lowercasedDescription.contains("performance") ||
                  lowercasedDescription.contains("производительн") {
            return "performance"
        } else if lowercasedDescription.contains("test") ||
                  lowercasedDescription.contains("тест") {
            return "testing"
        } else {
            return "generic"
        }
    }
    
    private func generateLocalFix(issueAnalysis: String, directoryPath: String, issueDescription: String) async -> LocalFileFix {
        // Генерируем контент с помощью AI
        let aiContent = await generateAIContent(issueAnalysis: issueAnalysis, issueDescription: issueDescription, directoryPath: directoryPath)
        
        // Определяем путь и имя файла на основе типа проблемы
        let (filePath, fileName) = determineFilePath(issueAnalysis: issueAnalysis, directoryPath: directoryPath)
        
        return LocalFileFix(
            filePath: filePath,
            content: aiContent,
            description: "AI-сгенерированное решение для: \(issueDescription)",
            diff: "+ Создан файл \(fileName) с AI-сгенерированным решением"
        )
    }
    
    private func generateAIContent(issueAnalysis: String, issueDescription: String, directoryPath: String) async -> String {
        // Анализируем структуру проекта
        let projectAnalysis = analyzeProjectStructure(directoryPath: directoryPath)
        
        let prompt = createAIPrompt(
            issueAnalysis: issueAnalysis, 
            issueDescription: issueDescription, 
            directoryPath: directoryPath,
            projectAnalysis: projectAnalysis
        )
        
        // Создаем сообщение для AI
        let message = ChatMessage(
            author: .user,
            content: prompt,
            isUser: true
        )
        
        // Отправляем запрос к AI
        if let aiResponse = await aiService.sendDirectMessage([message]) {
            return aiResponse
        } else {
            // Fallback контент если AI не ответил
            return createFallbackContent(issueAnalysis: issueAnalysis, issueDescription: issueDescription)
        }
    }
    
    private func createAIPrompt(issueAnalysis: String, issueDescription: String, directoryPath: String, projectAnalysis: String) -> String {
        return """
        Ты - эксперт по разработке программного обеспечения. Тебе нужно создать файл для решения следующей проблемы:
        
        **Тип проблемы:** \(issueAnalysis)
        **Описание проблемы:** \(issueDescription)
        **Директория:** \(directoryPath)
        
        **АНАЛИЗ ПРОЕКТА:**
        \(projectAnalysis)
        
        КРИТИЧЕСКИ ВАЖНО: Создай ТОЛЬКО содержимое файла без каких-либо комментариев, объяснений или дополнительного текста!
        
        **Правила создания файла:**
        - Создай только содержимое файла
        - НЕ добавляй комментарии типа "Файл создан для..."
        - НЕ добавляй объяснения после содержимого
        - НЕ используй markdown разметку
        - Файл должен быть готов к использованию
        
        **Для GitHub Actions (ci.yml):**
        - Используй macos-latest для runs-on
        - Адаптируй под конкретный проект на основе анализа выше
        - Используй правильные имена схем и таргетов из проекта
        - Включи шаги для сборки и тестирования конкретного проекта
        - Учти зависимости и структуру проекта
        - Создай рабочий YAML файл
        
        **Для Security файла:**
        - Создай политику безопасности для конкретного типа проекта
        - Включи контакты для отчетов об уязвимостях
        - Учти специфику проекта (macOS, iOS, и т.д.)
        
        **Для Performance файла:**
        - Создай руководство по оптимизации для конкретного типа проекта
        - Включи лучшие практики для данного типа приложения
        
        **Для Testing файла:**
        - Создай руководство по тестированию для конкретного проекта
        - Включи примеры тестов, адаптированные под структуру проекта
        
        Создай ТОЛЬКО содержимое файла, без комментариев и объяснений.
        """
    }
    
    private func analyzeProjectStructure(directoryPath: String) -> String {
        var analysis = "**Анализ структуры проекта:**\n\n"
        
        do {
            let fileManager = FileManager.default
            let contents = try fileManager.contentsOfDirectory(atPath: directoryPath)
            
            // Анализируем основные файлы проекта
            var projectType = "Неизвестный тип проекта"
            var hasXcodeProject = false
            var hasPackageSwift = false
            var hasSwiftFiles = false
            var mainTargets: [String] = []
            var dependencies: [String] = []
            
            for item in contents {
                if item.hasSuffix(".xcodeproj") {
                    hasXcodeProject = true
                    projectType = "Xcode проект"
                    mainTargets.append(item.replacingOccurrences(of: ".xcodeproj", with: ""))
                } else if item == "Package.swift" {
                    hasPackageSwift = true
                    projectType = "Swift Package Manager проект"
                } else if item.hasSuffix(".swift") {
                    hasSwiftFiles = true
                } else if item == "Podfile" {
                    dependencies.append("CocoaPods")
                } else if item == "Cartfile" {
                    dependencies.append("Carthage")
                } else if item == "Gemfile" {
                    dependencies.append("Ruby Gems")
                } else if item == "package.json" {
                    dependencies.append("Node.js")
                }
            }
            
            // Анализируем поддиректории
            for item in contents {
                let itemPath = "\(directoryPath)/\(item)"
                var isDirectory: ObjCBool = false
                if fileManager.fileExists(atPath: itemPath, isDirectory: &isDirectory) && isDirectory.boolValue {
                    if item == "Sources" || item == "src" {
                        analysis += "- 📁 Исходный код в директории: \(item)\n"
                    } else if item == "Tests" || item == "test" {
                        analysis += "- 🧪 Тесты в директории: \(item)\n"
                    } else if item == "Resources" || item == "assets" {
                        analysis += "- 🎨 Ресурсы в директории: \(item)\n"
                    } else if item.hasSuffix("App") || item.hasSuffix("App") {
                        analysis += "- 📱 Основное приложение: \(item)\n"
                    }
                }
            }
            
            // Формируем анализ
            analysis += "\n**Тип проекта:** \(projectType)\n"
            
            if hasXcodeProject {
                analysis += "**Xcode проект:** Да\n"
                if !mainTargets.isEmpty {
                    analysis += "**Основные таргеты:** \(mainTargets.joined(separator: ", "))\n"
                }
            }
            
            if hasPackageSwift {
                analysis += "**Swift Package Manager:** Да\n"
            }
            
            if hasSwiftFiles {
                analysis += "**Swift файлы:** Да\n"
            }
            
            if !dependencies.isEmpty {
                analysis += "**Зависимости:** \(dependencies.joined(separator: ", "))\n"
            }
            
            // Анализируем README если есть
            if contents.contains("README.md") {
                analysis += "**Документация:** README.md найден\n"
            }
            
            // Анализируем конфигурационные файлы
            let configFiles = contents.filter { $0.hasSuffix(".plist") || $0.hasSuffix(".entitlements") || $0.hasSuffix(".xcconfig") }
            if !configFiles.isEmpty {
                analysis += "**Конфигурационные файлы:** \(configFiles.joined(separator: ", "))\n"
            }
            
        } catch {
            analysis += "❌ Ошибка при анализе проекта: \(error.localizedDescription)\n"
        }
        
        return analysis
    }
    
    private func createFallbackContent(issueAnalysis: String, issueDescription: String) -> String {
        return """
        # Решение для проблемы: \(issueDescription)
        
        ## Тип проблемы: \(issueAnalysis)
        
        ### Описание
        Это автоматически сгенерированное решение для указанной проблемы.
        
        ### Рекомендации
        1. Проанализируйте проблему детально
        2. Изучите существующий код
        3. Примените соответствующие паттерны
        4. Протестируйте решение
        5. Документируйте изменения
        
        ### Следующие шаги
        - [ ] Анализ текущего состояния
        - [ ] Планирование изменений
        - [ ] Реализация решения
        - [ ] Тестирование
        - [ ] Документирование
        
        ---
        *Этот файл был создан автоматически AI агентом*
        """
    }
    
    private func determineFilePath(issueAnalysis: String, directoryPath: String) -> (String, String) {
        switch issueAnalysis {
        case "github_actions":
            let filePath = "\(directoryPath)/.github/workflows/ci.yml"
            return (filePath, ".github/workflows/ci.yml")
        case "security":
            let filePath = "\(directoryPath)/SECURITY.md"
            return (filePath, "SECURITY.md")
        case "performance":
            let filePath = "\(directoryPath)/PERFORMANCE.md"
            return (filePath, "PERFORMANCE.md")
        case "testing":
            let filePath = "\(directoryPath)/TESTING.md"
            return (filePath, "TESTING.md")
        default:
            let filePath = "\(directoryPath)/SOLUTION.md"
            return (filePath, "SOLUTION.md")
        }
    }
    

    
    private func createLocalFiles(fix: LocalFileFix, directoryPath: String) async -> LocalFixResult {
        var createdFiles: [String] = []
        var errors: [String] = []
        
        do {
            // Создаем директории если нужно
            let fileURL = URL(fileURLWithPath: fix.filePath)
            let directoryURL = fileURL.deletingLastPathComponent()
            
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: nil
            )
            
            // Создаем файл
            try fix.content.write(
                to: fileURL,
                atomically: true,
                encoding: .utf8
            )
            
            createdFiles.append(fix.filePath)
            print("✅ Создан файл: \(fix.filePath)")
            
        } catch {
            let errorMessage = "❌ Ошибка создания файла \(fix.filePath): \(error.localizedDescription)"
            errors.append(errorMessage)
            print(errorMessage)
        }
        
        let status: LocalFixStatus
        if errors.isEmpty {
            status = .success
        } else if !createdFiles.isEmpty {
            status = .partialSuccess
        } else {
            status = .failed
        }
        
        let message = """
        🔧 Результат исправления:
        
        📋 Описание: \(fix.description)
        📁 Созданные файлы: \(createdFiles.joined(separator: ", "))
        \(errors.isEmpty ? "" : "\n❌ Ошибки:\n\(errors.joined(separator: "\n"))")
        
        \(fix.diff)
        """
        
        return LocalFixResult(
            status: status,
            message: message,
            createdFiles: createdFiles,
            errors: errors
        )
    }
}
