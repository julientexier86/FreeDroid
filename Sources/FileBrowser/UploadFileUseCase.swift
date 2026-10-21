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
        let handle = try FileHandle(forReadingFrom: source)
        defer { try? handle.close() }

        var offset: Int64 = 0
        while let chunk = try handle.read(upToCount: 4 * 1024 * 1024), !chunk.isEmpty {
            try await fileRepository.write(destination, data: chunk, offset: offset)
            offset += Int64(chunk.count)
        }
    }
}
