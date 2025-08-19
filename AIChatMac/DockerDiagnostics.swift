//
//  DockerDiagnostics.swift
//  AIChatMac
//
//  Created by Николай Игнатов on 19.08.2025.
//

import Foundation

final class DockerDiagnostics {
    static func diagnoseDockerIssues() async -> String {
        var report = "🔍 ДИАГНОСТИКА DOCKER\n\n"
        
        // 1. Проверяем наличие файла docker
        let dockerPaths = [
            "/usr/local/bin/docker",
            "/opt/homebrew/bin/docker",
            "/usr/bin/docker"
        ]
        
        report += "📁 Проверка путей к Docker:\n"
        for path in dockerPaths {
            let exists = FileManager.default.fileExists(atPath: path)
            report += "  \(path): \(exists ? "✅ Найден" : "❌ Не найден")\n"
        }
        report += "\n"
        
        // 2. Пробуем выполнить docker --version
        report += "⚡ Тест выполнения команд:\n"
        
        for path in dockerPaths {
            if FileManager.default.fileExists(atPath: path) {
                let result = await runDockerCommand(path: path, args: ["--version"])
                report += "  \(path) --version: \(result.success ? "✅" : "❌") \(result.output.prefix(50))\n"
                
                if result.success {
                    // Пробуем docker info
                    let infoResult = await runDockerCommand(path: path, args: ["info"])
                    report += "  \(path) info: \(infoResult.success ? "✅ Daemon работает" : "❌ Daemon не отвечает")\n"
                    break
                }
            }
        }
        
        report += "\n"
        
        // 3. Проверяем права доступа
        report += "🔐 Проверка прав доступа:\n"
        let currentUser = NSUserName()
        report += "  Текущий пользователь: \(currentUser)\n"
        
        // Проверяем группу docker
        let groupResult = await runCommand("/usr/bin/groups", args: [])
        report += "  Группы пользователя: \(groupResult.output.trimmingCharacters(in: .whitespacesAndNewlines))\n"
        
        return report
    }
    
    private static func runDockerCommand(path: String, args: [String]) async -> (success: Bool, output: String) {
        return await runCommand(path, args: args)
    }
    
    private static func runCommand(_ path: String, args: [String]) async -> (success: Bool, output: String) {
        return await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = args
            
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            
            process.standardOutput = outputPipe
            process.standardError = errorPipe
            
            process.terminationHandler = { _ in
                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                
                let output = String(data: outputData, encoding: .utf8) ?? ""
                let error = String(data: errorData, encoding: .utf8) ?? ""
                
                let fullOutput = output.isEmpty ? error : output
                let success = process.terminationStatus == 0
                
                continuation.resume(returning: (success, fullOutput))
            }
            
            do {
                try process.run()
            } catch {
                continuation.resume(returning: (false, "Ошибка запуска: \(error.localizedDescription)"))
            }
        }
    }
}
