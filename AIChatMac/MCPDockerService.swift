//
//  MCPDockerService.swift
//  AIChatMac
//
//  Created by Николай Игнатов on 19.08.2025.
//

import Foundation

// MCP сервис для выполнения кода в Docker
final class MCPDockerService {
    private let baseURL: String
    
    init(baseURL: String = "http://localhost:5002") {
        self.baseURL = baseURL
    }
    
    // Выполнение Swift кода через MCP Docker сервис
    func executeSwiftCode(_ code: String) async -> SwiftExecutionResult {
        let startTime = Date()
        
        do {
            guard let url = URL(string: "\(baseURL)/execute/swift") else {
                throw MCPError.invalidURL
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let payload = [
                "code": code,
                "language": "swift",
                "timeout": 30
            ] as [String : Any]
            
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw MCPError.invalidResponse
            }
            
            if httpResponse.statusCode == 200 {
                let result = try parseResponse(data)
                let executionTime = Date().timeIntervalSince(startTime)
                
                return SwiftExecutionResult(
                    success: result.success,
                    code: code,
                    output: result.output,
                    error: result.error,
                    executionTime: executionTime
                )
            } else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw MCPError.serverError(errorMessage)
            }
            
        } catch {
            let executionTime = Date().timeIntervalSince(startTime)
            let errorMsg = "MCP Docker ошибка: \(error.localizedDescription)"
            
            return SwiftExecutionResult(
                success: false,
                code: code,
                output: "",
                error: errorMsg,
                executionTime: executionTime
            )
        }
    }
    
    // Проверка доступности MCP Docker сервиса
    func checkHealth() async -> Bool {
        do {
            guard let url = URL(string: "\(baseURL)/health") else {
                return false
            }
            
            let (_, response) = try await URLSession.shared.data(from: url)
            
            if let httpResponse = response as? HTTPURLResponse {
                return httpResponse.statusCode == 200
            }
            
            return false
        } catch {
            return false
        }
    }
    
    private func parseResponse(_ data: Data) throws -> (success: Bool, output: String, error: String) {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MCPError.invalidJSON
        }
        
        let success = json["success"] as? Bool ?? false
        let output = json["output"] as? String ?? ""
        let error = json["error"] as? String ?? ""
        
        return (success, output, error)
    }
}

// MARK: - Errors
enum MCPError: LocalizedError {
    case invalidURL
    case invalidResponse
    case invalidJSON
    case serverError(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Неверный URL MCP сервиса"
        case .invalidResponse:
            return "Неверный ответ от MCP сервиса"
        case .invalidJSON:
            return "Неверный JSON ответ"
        case .serverError(let message):
            return "Ошибка MCP сервера: \(message)"
        }
    }
}
