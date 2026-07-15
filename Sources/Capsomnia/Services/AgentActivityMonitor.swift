import CapsomniaAgentCore
import Foundation

@MainActor
final class AgentActivityMonitor {
    typealias Handler = ([AgentActivityRecord]) -> Void

    private let store: AgentActivityStore
    private let handler: Handler
    private var timer: Timer?
    private var lastRecords: [AgentActivityRecord] = []

    init(store: AgentActivityStore = AgentActivityStore(), handler: @escaping Handler) {
        self.store = store
        self.handler = handler
    }

    func start() {
        guard timer == nil else { return }
        refresh()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        lastRecords = []
        handler([])
    }

    func refresh() {
        let records = (try? store.loadVisible()) ?? []
        guard records != lastRecords else { return }
        lastRecords = records
        handler(records)
    }
}
