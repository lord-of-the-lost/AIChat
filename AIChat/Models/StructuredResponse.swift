//
//  StructuredResponse.swift
//  AIChat
//
//  Created by Николай Игнатов on 11.08.2025.
//

struct StructuredResponse: Decodable {
    let isSuccess: Bool
    let content: [String: String]
    let error: String?
}
