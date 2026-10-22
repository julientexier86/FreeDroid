import Foundation
import FreeDroidDomain

public struct UploadFileUseCase: Sendable {
    public let fileRepository: any FileRepository

    public init(fileRepository: any FileRepository) {
        self.fileRepository = fileRepository
    }

    public func callAsFunction(source: URL, destinationFolder: RemotePath) async throws {
        let accessed = source.startAccessingSecurityScopedResource()
        defer {
            if accessed { source.stopAccessingSecurityScopedResource() }
        }

        let destination = destinationFolder.appending(source.lastPathComponent)
        _ = try await fileRepository.upload(from: source, to: destination, progress: nil)
    }
}
