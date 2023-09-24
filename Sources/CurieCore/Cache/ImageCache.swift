import CurieCommon
import Foundation
import TSCBasic

enum Target {
    case reference(String)
    case ephemeral
}

struct ImageItem: Equatable {
    var reference: ImageReference
    var createAt: Date
    var size: MemorySize
}

protocol ImageCache {
    func makeImageReference(_ reference: String) throws -> ImageReference
    func findReference(_ reference: String) throws -> ImageReference
    func findImageReference(_ reference: String) throws -> ImageReference
    func findContainerReference(_ reference: String) throws -> ImageReference
    func listImages() throws -> [ImageItem]
    func listContainers() throws -> [ImageItem]
    func removeImage(_ reference: ImageReference) throws

    @discardableResult
    func cloneImage(source: ImageReference, target: Target) throws -> ImageReference
    func moveImage(source: ImageReference, target: ImageReference) throws
    func path(to reference: ImageReference) -> AbsolutePath
}

final class DefaultImageCache: ImageCache {
    let bundleParser: VMBundleParser
    let wallClock: WallClock
    let system: System
    let fileSystem: CurieCommon.FileSystem

    init(
        bundleParser: VMBundleParser,
        wallClock: WallClock,
        system: System,
        fileSystem: CurieCommon.FileSystem
    ) {
        self.bundleParser = bundleParser
        self.wallClock = wallClock
        self.system = system
        self.fileSystem = fileSystem
    }

    func makeImageReference(_ reference: String) throws -> ImageReference {
        let descriptor = try ImageDescriptor(reference: reference)
        let relativePath = RelativePath(reference)
        let absolutePath = imagesAbsolutePath.appending(relativePath)
        guard !fileSystem.exists(at: absolutePath) else {
            throw CoreError
                .generic(
                    "Cannot create empty reference, image with given reference (\(CurieCore.Constants.referenceFormat))"
                        + " already exists"
                )
        }
        return ImageReference(id: ImageID.make(), descriptor: descriptor, type: .image)
    }

    func findReference(_ reference: String) throws -> ImageReference {
        if let reference = try? findImageReference(reference) {
            return reference
        }
        return try findContainerReference(reference)
    }

    func findImageReference(_ reference: String) throws -> ImageReference {
        try findReference(reference, type: .image)
    }

    func findContainerReference(_ reference: String) throws -> ImageReference {
        try findReference(reference, type: .container)
    }

    func listImages() throws -> [ImageItem] {
        let references = try listImages(at: imagesAbsolutePath, basePath: imagesAbsolutePath, type: .image)
        return try items(from: references)
    }

    func listContainers() throws -> [ImageItem] {
        let references = try listImages(at: containersAbsolutePath, basePath: containersAbsolutePath, type: .container)
        return try items(from: references)
    }

    func removeImage(_ reference: ImageReference) throws {
        let absolutePath = path(to: reference)
        try fileSystem.remove(at: absolutePath)
        try removeEmptySubdirectories(of: imagesAbsolutePath)
        try removeEmptySubdirectories(of: containersAbsolutePath)
    }

    @discardableResult
    func cloneImage(source: ImageReference, target: Target) throws -> ImageReference {
        let sourceAbsolutePath = path(to: source)
        let targetId = ImageID.make()
        let targetDescriptor = try target.imageDescriptor(source: source, imageId: targetId)
        let targetReference = ImageReference(id: targetId, descriptor: targetDescriptor, type: target.imageType())
        let targetAbsolutePath = path(to: targetReference)
        guard sourceAbsolutePath != targetAbsolutePath else {
            throw CoreError.generic("Cannot clone, target reference is the same as source")
        }
        try fileSystem.createDirectory(at: targetAbsolutePath.parentDirectory)
        try fileSystem.copy(from: sourceAbsolutePath, to: targetAbsolutePath)

        let bundle = VMBundle(path: targetAbsolutePath)
        var state = try bundleParser.readState(from: bundle)
        state.id = targetId
        state.createdAt = wallClock.now()
        try bundleParser.writeState(state, toBundle: bundle)

        return targetReference
    }

    func moveImage(source: ImageReference, target: ImageReference) throws {
        let sourceAbsolutePath = path(to: source)
        let targetAbsolutePath = path(to: target)

        try removeImage(target)

        try fileSystem.createDirectory(at: targetAbsolutePath)
        try system.execute(["mv", sourceAbsolutePath.pathString, targetAbsolutePath.parentDirectory.pathString])

        try removeEmptySubdirectories(of: containersAbsolutePath)
    }

