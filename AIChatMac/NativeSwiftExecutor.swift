//
//  NativeSwiftExecutor.swift
//  AIChatMac
//
//  Created by Николай Игнатов on 19.08.2025.
//

import Foundation

// Альтернативный исполнитель Swift кода без Docker
final class NativeSwiftExecutor {
    private let tempDirectory: URL
    
    init() {
        self.tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("NativeSwiftPlayground")
    }
    
    func executeSwiftCode(_ code: String) async -> SwiftExecutionResult {
        let startTime = Date()
        
        do {
            // Создаем временную директорию
            try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
            
            // Создаем Swift файл
            let swiftFile = tempDirectory.appendingPathComponent("playground.swift")
            try code.write(to: swiftFile, atomically: true, encoding: .utf8)
            
            // Выполняем Swift код напрямую
            let result = await runNativeSwift(swiftFile: swiftFile)
            
            let executionTime = Date().timeIntervalSince(startTime)
            
            // Очищаем временные файлы
            try? FileManager.default.removeItem(at: tempDirectory)
            
            return SwiftExecutionResult(
                success: result.success,
                code: code,
                output: result.output,
                error: result.error,
                executionTime: executionTime
            )
            
        } catch {
            let executionTime = Date().timeIntervalSince(startTime)
            let errorMsg = "Ошибка подготовки файлов: \(error.localizedDescription)"
            return SwiftExecutionResult(
                success: false,
                code: code,
                output: "",
                error: errorMsg,
                executionTime: executionTime
            )
        }
    }
    
    private func runNativeSwift(swiftFile: URL) async -> (success: Bool, output: String, error: String) {
        return await withCheckedContinuation { continuation in
            let process = Process()
            
            // Ищем Swift в стандартных местах
            let possibleSwiftPaths = [
                "/usr/bin/swift",
                "/usr/local/bin/swift",
                "/opt/homebrew/bin/swift"
            ]
            
            var swiftPath: String?
            for path in possibleSwiftPaths {
                if FileManager.default.fileExists(atPath: path) {
                    swiftPath = path
                    break
                }
            }
            
            guard let validSwiftPath = swiftPath else {
                continuation.resume(returning: (false, "", "Swift компилятор не найден в системе"))
                return
            }
            
            process.executableURL = URL(fileURLWithPath: validSwiftPath)
            process.arguments = [swiftFile.path]
            
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            
            process.standardOutput = outputPipe
            process.standardError = errorPipe
            
            // Устанавливаем таймер на 30 секунд
            let timer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: false) { _ in
                process.terminate()
            }
            
            process.terminationHandler = { _ in
                timer.invalidate()
                
                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                
                let output = String(data: outputData, encoding: .utf8) ?? ""
                let error = String(data: errorData, encoding: .utf8) ?? ""
                
                let success = process.terminationStatus == 0
                continuation.resume(returning: (success, output, error))
            }
            
            do {
                try process.run()
            } catch {
                timer.invalidate()
                continuation.resume(returning: (false, "", "Ошибка запуска Swift: \(error.localizedDescription)"))
            }
        }
    }
}
