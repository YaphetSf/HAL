import SwiftUI

@main
struct HALApp: App {
    private let installationContext = HALInstallationContext.live()

    var body: some Scene {
        Window("HAL", id: "main") {
            Group {
                if installationContext.requirement == .none {
                    ControlCenterView()
                } else {
                    HALInstallationView(context: installationContext)
                }
            }
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: installationContext.requirement == .none ? 960 : 560,
                     height: installationContext.requirement == .none ? 660 : 460)
        .windowResizability(.contentMinSize)
    }
}
