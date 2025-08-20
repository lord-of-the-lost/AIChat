//
//  SwiftExecutionService.swift
//  AIChatMac
//
//  Created by Николай Игнатов on 19.08.2025.
//

import Foundation

final class SwiftExecutionService {
    private let mcpDockerService: MCPDockerService
    private let nativeExecutor: NativeSwiftExecutor
    
    init() {
        self.mcpDockerService = MCPDockerService()
        self.nativeExecutor = NativeSwiftExecutor()
    }
    
    func executeSwiftCode(_ code: String) async -> SwiftExecutionResult {
        // Пробуем MCP Docker сервис с коротким timeout
        let mcpTask = Task {
            return await mcpDockerService.checkHealth()
        }
        
        do {
            let isMCPAvailable = try await withTimeout(seconds: 2) {
                await mcpTask.value
            }
            
            if isMCPAvailable {
                return await mcpDockerService.executeSwiftCode(code)
            } else {
                return await nativeExecutor.executeSwiftCode(code)
            }
        } catch {
            mcpTask.cancel()
            return await nativeExecutor.executeSwiftCode(code)
        }
    }
    
    private func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw TimeoutError()
            }
            
            guard let result = try await group.next() else {
                throw TimeoutError()
            }
            
            group.cancelAll()
            return result
        }
    }
}

struct TimeoutError: Error {}

// MARK: - Docker Manager
final class DockerManager {
    private let swiftImage = "swift:5.9"
    
    func executeSwiftCode(in directory: URL) async -> (success: Bool, output: String, error: String) {
        // Проверяем, запущен ли Docker
        let dockerStatus = await checkDockerStatus()
        if !dockerStatus {
            let errorMsg = "Docker не запущен или недоступен. Пожалуйста, запустите Docker Desktop."
            return (false, "", errorMsg)
        }
        
        // Проверяем наличие Swift образа
        let imageExists = await ensureSwiftImage()
        if !imageExists {
            let errorMsg = "Не удалось загрузить Swift образ из Docker Hub."
            return (false, "", errorMsg)
        }
        
        // Выполняем Swift код в контейнере
        return await runSwiftInContainer(directory: directory)
    }
    
    private func checkDockerStatus() async -> Bool {
        // Сначала проверяем базовую команду docker
        let versionResult = await runShellCommand("docker", arguments: ["--version"])
        
        if !versionResult.success || !versionResult.output.contains("Docker version") {
            return false
        }
        
        // Затем проверяем что Docker daemon запущен
        let infoResult = await runShellCommand("docker", arguments: ["info"])
        if !infoResult.success {
            return false
        }
        
        return true
    }
    
    private func ensureSwiftImage() async -> Bool {
        // Сначала проверяем, есть ли образ локально
        let checkResult = await runShellCommand("docker", arguments: ["images", "-q", swiftImage])
        
        if !checkResult.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        
        let pullResult = await runShellCommand("docker", arguments: ["pull", swiftImage])
        return pullResult.success
    }
    
    private func runSwiftInContainer(directory: URL) async -> (success: Bool, output: String, error: String) {
        let containerName = "swift-playground-\(UUID().uuidString.prefix(8))"
        
        // Аргументы для запуска контейнера
        let dockerArgs = [
            "run",
            "--rm",
            "--name", containerName,
            "-v", "\(directory.path):/app",
            "-w", "/app",
            swiftImage,
            "swift", "main.swift"
        ]
        
        let result = await runShellCommand("docker", arguments: dockerArgs, timeout: 30.0)
        
        return (result.success, result.output, result.error)
    }
    
    private func runShellCommand(_ command: String, arguments: [String], timeout: TimeInterval = 10.0) async -> (success: Bool, output: String, error: String) {
        return await withCheckedContinuation { continuation in
            let process = Process()
            
            // Для Docker используем полный путь
            if command == "docker" {
                let dockerPath = "/usr/local/bin/docker"
                process.executableURL = URL(fileURLWithPath: dockerPath)
                process.arguments = arguments
                
                // Устанавливаем переменную окружения для пользовательского Docker socket
                var environment = ProcessInfo.processInfo.environment
                let userSocketPath = "unix:///Users/\(NSUserName())/.docker/run/docker.sock"
                environment["DOCKER_HOST"] = userSocketPath
                process.environment = environment
            } else {
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = [command] + arguments
            }
            
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            
            process.standardOutput = outputPipe
            process.standardError = errorPipe
            
            var output = ""
            var error = ""
            var hasCompleted = false
            
            // Таймер для timeout
            let timer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { _ in
                if !hasCompleted {
                    hasCompleted = true
                    process.terminate()
                    continuation.resume(returning: (false, output, "Timeout: операция превысила \(timeout) секунд"))
                }
            }
            
            process.terminationHandler = { _ in
                timer.invalidate()
                
                if !hasCompleted {
                    hasCompleted = true
                    
                    let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    
                    output = String(data: outputData, encoding: .utf8) ?? ""
                    error = String(data: errorData, encoding: .utf8) ?? ""
                    
                    let success = process.terminationStatus == 0
                    continuation.resume(returning: (success, output, error))
                }
            }
            
            do {
                try process.run()
            } catch {
                timer.invalidate()
                if !hasCompleted {
                    hasCompleted = true
                    continuation.resume(returning: (false, "", "Ошибка запуска команды: \(error.localizedDescription)"))
                }
            }
        }
    }
}
