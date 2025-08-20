//
//  ExpandingTextEditor.swift
//  AIChatMac
//
//  Created by Николай Игнатов on 19.08.2025.
//

import SwiftUI

struct ExpandingTextEditor: View {
    @Binding var text: String
    let placeholder: String
    
    @State private var textHeight: CGFloat = 35
    
    private let minHeight: CGFloat = 35
    private let maxHeight: CGFloat = 120
    private let lineHeight: CGFloat = 20
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            // Invisible text for height calculation
            Text(text.isEmpty ? "W" : text)
                .font(.system(size: 13))
                .opacity(0)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    GeometryReader { geometry in
                        Color.clear
                            .onAppear {
                                updateHeight(geometry.size.height)
                            }
                            .onChange(of: text) {
                                updateHeight(geometry.size.height)
                            }
                    }
                )
            
            // Placeholder
            if text.isEmpty {
                Text(placeholder)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                    .allowsHitTesting(false)
            }
            
            // Text editor
            TextEditor(text: $text)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
                .scrollDisabled(textHeight <= maxHeight)
        }
        .frame(height: textHeight)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(NSColor.controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )
        )
    }
    
    private func updateHeight(_ contentHeight: CGFloat) {
        let newHeight = max(minHeight, min(maxHeight, contentHeight + 16))
        if abs(newHeight - textHeight) > 1 {
            withAnimation(.easeInOut(duration: 0.1)) {
                textHeight = newHeight
            }
        }
    }
}
