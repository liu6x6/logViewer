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
    @StateObject private var requestActionCoordinator = NetworkRequestActionCoordinator()

    var body: some Scene {
        WindowGroup {
            ContentView(actionCoordinator: requestActionCoordinator)
                .environmentObject(connectionManager)
                .frame(minWidth: 1280, minHeight: 820)
                .task {
                    requestActionCoordinator.configure(injector: connectionManager.pulseInjector)
                }
        }
        .commands {
            RequestCommands(actionCoordinator: requestActionCoordinator)
        }
    }
}