    func path(to reference: ImageReference) -> AbsolutePath {
        storeAbsolutePath(reference.type).appending(reference.descriptor.relativePath())
    }

    // MARK: - Private

    private func items(from references: [ImageReference]) throws -> [ImageItem] {
        let items = try references.map {
            let bundle = VMBundle(path: path(to: $0))
            let state = try bundleParser.readState(from: bundle)
            return try ImageItem(
                reference: $0,
                createAt: state.createdAt,
                size: fileSystem.directorySize(at: path(to: $0))
            )
        }
        return items
    }

    private func storeAbsolutePath(_ type: ImageType) -> AbsolutePath {
        switch type {
        case .container:
            return containersAbsolutePath
        case .image:
            return imagesAbsolutePath
        }
    }

    private var imagesAbsolutePath: AbsolutePath {
        fileSystem.homeDirectory
            .appending(component: ".curie")
            .appending(component: "images")
    }

    private var containersAbsolutePath: AbsolutePath {
        fileSystem.homeDirectory
            .appending(component: ".curie")
            .appending(component: "containers")
    }

    func findReference(_ reference: String, type: ImageType) throws -> ImageReference {
        let descriptor = try ImageDescriptor(reference: reference)
        let absolutePath = storeAbsolutePath(type).appending(descriptor.relativePath())
        guard fileSystem.exists(at: absolutePath) else {
            switch type {
            case .container:
                guard let image = try listContainers().first(where: { $0.reference.id.description == reference }) else {
                    throw CoreError.generic("Cannot find the image")
                }
                return image.reference
            case .image:
                guard let image = try listImages().first(where: { $0.reference.id.description == reference }) else {
                    throw CoreError.generic("Cannot find the image")
                }
                return image.reference
            }
        }
        let bundle = VMBundle(path: absolutePath)
        let state = try bundleParser.readState(from: bundle)
        return ImageReference(id: state.id, descriptor: descriptor, type: type)
    }

    private func listImages(at path: AbsolutePath, basePath: AbsolutePath, type: ImageType) throws -> [ImageReference] {
        var result: [ImageReference] = []

        guard fileSystem.exists(at: path) else {
            return []
        }

        let list = try fileSystem.list(at: path)

        let directories = Set(list.compactMap {
            if case let .directory(directory) = $0 {
                return path.appending(directory.path)
            }
            return nil
        })

        let images = Set(directories.filter { bundleParser.canParseConfig(at: VMBundle(path: $0).config) })
        let paths = images.map { $0.relative(to: basePath) }
        let references = try paths.map { try findReference($0.pathString, type: type) }

        result.append(contentsOf: references)

        let subdirectories = directories.subtracting(images)

        try subdirectories.forEach {
            let references = try listImages(at: $0, basePath: basePath, type: type)
            result.append(contentsOf: references)
        }

        return result
    }

    @discardableResult
    private func removeEmptySubdirectories(of path: AbsolutePath) throws -> Bool {
        guard fileSystem.exists(at: path) else {
            return true
        }

        let list = try fileSystem.list(at: path)

        let directories = list.compactMap {
            if case let .directory(directory) = $0 {
                return path.appending(directory.path)
            }
            return nil
        }

        var empty = true
        try directories.forEach { path in
            empty = try empty && removeEmptySubdirectories(of: path)
        }

        let files = list.compactMap {
            if case let .file(file) = $0 {
                return file
            }
            return nil
        }

        guard files.isEmpty, empty else {
            return false
        }

        try fileSystem.remove(at: path)

        return true
    }
}

private extension ImageDescriptor {
    func relativePath() -> RelativePath {
        if let tag {
            return RelativePath("\(repository):\(tag)")
        } else {
            return RelativePath(repository)
        }
    }
}

private extension Target {
    func imageDescriptor(source: ImageReference, imageId: ImageID) throws -> ImageDescriptor {
        switch self {
        case let .reference(reference):
            return try ImageDescriptor(reference: reference)
        case .ephemeral:
            return ImageDescriptor(
                repository: "@\(imageId.description)/\(source.descriptor.repository)",
                tag: source.descriptor.tag
            )
        }
    }

    func imageType() -> ImageType {
        switch self {
        case .reference:
            return .image
        case .ephemeral:
            return .container
        }
    }
}
