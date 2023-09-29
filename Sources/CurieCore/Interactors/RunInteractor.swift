import Combine
import CurieCommon
import Foundation
import TSCBasic
import Virtualization

public struct RunInteractorContext {
    public var reference: String
    public var noWindow: Bool
    public var recoveryMode: Bool

    public init(
        reference: String,
        noWindow: Bool,
        recoveryMode: Bool
    ) {
        self.reference = reference
        self.noWindow = noWindow
        self.recoveryMode = recoveryMode
    }
}

public protocol RunInteractor {
    func execute(with context: RunInteractorContext) throws
}

public final class DefaultRunInteractor: RunInteractor {
    private let configurator: VMConfigurator
    private let imageRunner: ImageRunner
    private let imageCache: ImageCache
    private let system: System
    private let console: Console

    private var cancellables = Set<AnyCancellable>()

    init(
        configurator: VMConfigurator,
        imageRunner: ImageRunner,
        imageCache: ImageCache,
        system: System,
        console: Console
    ) {
        self.configurator = configurator
        self.imageRunner = imageRunner
        self.imageCache = imageCache
        self.system = system
        self.console = console
    }

    public func execute(with context: RunInteractorContext) throws {
        console.text("Run image \(context.reference)")

        let sourceReference = try imageCache.findImageReference(context.reference)
        let targetReference = try imageCache.cloneImage(source: sourceReference, target: .newReference)

        let bundle = VMBundle(path: imageCache.path(to: targetReference))
        let vm = try configurator.loadVM(with: bundle)
        let options = VMStartOptions(
            startUpFromMacOSRecovery: context.recoveryMode,
            noWindow: context.noWindow
        )

        vm.events
            .filter { $0 == .imageDidStop || $0 == .imageStopFailed }
            .sink { [imageCache, console] _ in
                do {
                    try imageCache.removeImage(targetReference)
                } catch {
                    console.error(error.localizedDescription)
                }
            }
            .store(in: &cancellables)

        try imageRunner.run(vm: vm, bundle: bundle, options: options)
    }
}
