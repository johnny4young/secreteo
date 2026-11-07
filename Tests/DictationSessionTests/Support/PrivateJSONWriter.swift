import Darwin
import Foundation

enum PrivateJSONWriterError: Error, Equatable {
    case outputAlreadyExists
    case publicationFailed
}

/// Publishes benchmark evidence without exposing a partial file or replacing
/// an earlier run.
enum PrivateJSONWriter {
    static func write<Document: Encodable>(
        _ document: Document,
        to output: URL
    ) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(document) + Data("\n".utf8)
        let parent = output.deletingLastPathComponent()
        try prepareDirectory(parent)
        let temporary = parent.appendingPathComponent(
            ".\(output.lastPathComponent).\(UUID().uuidString).tmp")
        try publish(data, temporary: temporary, output: output, parent: parent)
    }

    private static func prepareDirectory(_ parent: URL) throws {
        var isDirectory: ObjCBool = false
        let parentExisted = FileManager.default.fileExists(
            atPath: parent.path,
            isDirectory: &isDirectory)
        if parentExisted && !isDirectory.boolValue {
            throw PrivateJSONWriterError.publicationFailed
        }
        if !parentExisted {
            try FileManager.default.createDirectory(
                at: parent,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: parent.path)
        }
    }

    private static func publish(
        _ data: Data,
        temporary: URL,
        output: URL,
        parent: URL
    ) throws {
        var descriptor = Darwin.open(
            temporary.path,
            O_WRONLY | O_CREAT | O_EXCL,
            S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            throw PrivateJSONWriterError.publicationFailed
        }
        defer {
            if descriptor >= 0 { Darwin.close(descriptor) }
            try? FileManager.default.removeItem(at: temporary)
        }
        do {
            try writeAll(data, descriptor: descriptor)
            let synced = Darwin.fsync(descriptor) == 0
            let closed = Darwin.close(descriptor) == 0
            descriptor = -1
            guard synced, closed else { throw PrivateJSONWriterError.publicationFailed }
            guard Darwin.link(temporary.path, output.path) == 0 else {
                if errno == EEXIST {
                    throw PrivateJSONWriterError.outputAlreadyExists
                }
                throw PrivateJSONWriterError.publicationFailed
            }
            let directoryDescriptor = Darwin.open(parent.path, O_RDONLY)
            guard directoryDescriptor >= 0 else {
                throw PrivateJSONWriterError.publicationFailed
            }
            defer { Darwin.close(directoryDescriptor) }
            guard Darwin.fsync(directoryDescriptor) == 0 else {
                throw PrivateJSONWriterError.publicationFailed
            }
        } catch let error as PrivateJSONWriterError {
            throw error
        } catch {
            throw PrivateJSONWriterError.publicationFailed
        }
    }

    private static func writeAll(_ data: Data, descriptor: Int32) throws {
        try data.withUnsafeBytes { buffer in
            guard var cursor = buffer.baseAddress else { return }
            var remaining = buffer.count
            while remaining > 0 {
                let written = Darwin.write(descriptor, cursor, remaining)
                if written < 0 && errno == EINTR { continue }
                guard written > 0 else {
                    throw PrivateJSONWriterError.publicationFailed
                }
                cursor = cursor.advanced(by: written)
                remaining -= written
            }
        }
    }
}
