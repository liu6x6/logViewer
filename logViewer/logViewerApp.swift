//
//  logViewerApp.swift
//  logViewer
//
//  Created by xiaolong on 2026/5/29.
//

import SwiftUI

@main
struct logViewerApp: App {
    @StateObject private var connectionManager = ConnectionManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(connectionManager)
                .frame(minWidth: 1280, minHeight: 820)
        }
    }
}
