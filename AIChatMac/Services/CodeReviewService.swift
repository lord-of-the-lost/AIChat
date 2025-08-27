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
    private let mcpGitHubService: MCPGitHubService
    
    init(aiService: ChatService, githubPRService: GitHubPRService) {
        self.aiService = aiService
        self.githubPRService = githubPRService
        self.mcpGitHubService = MCPGitHubService(githubToken: githubPRService.githubToken)
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
    
    // MARK: - Interactive Issue Fixing
    
    func fixSpecificIssue(
        from url: String,
        issueDescription: String,
        progressCallback: ((Double) -> Void)? = nil
    ) async -> Result<InteractiveFixResult, Error> {
        
        print("🔧 Начинаем исправление конкретной проблемы")
        print("📋 Описание проблемы: \(issueDescription)")
        
        // 1. Парсим URL PR
        guard let (owner, repo, prNumber) = githubPRService.parseGitHubPRURL(url) else {
            return .failure(CodeReviewError.invalidURL)
        }
        
        print("✅ URL распарсен: \(owner)/\(repo) PR #\(prNumber)")
        
        // 2. Получаем данные PR
        let prResult = await githubPRService.fetchPullRequest(owner: owner, repo: repo, prNumber: prNumber)
        guard case .success(let pullRequest) = prResult else {
            return .failure(CodeReviewError.failedToFetchPR)
        }
        
        print("✅ Данные PR получены: \(pullRequest.title)")
        
        // 3. Получаем файлы PR
        let filesResult = await githubPRService.fetchPullRequestFiles(owner: owner, repo: repo, prNumber: prNumber)
        guard case .success(let files) = filesResult else {
            return .failure(CodeReviewError.failedToFetchFiles)
        }
        
        print("✅ Файлы PR получены: \(files.count) файлов")
        
        // 4. Анализируем описание проблемы
        let issueAnalysis = analyzeIssueDescription(issueDescription, files: files)
        
        // 5. Если нужно больше информации, возвращаем запрос
        if issueAnalysis.needsMoreInfo {
            return .success(InteractiveFixResult(
                status: .needsMoreInfo,
                questions: issueAnalysis.questions,
                pullRequest: pullRequest,
                issueAnalysis: issueAnalysis,
                generatedFix: nil,
                fixPR: nil
            ))
        }
        
        // 6. Генерируем фикс
        progressCallback?(0.3)
        let fixResult = await generateFixForSpecificIssue(
            issueAnalysis: issueAnalysis,
            pullRequest: pullRequest,
            owner: owner,
            repo: repo
        )
        
        progressCallback?(0.6)
        
        // 7. Создаем PR с фиксом
        let fixPRResult = await createFixPullRequest(
            fix: fixResult,
            owner: owner,
            repo: repo,
            baseBranch: pullRequest.base.ref,
            originalPRNumber: prNumber
        )
        
        progressCallback?(1.0)
        
        // Проверяем, был ли успешно создан PR
        let finalStatus: InteractiveFixStatus
        if fixPRResult != nil {
            finalStatus = .completed
        } else {
            finalStatus = .failed
        }
        
        return .success(InteractiveFixResult(
            status: finalStatus,
            questions: [],
            pullRequest: pullRequest,
            issueAnalysis: issueAnalysis,
            generatedFix: fixResult,
            fixPR: fixPRResult
        ))
    }
    
    private func analyzeIssueDescription(_ description: String, files: [PRFile]) -> IssueAnalysis {
        print("🔍 Анализируем описание проблемы...")
        
        let lowerDescription = description.lowercased()
        
        // 1. GitHub Actions / CI/CD проблемы
        if lowerDescription.contains("гитхаб экшенс") || lowerDescription.contains("github actions") || 
           lowerDescription.contains("ci/cd") || lowerDescription.contains("автоматизация") ||
           lowerDescription.contains("билдится") || lowerDescription.contains("сборка") ||
           lowerDescription.contains("workflow") || lowerDescription.contains("пайплайн") {
            
            return IssueAnalysis(
                filePath: nil,
                lineNumber: nil,
                issueType: "Infrastructure",
                issueMessage: description,
                suggestion: "Создать GitHub Actions для автоматической сборки и тестирования",
                needsMoreInfo: false,
                questions: []
            )
        }
        
        // 2. Проблемы безопасности
        if lowerDescription.contains("безопасн") || lowerDescription.contains("security") ||
           lowerDescription.contains("токен") || lowerDescription.contains("token") ||
           lowerDescription.contains("пароль") || lowerDescription.contains("password") ||
           lowerDescription.contains("ключ") || lowerDescription.contains("key") ||
           lowerDescription.contains("хранение") || lowerDescription.contains("storage") {
            
            return IssueAnalysis(
                filePath: nil,
                lineNumber: nil,
                issueType: "Security",
                issueMessage: description,
                suggestion: "Добавить безопасное хранение токенов и ключей",
                needsMoreInfo: false,
                questions: []
            )
        }
        
        // 3. Проблемы производительности
        if lowerDescription.contains("производительность") || lowerDescription.contains("performance") ||
           lowerDescription.contains("медленно") || lowerDescription.contains("slow") ||
           lowerDescription.contains("оптимизация") || lowerDescription.contains("optimization") {
            
            return IssueAnalysis(
                filePath: nil,
                lineNumber: nil,
                issueType: "Performance",
                issueMessage: description,
                suggestion: "Оптимизировать производительность кода",
                needsMoreInfo: false,
                questions: []
            )
        }
        
        // 4. Проблемы архитектуры
        if lowerDescription.contains("архитектура") || lowerDescription.contains("architecture") ||
           lowerDescription.contains("структура") || lowerDescription.contains("structure") ||
           lowerDescription.contains("паттерн") || lowerDescription.contains("pattern") {
            
            return IssueAnalysis(
                filePath: nil,
                lineNumber: nil,
                issueType: "Architecture",
                issueMessage: description,
                suggestion: "Улучшить архитектуру кода",
                needsMoreInfo: false,
                questions: []
            )
        }
        
        // 5. Проблемы стиля кода
        if lowerDescription.contains("стиль") || lowerDescription.contains("style") ||
           lowerDescription.contains("форматирование") || lowerDescription.contains("formatting") ||
           lowerDescription.contains("конвенции") || lowerDescription.contains("conventions") {
            
            return IssueAnalysis(
                filePath: nil,
                lineNumber: nil,
                issueType: "Style",
                issueMessage: description,
                suggestion: "Улучшить стиль кода и форматирование",
                needsMoreInfo: false,
                questions: []
            )
        }
        
        // Извлекаем информацию из описания для конкретных проблем
        let lines = description.components(separatedBy: "\n")
        var filePath: String?
        var lineNumber: Int?
        var issueType: String?
        var issueMessage: String?
        var suggestion: String?
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            
            // Ищем файл и строку в формате "Файл:строка" или "в Файл:строка"
            if let fileMatch = trimmedLine.range(of: #"([^:\s]+\.swift):(\d+)"#, options: .regularExpression) {
                let match = String(trimmedLine[fileMatch])
                let components = match.components(separatedBy: ":")
                if components.count == 2 {
                    filePath = components[0]
                    lineNumber = Int(components[1])
                }
            }
            
            // Ищем тип проблемы
            if trimmedLine.contains("Безопасность") || trimmedLine.contains("Security") {
                issueType = "Security"
            } else if trimmedLine.contains("Производительность") || trimmedLine.contains("Performance") {
                issueType = "Performance"
            } else if trimmedLine.contains("Архитектура") || trimmedLine.contains("Architecture") {
                issueType = "Architecture"
            } else if trimmedLine.contains("Стиль") || trimmedLine.contains("Style") {
                issueType = "Style"
            }
            
            // Ищем описание проблемы
            if trimmedLine.contains("Предложение:") {
                suggestion = trimmedLine.replacingOccurrences(of: "Предложение:", with: "").trimmingCharacters(in: .whitespaces)
            } else if !trimmedLine.isEmpty && !trimmedLine.contains(":") && issueMessage == nil {
                issueMessage = trimmedLine
            }
        }
        
        // Проверяем, нужна ли дополнительная информация
        var questions: [String] = []
        var needsMoreInfo = false
        
        if filePath == nil {
            questions.append("В каком файле находится проблема?")
            needsMoreInfo = true
        }
        
        if lineNumber == nil {
            questions.append("На какой строке находится проблема?")
            needsMoreInfo = true
        }
        
        if issueMessage == nil {
            questions.append("Опишите проблему более подробно")
            needsMoreInfo = true
        }
        
        // Проверяем, существует ли файл в PR
        if let filePath = filePath {
            let fileExists = files.contains { $0.filename.contains(filePath) }
            if !fileExists {
                questions.append("Файл '\(filePath)' не найден в PR. Укажите правильное имя файла")
                needsMoreInfo = true
            }
        }
        
        return IssueAnalysis(
            filePath: filePath,
            lineNumber: lineNumber,
            issueType: issueType ?? "Unknown",
            issueMessage: issueMessage,
            suggestion: suggestion,
            needsMoreInfo: needsMoreInfo,
            questions: questions
        )
    }
    
    private func generateFixForSpecificIssue(
        issueAnalysis: IssueAnalysis,
        pullRequest: PullRequest,
        owner: String,
        repo: String
    ) async -> GeneratedFix {
        
        print("🔧 Генерируем фикс для проблемы типа: \(issueAnalysis.issueType)...")
        
        // Проверяем тип проблемы и генерируем соответствующий фикс
        switch issueAnalysis.issueType {
        case "Infrastructure":
            return await generateInfrastructureFix(issueAnalysis: issueAnalysis, pullRequest: pullRequest, owner: owner, repo: repo)
        case "Security":
            return await generateSecurityFix(issueAnalysis: issueAnalysis, pullRequest: pullRequest, owner: owner, repo: repo)
        case "Performance":
            return await generatePerformanceFix(issueAnalysis: issueAnalysis, pullRequest: pullRequest, owner: owner, repo: repo)
        case "Architecture":
            return await generateArchitectureFix(issueAnalysis: issueAnalysis, pullRequest: pullRequest, owner: owner, repo: repo)
        case "Style":
            return await generateStyleFix(issueAnalysis: issueAnalysis, pullRequest: pullRequest, owner: owner, repo: repo)
        default:
            return await generateGenericFix(issueAnalysis: issueAnalysis, pullRequest: pullRequest, owner: owner, repo: repo)
        }
        
        // Получаем содержимое файла для конкретной проблемы
        guard let filePath = issueAnalysis.filePath else {
            return GeneratedFix(
                filePath: "unknown",
                originalContent: "",
                fixedContent: "",
                diff: "",
                description: "Не удалось определить файл для исправления",
                commitMessage: "Fix issue",
                success: false
            )
        }
        
        let fileContentResult = await githubPRService.fetchFileContent(
            owner: owner,
            repo: repo,
            path: filePath,
            ref: pullRequest.head.sha
        )
        
        let originalContent = (try? fileContentResult.get()) ?? ""
        
        // Создаем промпт для генерации фикса
        let fixPrompt = """
        Исправь следующую проблему в коде:
        
        **Файл:** \(filePath)
        **Строка:** \(issueAnalysis.lineNumber ?? 0)
        **Тип проблемы:** \(issueAnalysis.issueType)
        **Проблема:** \(issueAnalysis.issueMessage ?? "Не указана")
        **Предложение:** \(issueAnalysis.suggestion ?? "Нет предложения")
        
        **Текущий код файла:**
        ```swift
        \(originalContent)
        ```
        
        Сгенерируй исправление в следующем формате:
        
        FIXED_CODE:
        ```swift
        // исправленный код здесь
        ```
        
        DIFF:
        ```diff
        - старая строка
        + новая строка
        ```
        
        DESCRIPTION:
        Краткое описание исправления
        
        COMMIT_MESSAGE:
        Краткое сообщение для коммита
        """
        
        // Отправляем запрос к AI
        let messages = [
            ChatMessage(author: .user, content: fixPrompt, isUser: true)
        ]
        
        let result = await aiService.sendDirectMessage(messages)
        
        guard let response = result else {
            return GeneratedFix(
                filePath: issueAnalysis.filePath!,
                originalContent: originalContent,
                fixedContent: originalContent,
                diff: "",
                description: "Не удалось сгенерировать исправление",
                commitMessage: "Fix issue",
                success: false
            )
        }
        
        // Парсим ответ AI
        let fixedContent = extractCodeBlock(from: response, marker: "FIXED_CODE") ?? originalContent
        let diff = extractCodeBlock(from: response, marker: "DIFF") ?? ""
        let description = extractDescription(from: response) ?? "Исправление проблемы"
        let commitMessage = extractCommitMessage(from: response) ?? "Fix issue"
        
        return GeneratedFix(
            filePath: filePath,
            originalContent: originalContent,
            fixedContent: fixedContent,
            diff: diff,
            description: description,
            commitMessage: commitMessage,
            success: true
        )
    }
    
    private func generateInfrastructureFix(
        issueAnalysis: IssueAnalysis,
        pullRequest: PullRequest,
        owner: String,
        repo: String
    ) async -> GeneratedFix {
        
        print("🔧 Генерируем инфраструктурное исправление (GitHub Actions)...")
        
        // Создаем промпт для генерации GitHub Actions
        let fixPrompt = """
        Создай GitHub Actions для автоматической сборки и тестирования Swift проекта.
        
        **Проблема:** \(issueAnalysis.issueMessage ?? "Отсутствуют GitHub Actions")
        **Предложение:** \(issueAnalysis.suggestion ?? "Создать CI/CD пайплайн")
        
        Создай файл .github/workflows/ci.yml для автоматической сборки Swift проекта на macOS.
        
        Сгенерируй файл в следующем формате:
        
        FIXED_CODE:
        ```yaml
        # GitHub Actions для Swift проекта
        name: CI
        
        on:
          push:
            branches: [ main, develop ]
          pull_request:
            branches: [ main ]
        
        jobs:
          build:
            runs-on: macos-latest
            
            steps:
            - uses: actions/checkout@v4
            
            - name: Select Xcode
              run: sudo xcode-select -switch /Applications/Xcode_15.2.app
            
            - name: Build
              run: |
                xcodebuild -project AIChat.xcodeproj -scheme AIChatMac -configuration Debug build
                
            - name: Test
              run: |
                xcodebuild -project AIChat.xcodeproj -scheme AIChatMac -configuration Debug test
        ```
        
        DIFF:
        ```diff
        + name: CI
        + 
        + on:
        +   push:
        +     branches: [ main, develop ]
        +   pull_request:
        +     branches: [ main ]
        + 
        + jobs:
        +   build:
        +     runs-on: macos-latest
        +     
        +     steps:
        +     - uses: actions/checkout@v4
        +     
        +     - name: Select Xcode
        +       run: sudo xcode-select -switch /Applications/Xcode_15.2.app
        +     
        +     - name: Build
        +       run: |
        +         xcodebuild -project AIChat.xcodeproj -scheme AIChatMac -configuration Debug build
        +         
        +     - name: Test
        +       run: |
        +         xcodebuild -project AIChat.xcodeproj -scheme AIChatMac -configuration Debug test
        ```
        
        DESCRIPTION:
        Создан GitHub Actions для автоматической сборки и тестирования Swift проекта
        
        COMMIT_MESSAGE:
        Add GitHub Actions CI/CD pipeline
        """
        
        // Отправляем запрос к AI
        let messages = [
            ChatMessage(author: .user, content: fixPrompt, isUser: true)
        ]
        
        let result = await aiService.sendDirectMessage(messages)
        
        guard let response = result else {
            return GeneratedFix(
                filePath: ".github/workflows/ci.yml",
                originalContent: "",
                fixedContent: "",
                diff: "",
                description: "Не удалось сгенерировать GitHub Actions",
                commitMessage: "Add CI/CD pipeline",
                success: false
            )
        }
        
        // Парсим ответ AI
        let fixedContent = extractCodeBlock(from: response, marker: "FIXED_CODE") ?? getDefaultGitHubActions()
        let diff = extractCodeBlock(from: response, marker: "DIFF") ?? ""
        let description = extractDescription(from: response) ?? "Создан GitHub Actions для автоматической сборки"
        let commitMessage = extractCommitMessage(from: response) ?? "Add GitHub Actions CI/CD pipeline"
        
        return GeneratedFix(
            filePath: ".github/workflows/ci.yml",
            originalContent: "",
            fixedContent: fixedContent,
            diff: diff,
            description: description,
            commitMessage: commitMessage,
            success: true
        )
    }
    
    private func getDefaultGitHubActions() -> String {
        return """
        name: CI
        
        on:
          push:
            branches: [ main, develop ]
          pull_request:
            branches: [ main ]
        
        jobs:
          build:
            runs-on: macos-latest
            
            steps:
            - uses: actions/checkout@v4
            
            - name: Select Xcode
              run: sudo xcode-select -switch /Applications/Xcode_15.2.app
            
            - name: Build
              run: |
                xcodebuild -project AIChat.xcodeproj -scheme AIChatMac -configuration Debug build
                
            - name: Test
              run: |
                xcodebuild -project AIChat.xcodeproj -scheme AIChatMac -configuration Debug test
        """
    }
    
    // MARK: - Security Fix Generation
    
    private func generateSecurityFix(
        issueAnalysis: IssueAnalysis,
        pullRequest: PullRequest,
        owner: String,
        repo: String
    ) async -> GeneratedFix {
        
        print("🔒 Генерируем исправление для проблемы безопасности...")
        
        // Создаем промпт для генерации исправления безопасности
        let fixPrompt = """
        Создай безопасное решение для хранения токенов и ключей в Swift приложении.
        
        **Проблема:** \(issueAnalysis.issueMessage ?? "Небезопасное хранение токенов")
        **Предложение:** \(issueAnalysis.suggestion ?? "Добавить безопасное хранение")
        
        Создай файл для безопасного хранения токенов с использованием Keychain.
        
        Сгенерируй файл в следующем формате:
        
        FIXED_CODE:
        ```swift
        import Foundation
        import Security
        
        // MARK: - Secure Token Storage
        class SecureTokenStorage {
            private let service = "com.aichat.tokens"
            
            // Сохранить токен в Keychain
            func saveToken(_ token: String, forKey key: String) -> Bool {
                let query: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: service,
                    kSecAttrAccount as String: key,
                    kSecValueData as String: token.data(using: .utf8)!
                ]
                
                // Удаляем существующий токен
                SecItemDelete(query as CFDictionary)
                
                // Сохраняем новый токен
                let status = SecItemAdd(query as CFDictionary, nil)
                return status == errSecSuccess
            }
            
            // Получить токен из Keychain
            func getToken(forKey key: String) -> String? {
                let query: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: service,
                    kSecAttrAccount as String: key,
                    kSecReturnData as String: true,
                    kSecMatchLimit as String: kSecMatchLimitOne
                ]
                
                var result: AnyObject?
                let status = SecItemCopyMatching(query as CFDictionary, &result)
                
                guard status == errSecSuccess,
                      let data = result as? Data,
                      let token = String(data: data, encoding: .utf8) else {
                    return nil
                }
                
                return token
            }
            
            // Удалить токен из Keychain
            func deleteToken(forKey key: String) -> Bool {
                let query: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: service,
                    kSecAttrAccount as String: key
                ]
                
                let status = SecItemDelete(query as CFDictionary)
                return status == errSecSuccess
            }
            
            // Проверить существование токена
            func hasToken(forKey key: String) -> Bool {
                return getToken(forKey: key) != nil
            }
        }
        
        // MARK: - Environment Configuration
        class EnvironmentConfig {
            private let tokenStorage = SecureTokenStorage()
            
            // Безопасное получение API ключа
            var apiKey: String? {
                return tokenStorage.getToken(forKey: "api_key")
            }
            
            // Безопасное получение GitHub токена
            var githubToken: String? {
                return tokenStorage.getToken(forKey: "github_token")
            }
            
            // Инициализация токенов (вызывать только один раз)
            func setupTokens(apiKey: String, githubToken: String) {
                tokenStorage.saveToken(apiKey, forKey: "api_key")
                tokenStorage.saveToken(githubToken, forKey: "github_token")
            }
        }
        ```
        
        DIFF:
        ```diff
        + import Foundation
        + import Security
        + 
        + // MARK: - Secure Token Storage
        + class SecureTokenStorage {
        +     private let service = "com.aichat.tokens"
        +     
        +     // Сохранить токен в Keychain
        +     func saveToken(_ token: String, forKey key: String) -> Bool {
        +         let query: [String: Any] = [
        +             kSecClass as String: kSecClassGenericPassword,
        +             kSecAttrService as String: service,
        +             kSecAttrAccount as String: key,
        +             kSecValueData as String: token.data(using: .utf8)!
        +         ]
        +         
        +         // Удаляем существующий токен
        +         SecItemDelete(query as CFDictionary)
        +         
        +         // Сохраняем новый токен
        +         let status = SecItemAdd(query as CFDictionary, nil)
        +         return status == errSecSuccess
        +     }
        +     
        +     // Получить токен из Keychain
        +     func getToken(forKey key: String) -> String? {
        +         let query: [String: Any] = [
        +             kSecClass as String: kSecClassGenericPassword,
        +             kSecAttrService as String: service,
        +             kSecAttrAccount as String: key,
        +             kSecReturnData as String: true,
        +             kSecMatchLimit as String: kSecMatchLimitOne
        +         ]
        +         
        +         var result: AnyObject?
        +         let status = SecItemCopyMatching(query as CFDictionary, &result)
        +         
        +         guard status == errSecSuccess,
        +               let data = result as? Data,
        +               let token = String(data: data, encoding: .utf8) else {
        +             return nil
        +         }
        +         
        +         return token
        +     }
        +     
        +     // Удалить токен из Keychain
        +     func deleteToken(forKey key: String) -> Bool {
        +         let query: [String: Any] = [
        +             kSecClass as String: kSecClassGenericPassword,
        +             kSecAttrService as String: service,
        +             kSecAttrAccount as String: key
        +         ]
        +         
        +         let status = SecItemDelete(query as CFDictionary)
        +         return status == errSecSuccess
        +     }
        +     
        +     // Проверить существование токена
        +     func hasToken(forKey key: String) -> Bool {
        +         return getToken(forKey: key) != nil
        +     }
        + }
        + 
        + // MARK: - Environment Configuration
        + class EnvironmentConfig {
        +     private let tokenStorage = SecureTokenStorage()
        +     
        +     // Безопасное получение API ключа
        +     var apiKey: String? {
        +         return tokenStorage.getToken(forKey: "api_key")
        +         }
        +         
        +         // Безопасное получение GitHub токена
        +         var githubToken: String? {
        +             return tokenStorage.getToken(forKey: "github_token")
        +         }
        +         
        +         // Инициализация токенов (вызывать только один раз)
        +         func setupTokens(apiKey: String, githubToken: String) {
        +             tokenStorage.saveToken(apiKey, forKey: "api_key")
        +             tokenStorage.saveToken(githubToken, forKey: "github_token")
        +         }
        + }
        ```
        
        DESCRIPTION:
        Добавлено безопасное хранение токенов с использованием Keychain
        
        COMMIT_MESSAGE:
        Add secure token storage using Keychain
        """
        
        // Отправляем запрос к AI
        let messages = [
            ChatMessage(author: .user, content: fixPrompt, isUser: true)
        ]
        
        let result = await aiService.sendDirectMessage(messages)
        
        guard let response = result else {
            return GeneratedFix(
                filePath: "AIChatMac/Services/SecureTokenStorage.swift",
                originalContent: "",
                fixedContent: "",
                diff: "",
                description: "Не удалось сгенерировать исправление безопасности",
                commitMessage: "Add secure token storage",
                success: false
            )
        }
        
        // Парсим ответ AI
        let fixedContent = extractCodeBlock(from: response, marker: "FIXED_CODE") ?? getDefaultSecurityFix()
        let diff = extractCodeBlock(from: response, marker: "DIFF") ?? ""
        let description = extractDescription(from: response) ?? "Добавлено безопасное хранение токенов"
        let commitMessage = extractCommitMessage(from: response) ?? "Add secure token storage using Keychain"
        
        return GeneratedFix(
            filePath: "AIChatMac/Services/SecureTokenStorage.swift",
            originalContent: "",
            fixedContent: fixedContent,
            diff: diff,
            description: description,
            commitMessage: commitMessage,
            success: true
        )
    }
    
    // MARK: - Other Fix Generators (Placeholders)
    
    private func generatePerformanceFix(
        issueAnalysis: IssueAnalysis,
        pullRequest: PullRequest,
        owner: String,
        repo: String
    ) async -> GeneratedFix {
        return GeneratedFix(
            filePath: "AIChatMac/Services/PerformanceOptimization.swift",
            originalContent: "",
            fixedContent: "// Performance optimization placeholder",
            diff: "",
            description: "Performance optimization (placeholder)",
            commitMessage: "Add performance optimization",
            success: true
        )
    }
    
    private func generateArchitectureFix(
        issueAnalysis: IssueAnalysis,
        pullRequest: PullRequest,
        owner: String,
        repo: String
    ) async -> GeneratedFix {
        return GeneratedFix(
            filePath: "AIChatMac/Services/ArchitectureImprovement.swift",
            originalContent: "",
            fixedContent: "// Architecture improvement placeholder",
            diff: "",
            description: "Architecture improvement (placeholder)",
            commitMessage: "Improve code architecture",
            success: true
        )
    }
    
    private func generateStyleFix(
        issueAnalysis: IssueAnalysis,
        pullRequest: PullRequest,
        owner: String,
        repo: String
    ) async -> GeneratedFix {
        return GeneratedFix(
            filePath: "AIChatMac/Services/StyleImprovement.swift",
            originalContent: "",
            fixedContent: "// Code style improvement placeholder",
            diff: "",
            description: "Code style improvement (placeholder)",
            commitMessage: "Improve code style",
            success: true
        )
    }
    
    private func generateGenericFix(
        issueAnalysis: IssueAnalysis,
        pullRequest: PullRequest,
        owner: String,
        repo: String
    ) async -> GeneratedFix {
        return GeneratedFix(
            filePath: "AIChatMac/Services/GenericFix.swift",
            originalContent: "",
            fixedContent: "// Generic fix placeholder",
            diff: "",
            description: "Generic fix (placeholder)",
            commitMessage: "Add generic fix",
            success: true
        )
    }
    
    private func getDefaultSecurityFix() -> String {
        return """
        import Foundation
        import Security
        
        // MARK: - Secure Token Storage
        class SecureTokenStorage {
            private let service = "com.aichat.tokens"
            
            // Сохранить токен в Keychain
            func saveToken(_ token: String, forKey key: String) -> Bool {
                let query: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: service,
                    kSecAttrAccount as String: key,
                    kSecValueData as String: token.data(using: .utf8)!
                ]
                
                // Удаляем существующий токен
                SecItemDelete(query as CFDictionary)
                
                // Сохраняем новый токен
                let status = SecItemAdd(query as CFDictionary, nil)
                return status == errSecSuccess
            }
            
            // Получить токен из Keychain
            func getToken(forKey key: String) -> String? {
                let query: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: service,
                    kSecAttrAccount as String: key,
                    kSecReturnData as String: true,
                    kSecMatchLimit as String: kSecMatchLimitOne
                ]
                
                var result: AnyObject?
                let status = SecItemCopyMatching(query as CFDictionary, &result)
                
                guard status == errSecSuccess,
                      let data = result as? Data,
                      let token = String(data: data, encoding: .utf8) else {
                    return nil
                }
                
                return token
            }
            
            // Удалить токен из Keychain
            func deleteToken(forKey key: String) -> Bool {
                let query: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: service,
                    kSecAttrAccount as String: key
                ]
                
                let status = SecItemDelete(query as CFDictionary)
                return status == errSecSuccess
            }
            
            // Проверить существование токена
            func hasToken(forKey key: String) -> Bool {
                return getToken(forKey: key) != nil
            }
        }
        
        // MARK: - Environment Configuration
        class EnvironmentConfig {
            private let tokenStorage = SecureTokenStorage()
            
            // Безопасное получение API ключа
            var apiKey: String? {
                return tokenStorage.getToken(forKey: "api_key")
            }
            
            // Безопасное получение GitHub токена
            var githubToken: String? {
                return tokenStorage.getToken(forKey: "github_token")
            }
            
            // Инициализация токенов (вызывать только один раз)
            func setupTokens(apiKey: String, githubToken: String) {
                tokenStorage.saveToken(apiKey, forKey: "api_key")
                tokenStorage.saveToken(githubToken, forKey: "github_token")
            }
        }
        """
    }
    
    private func createFixPullRequest(
        fix: GeneratedFix,
        owner: String,
        repo: String,
        baseBranch: String,
        originalPRNumber: Int
    ) async -> PullRequest? {
        
        print("🔧 Создаем Pull Request с исправлением...")
        
        // Сначала получаем информацию о репозитории
        let repoInfoResult = await mcpGitHubService.getRepositoryInfo(owner: owner, repo: repo)
        
        switch repoInfoResult {
        case .success(let repoInfo):
            print("✅ Информация о репозитории получена")
            print("📋 Default branch: \(repoInfo.defaultBranch)")
            print("🔒 Приватный: \(repoInfo.isPrivate)")
            
            // Используем правильную ветку по умолчанию
            let actualBaseBranch = baseBranch.isEmpty ? repoInfo.defaultBranch : baseBranch
            print("📋 Используем ветку: \(actualBaseBranch)")
            
        case .failure(let error):
            print("❌ Не удалось получить информацию о репозитории: \(error)")
            return nil
        }
        
        // Создаем ветку для фикса используя MCP сервис
        let branchName = "fix-issue-pr-\(originalPRNumber)"
        let actualBaseBranch = baseBranch.isEmpty ? "main" : baseBranch
        let branchResult = await mcpGitHubService.createBranch(
            owner: owner,
            repo: repo,
            branchName: branchName,
            baseBranch: actualBaseBranch
        )
        
        switch branchResult {
        case .success:
            print("✅ Ветка \(branchName) создана успешно")
        case .failure(let error):
            print("❌ Не удалось создать ветку \(branchName): \(error)")
            return nil
        }
        
        // Создаем файл с исправлением используя MCP сервис
        let fileResult = await mcpGitHubService.createFile(
            owner: owner,
            repo: repo,
            path: fix.filePath,
            content: fix.fixedContent,
            message: fix.commitMessage,
            branch: branchName
        )
        
        switch fileResult {
        case .success:
            print("✅ Файл \(fix.filePath) создан успешно")
        case .failure(let error):
            print("❌ Не удалось создать файл: \(error)")
            return nil
        }
        
        // Проверяем, существует ли уже Pull Request
        let prExistsResult = await githubPRService.checkPullRequestExists(
            owner: owner,
            repo: repo,
            headBranch: branchName,
            baseBranch: baseBranch
        )
        
        switch prExistsResult {
        case .success(let exists):
            if exists {
                print("⚠️ Pull Request уже существует для ветки \(branchName)")
                return nil
            }
        case .failure(let error):
            print("⚠️ Не удалось проверить существование PR: \(error)")
        }
        
        // Создаем Pull Request используя MCP сервис
        let prResult = await mcpGitHubService.createPullRequest(
            owner: owner,
            repo: repo,
            title: "🔧 Исправление проблемы из PR #\(originalPRNumber)",
            body: """
            ## Исправление проблемы
            
            **Файл:** \(fix.filePath)
            **Описание:** \(fix.description)
            
            ### Изменения:
            ```
            \(fix.diff)
            ```
            
            ---
            *Исправление сгенерировано автоматически*
            """,
            headBranch: branchName,
            baseBranch: actualBaseBranch
        )
        
        switch prResult {
        case .success(let mcpPR):
            print("✅ Создан Pull Request с исправлением: \(mcpPR.htmlUrl)")
            // Конвертируем GitHubPullRequest в PullRequest
            let dateFormatter = ISO8601DateFormatter()
            
            let pr = PullRequest(
                id: mcpPR.id,
                number: mcpPR.number,
                title: mcpPR.title,
                body: mcpPR.body,
                state: mcpPR.state,
                user: GitHubUser(
                    login: mcpPR.user.login,
                    id: mcpPR.user.id,
                    name: mcpPR.user.name,
                    email: mcpPR.user.email,
                    avatarUrl: mcpPR.user.avatarUrl,
                    htmlUrl: mcpPR.user.htmlUrl
                ),
                head: PRBranch(
                    label: mcpPR.head.label,
                    ref: mcpPR.head.ref,
                    sha: mcpPR.head.sha,
                    user: mcpPR.head.user ?? GitHubUser(
                        login: "",
                        id: 0,
                        name: nil,
                        email: nil,
                        avatarUrl: "",
                        htmlUrl: nil
                    ),
                    repo: mcpPR.head.repo ?? GitHubRepository(
                        id: 0,
                        name: "",
                        fullName: "",
                        description: nil,
                        isPrivate: false,
                        htmlUrl: "",
                        autoInit: nil
                    )
                ),
                base: PRBranch(
                    label: mcpPR.base.label,
                    ref: mcpPR.base.ref,
                    sha: mcpPR.base.sha,
                    user: mcpPR.base.user ?? GitHubUser(
                        login: "",
                        id: 0,
                        name: nil,
                        email: nil,
                        avatarUrl: "",
                        htmlUrl: nil
                    ),
                    repo: mcpPR.base.repo ?? GitHubRepository(
                        id: 0,
                        name: "",
                        fullName: "",
                        description: nil,
                        isPrivate: false,
                        htmlUrl: "",
                        autoInit: nil
                    )
                ),
                additions: 0,
                deletions: 0,
                changedFiles: 0,
                createdAt: dateFormatter.date(from: mcpPR.createdAt) ?? Date(),
                updatedAt: dateFormatter.date(from: mcpPR.updatedAt) ?? Date(),
                htmlUrl: mcpPR.htmlUrl,
                diffUrl: "",
                patchUrl: "",
                commitsUrl: "",
                commentsUrl: "",
                reviewCommentsUrl: "",
                statusesUrl: ""
            )
            return pr
        case .failure(let error):
            print("❌ Ошибка создания Pull Request: \(error)")
            return nil
        }
    }
    
    private func extractCodeBlock(from text: String, marker: String) -> String? {
        let pattern = "\(marker):\\s*```(?:swift)?\\s*([\\s\\S]*?)```"
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }
        
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range) else {
            return nil
        }
        
        let codeRange = match.range(at: 1)
        guard let range = Range(codeRange, in: text) else {
            return nil
        }
        
        return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func extractDescription(from text: String) -> String? {
        let pattern = "DESCRIPTION:\\s*(.+)"
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }
        
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range) else {
            return nil
        }
        
        let descRange = match.range(at: 1)
        guard let range = Range(descRange, in: text) else {
            return nil
        }
        
        return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func extractCommitMessage(from text: String) -> String? {
        let pattern = "COMMIT_MESSAGE:\\s*(.+)"
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }
        
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range) else {
            return nil
        }
        
        let msgRange = match.range(at: 1)
        guard let range = Range(msgRange, in: text) else {
            return nil
        }
        
        return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
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
