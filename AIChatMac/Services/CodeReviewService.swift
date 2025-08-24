//
//  CodeReviewService.swift
//  AIChatMac
//
//  Created by Николай Игнатов on 19.08.2025.
//

import Foundation

final class CodeReviewService {
    private let aiService: ChatService
    private let githubPRService: GitHubPRService
    
    init(aiService: ChatService, githubPRService: GitHubPRService) {
        self.aiService = aiService
        self.githubPRService = githubPRService
    }
    
    // MARK: - Timeout Helper
    private func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async -> T?) async -> T? {
        return await withTaskGroup(of: T?.self) { group in
            group.addTask {
                await operation()
            }
            
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return nil
            }
            
            for await result in group {
                if result != nil {
                    group.cancelAll()
                    return result
                }
            }
            return nil
        }
    }
    
    // MARK: - Main Review Function
    
    func reviewPullRequest(from url: String, progressCallback: ((Double) -> Void)? = nil) async -> Result<CodeReviewResult, Error> {
        print("🔍 Начинаем ревью PR: \(url)")
        
        // 1. Парсим URL
        guard let (owner, repo, prNumber) = githubPRService.parseGitHubPRURL(url) else {
            print("❌ Не удалось распарсить URL")
            return .failure(CodeReviewError.invalidURL)
        }
        print("✅ URL распарсен: \(owner)/\(repo) PR #\(prNumber)")
        
        // 2. Получаем данные PR
        print("📥 Получаем данные PR...")
        let prResult = await githubPRService.fetchPullRequest(owner: owner, repo: repo, prNumber: prNumber)
        guard case .success(let pullRequest) = prResult else {
            print("❌ Не удалось получить данные PR")
            return .failure(CodeReviewError.failedToFetchPR)
        }
        print("✅ Данные PR получены: \(pullRequest.title)")
        
        // 3. Получаем файлы PR
        print("📁 Получаем файлы PR...")
        let filesResult = await githubPRService.fetchPullRequestFiles(owner: owner, repo: repo, prNumber: prNumber)
        guard case .success(let files) = filesResult else {
            print("❌ Не удалось получить файлы PR")
            return .failure(CodeReviewError.failedToFetchFiles)
        }
        print("✅ Файлы PR получены: \(files.count) файлов")
        
        // 4. Получаем diff
        print("📋 Получаем diff...")
        let diffResult = await githubPRService.fetchPullRequestDiff(owner: owner, repo: repo, prNumber: prNumber)
        guard case .success(let diff) = diffResult else {
            print("❌ Не удалось получить diff")
            return .failure(CodeReviewError.failedToFetchDiff)
        }
        print("✅ Diff получен: \(diff.count) символов")
        
        // 5. Выполняем AI ревью
        print("🤖 Выполняем AI ревью...")
        
        // Пробуем сначала с полным diff
        var reviewResult = await performAIReview(pullRequest: pullRequest, files: files, diff: diff, progressCallback: progressCallback)
        
        // Если не удалось, пробуем без diff
        if case .failure = reviewResult {
            print("⚠️ Ревью с diff не удалось, пробуем без diff...")
            reviewResult = await performAIReview(pullRequest: pullRequest, files: files, diff: "", progressCallback: progressCallback)
        }
        
        guard case .success(let review) = reviewResult else {
            print("❌ Не удалось выполнить AI ревью")
            return .failure(CodeReviewError.failedToReview)
        }
        print("✅ AI ревью выполнено: оценка \(review.overallScore)/100")
        
        // 6. Создаем issues на основе ревью
        let issuesResult = await createIssuesFromReview(
            review: review,
            owner: owner,
            repo: repo,
            prNumber: prNumber
        )
        
        // 7. Добавляем комментарий к PR
        let commentResult = await addReviewCommentToPR(
            review: review,
            owner: owner,
            repo: repo,
            prNumber: prNumber
        )
        
        return .success(CodeReviewResult(
            pullRequest: pullRequest,
            review: review,
            createdIssues: issuesResult,
            commentAdded: commentResult
        ))
    }
    
    // MARK: - AI Review Pipeline
    
    private func performAIReview(pullRequest: PullRequest, files: [PRFile], diff: String, progressCallback: ((Double) -> Void)? = nil) async -> Result<CodeReview, Error> {
        print("🔄 Начинаем пайплайн ревью...")
        
        // Разбиваем файлы на батчи
        let batchSize = 2 // Уменьшили размер батча для стабильности
        let batches = stride(from: 0, to: files.count, by: batchSize).map {
            Array(files[$0..<min($0 + batchSize, files.count)])
        }
        
        print("📊 Всего батчей: \(batches.count) (по \(batchSize) файлов)")
        print("⏱️ Ожидаемое время: ~\(batches.count * 30) секунд")
        
        var accumulatedIssues: [CodeIssue] = []
        var accumulatedWarnings: [CodeWarning] = []
        var accumulatedSuggestions: [CodeSuggestion] = []
        var accumulatedContext = ""
        var batchScores: [Int] = []
        
        // Ревью каждого батча
        for (index, batch) in batches.enumerated() {
            let progress = Double(index) / Double(batches.count)
            print("🔄 Ревью батча \(index + 1)/\(batches.count) (\(batch.count) файлов)... [\(String(format: "%.1f", progress * 100))%]")
            
            // Обновляем прогресс в UI
            progressCallback?(progress)
            
            let batchResult = await reviewBatch(
                batch: batch,
                batchIndex: index,
                totalBatches: batches.count,
                accumulatedContext: accumulatedContext,
                pullRequest: pullRequest
            )
            
            switch batchResult {
            case .success(let batchReview):
                // Накопление результатов
                accumulatedIssues.append(contentsOf: batchReview.issues)
                accumulatedWarnings.append(contentsOf: batchReview.warnings)
                accumulatedSuggestions.append(contentsOf: batchReview.suggestions)
                accumulatedContext += "\n\n" + batchReview.context
                batchScores.append(batchReview.score)
                
                print("✅ Батч \(index + 1) завершен: \(batchReview.issues.count) проблем, оценка \(batchReview.score)/100")
                
            case .failure(let error):
                print("❌ Ошибка в батче \(index + 1): \(error)")
                // Продолжаем с другими батчами
            }
        }
        
        // Создаем финальный отчет
        let overallScore = batchScores.isEmpty ? 80 : batchScores.reduce(0, +) / batchScores.count
        let summary = createFinalSummary(
            totalFiles: files.count,
            totalIssues: accumulatedIssues.count,
            totalWarnings: accumulatedWarnings.count,
            totalSuggestions: accumulatedSuggestions.count,
            averageScore: overallScore
        )
        
        let finalReview = CodeReview(
            prId: pullRequest.id,
            prNumber: pullRequest.number,
            issues: accumulatedIssues,
            warnings: accumulatedWarnings,
            suggestions: accumulatedSuggestions,
            overallScore: overallScore,
            reviewDate: Date(),
            summary: summary
        )
        
        print("✅ Пайплайн ревью завершен:")
        print("   - Всего файлов: \(files.count)")
        print("   - Всего проблем: \(accumulatedIssues.count)")
        print("   - Всего предупреждений: \(accumulatedWarnings.count)")
        print("   - Всего предложений: \(accumulatedSuggestions.count)")
        print("   - Средняя оценка: \(overallScore)/100")
        
        // Завершаем прогресс
        progressCallback?(1.0)
        
        return .success(finalReview)
    }
    
    private func reviewBatch(
        batch: [PRFile],
        batchIndex: Int,
        totalBatches: Int,
        accumulatedContext: String,
        pullRequest: PullRequest
    ) async -> Result<BatchReviewResult, Error> {
        
        // Получаем diff только для файлов в этом батче
        var batchDiff = ""
        for file in batch {
            if let fileDiff = await getFileDiff(file: file, owner: pullRequest.head.repo.fullName.components(separatedBy: "/")[0], repo: pullRequest.head.repo.fullName.components(separatedBy: "/")[1], prNumber: pullRequest.number) {
                batchDiff += fileDiff + "\n\n"
            }
        }
        
        // Ограничиваем размер diff для батча
        let maxBatchDiffSize = 30000 // 30KB на батч
        if batchDiff.count > maxBatchDiffSize {
            batchDiff = String(batchDiff.prefix(maxBatchDiffSize)) + "\n\n... (diff обрезан)"
        }
        
        let prompt = createBatchReviewPrompt(
            batch: batch,
            batchIndex: batchIndex,
            totalBatches: totalBatches,
            batchDiff: batchDiff,
            accumulatedContext: accumulatedContext,
            pullRequest: pullRequest
        )
        
        // Отладочная информация - размер промпта
        print("📝 Размер промпта для батча \(batchIndex + 1): \(prompt.count) символов")
        print("📝 Первые 300 символов промпта:")
        print(String(prompt.prefix(300)))
        
        let message = ChatMessage(
            author: .user,
            content: prompt,
            isUser: true
        )
        
        // Отправляем запрос к AI с таймаутом
        let aiResponse = await withTimeout(seconds: 30) {
            await self.aiService.sendDirectMessage([message])
        }
        
        guard let aiResponse = aiResponse else {
            print("❌ AI сервис не вернул ответ (timeout или ошибка)")
            return .failure(CodeReviewError.aiReviewFailed)
        }
        
        // Отладочная информация - первые 500 символов ответа AI
        print("🤖 AI ответ (батч \(batchIndex + 1), первые 500 символов):")
        print(String(aiResponse.prefix(500)))
        print("📊 Размер ответа AI: \(aiResponse.count) символов")
        
        // Проверяем, что AI действительно что-то вернул
        if aiResponse.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            print("❌ AI вернул пустой ответ!")
            return .failure(CodeReviewError.aiReviewFailed)
        }
        
        // Парсим ответ для батча
        let result = parseBatchReviewResponse(aiResponse, batchIndex: batchIndex)
        
        // Отладочная информация
        switch result {
        case .success(let batchResult):
            print("🔍 Батч \(batchIndex + 1) результаты:")
            print("   - Проблем: \(batchResult.issues.count)")
            print("   - Предупреждений: \(batchResult.warnings.count)")
            print("   - Предложений: \(batchResult.suggestions.count)")
            print("   - Оценка: \(batchResult.score)/100")
        case .failure(let error):
            print("❌ Ошибка парсинга батча \(batchIndex + 1): \(error)")
        }
        
        return result
    }
    
    private func getFileDiff(file: PRFile, owner: String, repo: String, prNumber: Int) async -> String? {
        // Используем patch из PRFile, если он доступен
        if let patch = file.patch {
            return patch
        }
        
        // Если patch недоступен, можно попробовать получить diff через API
        // Но для простоты пока возвращаем пустую строку
        return ""
    }
    
    private func createBatchReviewPrompt(
        batch: [PRFile],
        batchIndex: Int,
        totalBatches: Int,
        batchDiff: String,
        accumulatedContext: String,
        pullRequest: PullRequest
    ) -> String {
        
        let fileSummary = batch.map { file in
            "- \(file.filename) (\(file.status)): +\(file.additions) -\(file.deletions)"
        }.joined(separator: "\n")
        
        var prompt = """
        РЕВЬЮ БАТЧА \(batchIndex + 1)/\(totalBatches)
        
        PR: \(pullRequest.title)
        Файлы: \(batch.count)
        \(fileSummary)
        """
        
        if !accumulatedContext.isEmpty {
            prompt += """
            
            Контекст: \(accumulatedContext)
            """
        }
        
        if !batchDiff.isEmpty {
            prompt += """
            
            Изменения:
            \(batchDiff)
            """
        }
        
        prompt += """
        
        Найди все проблемы в коде. Будь критичным.
        
        ВАЖНО: Для каждой проблемы давай конкретное предложение по исправлению!
        
        Типы: Безопасность, Ошибка, Производительность, Архитектура, Стиль кода, Документация, Покрытие тестами, Именование
        
        Формат ответа:
        ОЦЕНКА: [1-100]
        
        ПРОБЛЕМЫ:
        - [Тип] [Файл:строка] - [Описание] - [Предложение исправления]
        
        ПРЕДУПРЕЖДЕНИЯ:
        - [Тип] [Файл:строка] - [Описание] - [Предложение]
        
        ПРЕДЛОЖЕНИЯ:
        - [Тип] [Файл:строка] - [Описание] - [Код или предложение]
        
        КОНТЕКСТ:
        [Наблюдения для следующих батчей]
        """
        
        return prompt
    }
    
    private func parseBatchReviewResponse(_ response: String, batchIndex: Int) -> Result<BatchReviewResult, Error> {
        var issues: [CodeIssue] = []
        var warnings: [CodeWarning] = []
        var suggestions: [CodeSuggestion] = []
        var score = 80
        var context = ""
        
        let lines = response.components(separatedBy: .newlines)
        var currentSection = ""
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            
            if trimmedLine.contains("ОЦЕНКА:") || trimmedLine.contains("ОЦЕНКА БАТЧА:") {
                if let scoreMatch = trimmedLine.range(of: "\\d+", options: .regularExpression) {
                    let scoreString = String(trimmedLine[scoreMatch])
                    score = Int(scoreString) ?? 80
                }
            } else if trimmedLine.contains("ПРОБЛЕМЫ:") || trimmedLine.contains("ПРОБЛЕМЫ В БАТЧЕ:") {
                currentSection = "issues"
            } else if trimmedLine.contains("ПРЕДУПРЕЖДЕНИЯ:") || trimmedLine.contains("ПРЕДУПРЕЖДЕНИЯ В БАТЧЕ:") {
                currentSection = "warnings"
            } else if trimmedLine.contains("ПРЕДЛОЖЕНИЯ:") || trimmedLine.contains("ПРЕДЛОЖЕНИЯ ПО УЛУЧШЕНИЮ:") {
                currentSection = "suggestions"
            } else if trimmedLine.contains("КОНТЕКСТ:") || trimmedLine.contains("КОНТЕКСТ ДЛЯ СЛЕДУЮЩИХ БАТЧЕЙ:") {
                currentSection = "context"
            } else if trimmedLine.hasPrefix("- ") && !trimmedLine.isEmpty {
                let issueText = String(trimmedLine.dropFirst(2))
                parseIssueLine(issueText, section: currentSection, issues: &issues, warnings: &warnings, suggestions: &suggestions)
            } else if currentSection == "context" && !trimmedLine.isEmpty {
                context += trimmedLine + " "
            }
        }
        
        let batchResult = BatchReviewResult(
            issues: issues,
            warnings: warnings,
            suggestions: suggestions,
            score: score,
            context: context
        )
        
        return .success(batchResult)
    }
    
    private func createFinalSummary(
        totalFiles: Int,
        totalIssues: Int,
        totalWarnings: Int,
        totalSuggestions: Int,
        averageScore: Int
    ) -> String {
        return """
        Ревью завершено для \(totalFiles) файлов.
        
        📊 Итоговая статистика:
        - Всего проблем: \(totalIssues)
        - Всего предупреждений: \(totalWarnings)
        - Всего предложений: \(totalSuggestions)
        - Средняя оценка: \(averageScore)/100
        
        Ревью проводилось по батчам для обеспечения качества анализа больших PR.
        """
    }
    
    // MARK: - Issue Creation
    
    private func createIssuesFromReview(review: CodeReview, owner: String, repo: String, prNumber: Int) async -> [GitHubIssueResponse] {
        var createdIssues: [GitHubIssueResponse] = []
        
        // Создаем один issue со всеми проблемами
        if !review.issues.isEmpty {
            if let issue = await createCompleteIssue(
                review: review,
                owner: owner,
                repo: repo,
                prNumber: prNumber
            ) {
                createdIssues.append(issue)
            }
        }
        
        return createdIssues
    }
    
        private func createCompleteIssue(
        review: CodeReview,
        owner: String,
        repo: String,
        prNumber: Int
    ) async -> GitHubIssueResponse? {
        let title = "🔍 Ревью PR #\(prNumber): \(review.issues.count) проблем найдено"
        
        // Группируем проблемы по приоритету
        let criticalIssues = review.issues.filter { $0.severity == .critical }
        let highIssues = review.issues.filter { $0.severity == .high }
        let mediumIssues = review.issues.filter { $0.severity == .medium }
        let lowIssues = review.issues.filter { $0.severity == .low }
        
        var body = """
        ## 🔍 Полное ревью PR #\(prNumber)
        
        ### 📊 Статистика:
        - **Всего проблем:** \(review.issues.count)
        - **Критических:** \(criticalIssues.count)
        - **Высокого приоритета:** \(highIssues.count)
        - **Среднего приоритета:** \(mediumIssues.count)
        - **Низкого приоритета:** \(lowIssues.count)
        - **Общая оценка:** \(review.overallScore)/100
        
        """
        
        // Добавляем проблемы по приоритету
        if !criticalIssues.isEmpty {
            body += """
            
            ## 🚨 Критические проблемы (\(criticalIssues.count)):
            \(formatIssues(criticalIssues))
            """
        }
        
        if !highIssues.isEmpty {
            body += """
            
            ## ⚠️ Высокий приоритет (\(highIssues.count)):
            \(formatIssues(highIssues))
            """
        }
        
        if !mediumIssues.isEmpty {
            body += """
            
            ## 🔵 Средний приоритет (\(mediumIssues.count)):
            \(formatIssues(mediumIssues))
            """
        }
        
        if !lowIssues.isEmpty {
            body += """
            
            ## 🟡 Низкий приоритет (\(lowIssues.count)):
            \(formatIssues(lowIssues))
            """
        }
        
        body += """
        
        ---
        *Автоматически создано системой ревью кода*
        """
        
        let issueRequest = GitHubIssueRequest(
            title: title,
            body: body,
            labels: ["code-review", "automated-review"],
            assignees: nil
        )
        
        let result = await githubPRService.createIssue(owner: owner, repo: repo, issue: issueRequest)
        switch result {
        case .success(let response):
            print("✅ Создан полный issue: \(response.title)")
            return response
        case .failure(let error):
            print("❌ Ошибка создания полного issue: \(error)")
            return nil
        }
    }
    
    private func formatIssues(_ issues: [CodeIssue]) -> String {
        return issues.map { issue in
            """
            - **\(issue.type.rawValue)** в `\(issue.file ?? "неизвестный файл"):\(issue.line ?? 0)`
              - \(issue.message)
              - **Предложение:** \(issue.suggestion ?? "Не указано")
            """
        }.joined(separator: "\n\n")
    }
    
    private func addReviewCommentToPR(
        review: CodeReview,
        owner: String,
        repo: String,
        prNumber: Int
    ) async -> Bool {
        let comment = createReviewComment(review: review)
        
        let result = await githubPRService.addCommentToPR(
            owner: owner,
            repo: repo,
            prNumber: prNumber,
            comment: comment
        )
        
        switch result {
        case .success:
            print("✅ Комментарий к PR добавлен")
            return true
        case .failure(let error):
            print("❌ Ошибка добавления комментария к PR: \(error)")
            return false
        }
    }
    
    private func createReviewComment(review: CodeReview) -> String {
        return """
        ## 🔍 Результаты автоматического ревью кода
        
        ### 📊 Общая статистика:
        - **Оценка:** \(review.overallScore)/100
        - **Проблемы:** \(review.issues.count)
        - **Предупреждения:** \(review.warnings.count)
        - **Предложения:** \(review.suggestions.count)
        
        ### 🚨 Проблемы по приоритету:
        - **Критические:** \(review.issues.filter { $0.severity == .critical }.count)
        - **Высокие:** \(review.issues.filter { $0.severity == .high }.count)
        - **Средние:** \(review.issues.filter { $0.severity == .medium }.count)
        - **Низкие:** \(review.issues.filter { $0.severity == .low }.count)
        
        ### 📝 Резюме:
        \(review.summary)
        
        ---
        *Ревью выполнено автоматически с помощью AI*
        """
    }
    
    private func parseIssueLine(_ line: String, section: String, issues: inout [CodeIssue], warnings: inout [CodeWarning], suggestions: inout [CodeSuggestion]) {
        // Парсим строку вида: "[Тип] [Файл:строка] - [Описание]" или "[Тип проблемы] [Файл:строка] - [Описание]"
        let components = line.components(separatedBy: " - ")
        guard components.count >= 2 else { 
            print("❌ Неправильный формат строки: '\(line)'")
            return 
        }
        
        let firstPart = components[0]
        let description = components[1]
        let suggestion = components.count > 2 ? components[2] : nil
        
        // Извлекаем тип и файл:строка
        // AI отвечает в формате: "[Тип] [Файл:строка]" или "[Тип] Файл:строка"
        let firstPartComponents = firstPart.components(separatedBy: " ")
        guard firstPartComponents.count >= 2 else { 
            print("❌ Неправильный формат первой части: '\(firstPart)'")
            return 
        }
        
        let issueTypeString = firstPartComponents[0].trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        let fileLinePart = firstPartComponents[1].trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        
        // Парсим файл:строка
        let fileLineComponents = fileLinePart.components(separatedBy: ":")
        guard fileLineComponents.count >= 2 else { 
            print("❌ Неправильный формат файл:строка: '\(fileLinePart)'")
            return 
        }
        
        let filename = fileLineComponents[0]
        let lineNumber = Int(fileLineComponents[1]) ?? 0
        
        print("🔍 Парсинг строки: '\(line)'")
        print("   - Тип: '\(issueTypeString)'")
        print("   - Файл: '\(filename)'")
        print("   - Строка: \(lineNumber)")
        print("   - Описание: '\(description)'")
        
        // Определяем тип и создаем соответствующий объект
        switch section {
        case "issues":
            let issueType = parseIssueType(issueTypeString)
            let severity = determineSeverity(from: issueType)
            print("🔍 Парсинг проблемы: '\(issueTypeString)' -> \(issueType.rawValue) -> \(severity.rawValue)")
            let issue = CodeIssue(
                type: issueType,
                severity: severity,
                file: filename,
                line: lineNumber,
                message: description,
                suggestion: suggestion,
                codeSnippet: nil
            )
            issues.append(issue)
            
        case "warnings":
            let warningType = WarningType(rawValue: issueTypeString) ?? .codeStyle
            let warning = CodeWarning(
                type: warningType,
                file: filename,
                line: lineNumber,
                message: description,
                suggestion: suggestion
            )
            warnings.append(warning)
            
        case "suggestions":
            let suggestionType = SuggestionType(rawValue: issueTypeString) ?? .refactoring
            let suggestion = CodeSuggestion(
                type: suggestionType,
                file: filename,
                line: lineNumber,
                message: description,
                code: suggestion
            )
            suggestions.append(suggestion)
            
        default:
            break
        }
    }
    
    private func parseIssueType(_ typeString: String) -> IssueType {
        let lowercased = typeString.lowercased()
        
        switch lowercased {
        case let s where s.contains("безопасность") || s.contains("security"):
            return .security
        case let s where s.contains("ошибка") || s.contains("bug") || s.contains("error"):
            return .bug
        case let s where s.contains("производительность") || s.contains("performance"):
            return .performance
        case let s where s.contains("архитектура") || s.contains("architecture"):
            return .architecture
        case let s where s.contains("стиль") || s.contains("style") || s.contains("код"):
            return .codeStyle
        case let s where s.contains("документация") || s.contains("documentation") || s.contains("комментарий"):
            return .documentation
        case let s where s.contains("тест") || s.contains("test") || s.contains("покрытие"):
            return .testCoverage
        case let s where s.contains("именование") || s.contains("naming") || s.contains("имя"):
            return .naming
        default:
            return .codeStyle // По умолчанию считаем проблемой стиля
        }
    }
    
    private func determineSeverity(from issueType: IssueType) -> Severity {
        switch issueType {
        case .security:
            return .critical
        case .bug:
            return .critical
        case .performance:
            return .high
        case .architecture:
            return .high
        case .codeStyle:
            return .medium
        case .documentation:
            return .low
        case .testCoverage:
            return .low
        case .naming:
            return .low
        }
    }
}

// MARK: - Supporting Types

struct BatchReviewResult {
    let issues: [CodeIssue]
    let warnings: [CodeWarning]
    let suggestions: [CodeSuggestion]
    let score: Int
    let context: String
}

struct CodeReviewResult {
    let pullRequest: PullRequest
    let review: CodeReview
    let createdIssues: [GitHubIssueResponse]
    let commentAdded: Bool
}

// MARK: - Errors

enum CodeReviewError: Error, LocalizedError {
    case invalidURL
    case failedToFetchPR
    case failedToFetchFiles
    case failedToFetchDiff
    case failedToReview
    case aiReviewFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Неверный URL GitHub PR"
        case .failedToFetchPR:
            return "Не удалось получить данные PR"
        case .failedToFetchFiles:
            return "Не удалось получить файлы PR"
        case .failedToFetchDiff:
            return "Не удалось получить diff"
        case .failedToReview:
            return "Не удалось выполнить ревью"
        case .aiReviewFailed:
            return "AI ревью не удалось"
        }
    }
}
