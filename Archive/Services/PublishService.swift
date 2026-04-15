import Foundation

struct PublishService {
    let connectors: [any PublishConnector]

    init(connectors: [any PublishConnector] = []) {
        self.connectors = connectors
    }
}
