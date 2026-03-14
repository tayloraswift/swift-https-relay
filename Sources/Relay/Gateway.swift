import ArgumentParser
import NIOCore
import NIOPosix
import NIOSSL

#if canImport(Glibc)
@preconcurrency import Glibc
@preconcurrency import SwiftGlibc
#elseif canImport(Darwin)
import Darwin
#endif

func print(_ items: Any..., separator: String = " ", terminator: String = "\n") {
    for item: Any in items {
        Swift.print(item, separator: "", terminator: separator)
    }

    Swift.print(terminator, terminator: "")

    if  terminator.contains(where: \.isNewline) {
        fflush(stdout)
    }
}

struct Gateway: Sendable {
    /// A hostname, which may not be publicly resolvable.
    let host: String
    /// A port to direct traffic for the ``host`` to.
    let port: Int
    /// A port to bind to, allowing external traffic to reach the ``host``.
    let portBinding: Int
    /// A path to a directory containing certificates, if this gateway should be secured.
    let certificateDirectory: String?

    init(host: String, port: Int, portBinding: Int, certificateDirectory: String? = nil) {
        self.host = host
        self.port = port
        self.portBinding = portBinding
        self.certificateDirectory = certificateDirectory
    }
}
extension Gateway: CustomStringConvertible {
    var description: String {
        var string: String = "\(self.host):\(self.port)@\(self.portBinding)"

        if  let certificateDirectory: String = self.certificateDirectory {
            string += ":\(certificateDirectory)"
        }

        return string
    }
}
extension Gateway: LosslessStringConvertible {
    init?(_ string: String) {
        guard
        let at: String.Index = string.firstIndex(of: "@"),
        let colon: String.Index = string[..<at].lastIndex(of: ":"),
        let port: Int = .init(string[string.index(after: colon) ..< at]) else {
            return nil
        }

        let certificateDirectory: String?

        let i: String.Index = string.index(after: at)
        let j: String.Index
        if  let colon: String.Index = string[i...].firstIndex(of: ":") {
            j = colon
            certificateDirectory = .init(string[string.index(after: colon)...])
        } else {
            j = string.endIndex
            certificateDirectory = nil
        }

        guard
        let portBinding: Int = .init(string[i ..< j]) else {
            return nil
        }

        self.init(
            host: String.init(string[..<colon]),
            port: port,
            portBinding: portBinding,
            certificateDirectory: certificateDirectory
        )
    }
}
extension Gateway: ExpressibleByArgument {
}
extension Gateway {
    func listen() async throws {
        let context: NIOSSLContext? = try self.certificateDirectory.map {
            let privateKey: NIOSSLPrivateKey = try .init(
                file: "\($0)/privkey.pem",
                format: .pem
            )

            let fullChain: [NIOSSLCertificate] = try NIOSSLCertificate.fromPEMFile(
                "\($0)/fullchain.pem"
            )

            var configuration: TLSConfiguration = .makeServerConfiguration(
                certificateChain: fullChain.map(NIOSSLCertificateSource.certificate(_:)),
                privateKey: .privateKey(privateKey)
            )

            //  This is important, if we are doing the TLS encryption on this side, then the
            //  application on the other side is not, and therefore could not possibly support
            //  HTTP/2.
            configuration.applicationProtocols = ["http/1.1"]

            return try .init(configuration: configuration)
        }

        let bootstrap: ServerBootstrap = .init(group: MultiThreadedEventLoopGroup.singleton)
            .serverChannelOption(
                ChannelOptions.socket(.init(SOL_SOCKET), SO_REUSEADDR),
                value: 1
            )
            .childChannelOption(
                ChannelOptions.socket(.init(SOL_SOCKET), SO_REUSEADDR),
                value: 1
            )
            .childChannelInitializer {
                (incoming: any Channel) in

                let incomingHandler: GatewayHandler
                let outgoingHandler: NIOLoopBound<GatewayHandler>

                (incomingHandler, outgoingHandler) = GatewayHandler.bridge(
                    on: incoming.eventLoop
                )

                let bootstrap: ClientBootstrap = .init(group: incoming.eventLoop)
                    .connectTimeout(.seconds(3))
                    .channelInitializer {
                        (channel: any Channel) in
                        channel.eventLoop.makeCompletedFuture {
                            try channel.pipeline.syncOperations.addHandler(
                                outgoingHandler.value
                            )
                        }
                    }

                do {
                    if  let context: NIOSSLContext {
                        try incoming.pipeline.syncOperations.addHandler(
                            NIOSSLServerHandler(
                                context: context
                            )
                        )
                    }
                    try incoming.pipeline.syncOperations.addHandlers(incomingHandler)
                } catch {
                    return incoming.eventLoop.makeFailedFuture(error)
                }

                let future: EventLoopFuture = bootstrap.connect(
                    host: self.host,
                    port: self.port
                ).map {
                    (channel: any Channel) in

                    print("Forwarding connection to \(self.host):\(self.port)")

                    channel.closeFuture.whenComplete {
                        _ in

                        print("Disconnected from \(self.host):\(self.port)")
                    }
                }

                //  Break reference cycle.
                future.whenFailure {
                    _ in
                    print("Failed to connect to \(self.host):\(self.port)")
                    outgoingHandler.value.unlink()
                }

                return future
            }

        let channel: any Channel = try await bootstrap.bind(
            host: "::",
            port: self.portBinding
        ).get()

        print("Activated gateway \(self)")

        try await channel.closeFuture.get()
    }
}
