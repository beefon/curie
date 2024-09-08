//
// Copyright 2024 Marcin Iwanicki, Tomasz Jarosik, and contributors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

import CurieCommon
import Foundation

public struct CloneInteractorContext {
    public var sourceReference: String
    public var targetReference: String

    public init(sourceReference: String, targetReference: String) {
        self.sourceReference = sourceReference
        self.targetReference = targetReference
    }
}

public protocol CloneInteractor {
    func execute(with context: CloneInteractorContext) throws
}

final class DefaultCloneInteractor: CloneInteractor {
    private let imageCache: ImageCache
    private let console: Console

    init(
        imageCache: ImageCache,
        console: Console
    ) {
        self.imageCache = imageCache
        self.console = console
    }

    func execute(with context: CloneInteractorContext) throws {
        let source = try imageCache.findImageReference(context.sourceReference)

        try imageCache.cloneImage(source: source, target: .reference(context.targetReference))

        console.text("Image has been cloned")
    }
}
