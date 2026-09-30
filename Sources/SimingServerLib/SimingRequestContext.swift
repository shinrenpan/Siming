import Hummingbird
import NIOCore

/// Request context for every Siming route. `BasicRequestContext` drops the channel, and with
/// it the TCP peer address that `RateLimitMiddleware` keys on.
public struct SimingRequestContext: RequestContext, RemoteAddressRequestContext {
    public var coreContext: CoreRequestContextStorage
    public let remoteAddress: SocketAddress?

    public init(source: ApplicationRequestContextSource) {
        self.coreContext = .init(source: source)
        self.remoteAddress = source.channel.remoteAddress
    }
}
