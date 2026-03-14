import ArgumentParser
import NIOCore
import NIOPosix

struct Main {
    @Option(
        name: [.customLong("certificates"), .customShort("c")],
        help: "A path to the certificates directory",
        completion: .directory
    ) var certificates: String = "Assets/certificates"

    @Argument var gateways: [Gateway] = []

    init() {
    }
}

@main extension Main: AsyncParsableCommand {
    func run() async throws {
        NIOSingletons.groupLoopCountSuggestion = 2

        try await withThrowingTaskGroup(of: Void.self) {
            (tasks: inout ThrowingTaskGroup<Void, any Error>) in

            for gateway: Gateway in self.gateways {
                tasks.addTask {
                    try await gateway.listen()
                }
            }

            defer {
                tasks.cancelAll()
            }

            for try await _: Void in tasks {
                break
            }
        }
    }
}
