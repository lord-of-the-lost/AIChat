//
//  JSONTextView.swift
//  AIChat
//
//  Created by Николай Игнатов on 11.08.2025.
//

import SwiftUI

struct JSONTextView: View {
    let jsonString: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(formatJSON(jsonString), id: \.id) { token in
                Text(token.text)
                    .foregroundColor(token.color)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
    
    private func formatJSON(_ string: String) -> [JSONToken] {
        var tokens: [JSONToken] = []
        
        // Простая подсветка — через разбор по типам символов
        let pattern = #"(".*?")|(\b\d+\b)|(true|false|null)|([{}[\]:,])"#
        let regex = try? NSRegularExpression(pattern: pattern, options: [])
        let nsString = string as NSString
        var lastLocation = 0
        
        regex?.enumerateMatches(in: string, options: [], range: NSRange(location: 0, length: nsString.length)) { match, _, _ in
            guard let match = match else { return }
            
            if match.range.location > lastLocation {
                let text = nsString.substring(with: NSRange(location: lastLocation, length: match.range.location - lastLocation))
                tokens.append(JSONToken(text: text, color: .primary))
            }
            
            let matchText = nsString.substring(with: match.range)
            
            if match.range(at: 1).location != NSNotFound {
                // Строки
                if matchText.hasPrefix("\"") && matchText.hasSuffix("\"") && !matchText.contains(":") {
                    tokens.append(JSONToken(text: matchText, color: .green))
                } else {
                    tokens.append(JSONToken(text: matchText, color: .blue)) // ключи
                }
            } else if match.range(at: 2).location != NSNotFound {
                // Числа
                tokens.append(JSONToken(text: matchText, color: .orange))
            } else if match.range(at: 3).location != NSNotFound {
                // true / false / null
                tokens.append(JSONToken(text: matchText, color: .purple))
            } else {
                // Фигурные скобки, запятые и т.д.
                tokens.append(JSONToken(text: matchText, color: .primary))
            }
            
            lastLocation = match.range.location + match.range.length
        }
        
        if lastLocation < nsString.length {
            let text = nsString.substring(from: lastLocation)
            tokens.append(JSONToken(text: text, color: .primary))
        }
        
        return tokens
    }
}
