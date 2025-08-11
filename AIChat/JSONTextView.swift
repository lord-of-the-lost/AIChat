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
        Text(attributed)
            .font(.system(.body, design: .monospaced))
            .textSelection(.enabled)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(8)
            .fixedSize(horizontal: false, vertical: true)
    }
    
    // Пробуем сначала pretty-print JSON, если можно
    private var prettyJSONString: String {
        guard let data = jsonString.data(using: .utf8) else { return jsonString }
        if let obj = try? JSONSerialization.jsonObject(with: data) {
            if let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
               let s = String(data: pretty, encoding: .utf8) {
                return s
            }
        }
        return jsonString
    }
    
    // Конвертим в AttributedString с подсветкой
    private var attributed: AttributedString {
        makeAttributed(from: prettyJSONString)
    }
    
    private func makeAttributed(from string: String) -> AttributedString {
        let ns = NSString(string: string)
        let fullRange = NSRange(location: 0, length: ns.length)
        let mutable = NSMutableAttributedString(string: string)
        
        // Базовые атрибуты: моноширинный шрифт + цвет по умолчанию
        let font = UIFont.monospacedSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize, weight: .regular)
        mutable.addAttribute(.font, value: font, range: fullRange)
        mutable.addAttribute(.foregroundColor, value: UIColor.label, range: fullRange)
        
        // Шаблоны и цвета (порядок важен: ключи должны быть подсвечены раньше строк)
        let patterns: [String: UIColor] = [
            // ключ — строка в кавычках, за которой следует двоеточие (lookahead)
            #"\"([^\"\\]*(?:\\.[^\"\\]*)*)\"(?=\s*:)"#: UIColor.systemBlue,
            // обычная строка в кавычках (значение)
            #"\"([^\"\\]*(?:\\.[^\"\\]*)*)\""#: UIColor.systemGreen,
            // true/false/null
            #"\b(true|false|null)\b"#: UIColor.systemPurple,
            // числа (целые и дробные, экспоненциальные)
            #"\b-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?\b"#: UIColor.systemOrange
        ]
        
        for (pattern, color) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { continue }
            regex.enumerateMatches(in: string, options: [], range: fullRange) { match, _, _ in
                guard let match = match else { return }
                let matchRange = match.range(at: 0)
                mutable.addAttribute(.foregroundColor, value: color, range: matchRange)
            }
        }
        
        return AttributedString(mutable)
    }
}
