import AppKit

@main
@MainActor
struct CapsomniaMain {
    static func main() {
        let application = NSApplication.shared
        let delegate = ApplicationController()
        application.delegate = delegate
        application.run()
    }
}

