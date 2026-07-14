import CoreGraphics
import Foundation

@MainActor
final class CapsLockMonitor {
    typealias Handler = (_ capsLockOn: Bool, _ lidClosed: Bool?) -> Void

    private var timer: Timer?
    private let handler: Handler

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    func start() {
        stop()
        tick()

        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
        timer.tolerance = 0.05
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        let capsLockOn = CGEventSource.flagsState(.hidSystemState).contains(.maskAlphaShift)
        handler(capsLockOn, ClamshellStateReader.isClosed())
    }
}

