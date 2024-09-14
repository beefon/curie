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

public enum Operation {
    case build(BuildParameters)
    case clone(CloneParameters)
    case download(DownloadParameters)
}

public protocol Interactor {
    func execute(_ operation: Operation) throws
}

protocol AsyncInteractor: AnyObject {
    associatedtype Parameters

    func execute(parameters: Parameters) async throws
}

final class DefaultInteractor: Interactor {
    private let buildInteractor: BuildInteractor
    private let cloneInteractor: CloneInteractor
    private let downloadInteractor: DownloadInteractor
    private let runLoop: CurieCommon.RunLoop

    init(
        buildInteractor: BuildInteractor,
        cloneInteractor: CloneInteractor,
        downloadInteractor: DownloadInteractor,
        runLoop: CurieCommon.RunLoop
    ) {
        self.buildInteractor = buildInteractor
        self.cloneInteractor = cloneInteractor
        self.downloadInteractor = downloadInteractor
        self.runLoop = runLoop
    }

    func execute(_ operation: Operation) throws {
        try runLoop.run { [self] _ in
            switch operation {
            case let .build(parameters):
                try await buildInteractor.execute(parameters: parameters)
            case let .clone(parameters):
                try await cloneInteractor.execute(parameters: parameters)
            case let .download(parameters):
                try await downloadInteractor.execute(parameters: parameters)
            }
        }
    }
}
