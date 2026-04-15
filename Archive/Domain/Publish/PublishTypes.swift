import Foundation

struct PublishTarget: Hashable, Sendable {
    let identifier: String
    let displayName: String
}

protocol PublishConnector: Sendable {
    var target: PublishTarget { get }
}

