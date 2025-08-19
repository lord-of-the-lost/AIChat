//
//  AIChatMacApp.swift
//  AIChatMac
//
//  Created by Николай Игнатов on 19.08.2025.
//

import SwiftUI

@main
struct AIChatMacApp: App {
    var body: some Scene {
        WindowGroup {
            MacStartView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}
