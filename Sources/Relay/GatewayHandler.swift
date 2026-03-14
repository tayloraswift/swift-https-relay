import NIOCore

final class GatewayHandler {
    private var partner: GatewayHandler?

    /// This is an array because the handler can be added to multiple pipelines, for example,
    /// when attempting to connect over IPv4 and IPv6 simultaneously. If we just used an
    /// optional, the context would always disappear since only one connection can succeed.
    private var context: [ChannelHandlerContext]

    private var readPending: Bool

    /// This is mainly for debugging purposes.
    private let side: GatewaySide

    private init(side: GatewaySide) {
        self.partner = nil
        self.context = []
        self.readPending = false
        self.side = side
    }
}
extension GatewayHandler {
    static func bridge(on eventLoop: any EventLoop) -> (
        GatewayHandler,
        NIOLoopBound<GatewayHandler>
    ) {
        let bridge: (GatewayHandler, GatewayHandler) = (
            .init(side: .incoming),
            .init(side: .outgoing)
        )

        bridge.0.partner = bridge.1
        bridge.1.partner = bridge.0

        return (bridge.0, .init(bridge.1, eventLoop: eventLoop))
    }

    func unlink() {
        self.partner = nil
        self.context = []
    }
}
extension GatewayHandler {
    private func partnerWrite(_ data: NIOAny) {
        self.context.first?.write(data, promise: nil)
    }

    private func partnerFlush() {
        self.context.first?.flush()
    }

    private func partnerWriteEOF() {
        self.context.first?.close(mode: .output, promise: nil)
    }

    private func partnerCloseFull() {
        self.context.first?.close(promise: nil)
    }

    private func partnerBecameWritable() {
        if  self.readPending {
            self.readPending = false
            self.context.first?.read()
        }
    }

    private var partnerWritable: Bool {
        self.context.first?.channel.isWritable ?? false
    }
}

extension GatewayHandler: ChannelDuplexHandler {
    typealias InboundIn = NIOAny
    typealias OutboundIn = NIOAny
    typealias OutboundOut = NIOAny

    func handlerAdded(context: ChannelHandlerContext) {
        self.context.append(context)
    }

    func handlerRemoved(context: ChannelHandlerContext) {
        self.context.removeAll { context === $0 }

        if  self.context.isEmpty {
            self.partner = nil
        }
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        self.partner?.partnerWrite(data)
    }

    func channelReadComplete(context: ChannelHandlerContext) {
        self.partner?.partnerFlush()
    }

    func channelInactive(context: ChannelHandlerContext) {
        self.partner?.partnerCloseFull()
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        if  case ChannelEvent.inputClosed = event {
            self.partner?.partnerWriteEOF()
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: any Error) {
        self.partner?.partnerCloseFull()
    }

    func channelWritabilityChanged(context: ChannelHandlerContext) {
        if  context.channel.isWritable {
            self.partner?.partnerBecameWritable()
        }
    }

    func read(context: ChannelHandlerContext) {
        if  case true? = self.partner?.partnerWritable {
            context.read()
        } else {
            self.readPending = true
        }
    }
}
