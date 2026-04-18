import Foundation

final class FileCoordinatorIO: @unchecked Sendable {
    private let fileManager = FileManager.default

    func readString(at url: URL) throws -> String {
        var coordinationError: NSError?
        var readError: Error?
        var content: String?

        let coordinator = NSFileCoordinator(filePresenter: nil)
        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinatedURL in
            do {
                let data = try Data(contentsOf: coordinatedURL)
                guard let string = String(data: data, encoding: .utf8) else {
                    throw CocoaError(.fileReadInapplicableStringEncoding)
                }
                content = string.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            } catch {
                readError = error
            }
        }

        if let coordinationError {
            throw coordinationError
        }
        if let readError {
            throw readError
        }
        return content ?? ""
    }

    func writeAtomically(_ string: String, to url: URL) throws {
        let normalized = string.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        guard let data = normalized.data(using: .utf8) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }

        let tempURL = url.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).tmp")
        try data.write(to: tempURL, options: .atomic)

        var coordinationError: NSError?
        var writeError: Error?
        let coordinator = NSFileCoordinator(filePresenter: nil)
        coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { coordinatedURL in
            do {
                _ = try fileManager.replaceItemAt(coordinatedURL, withItemAt: tempURL)
            } catch {
                writeError = error
            }
        }

        if let coordinationError {
            throw coordinationError
        }
        if let writeError {
            throw writeError
        }
    }

    func createDirectoryIfNeeded(at url: URL) throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func createFile(at url: URL, contents: String) throws {
        let data = Data(contents.utf8)
        try createDirectoryIfNeeded(at: url.deletingLastPathComponent())
        guard fileManager.createFile(atPath: url.path, contents: data) else {
            throw CocoaError(.fileWriteUnknown)
        }
    }

    func moveItem(at sourceURL: URL, to destinationURL: URL) throws {
        var coordinationError: NSError?
        var moveError: Error?
        let coordinator = NSFileCoordinator(filePresenter: nil)
        coordinator.coordinate(writingItemAt: sourceURL, options: .forMoving, writingItemAt: destinationURL, options: [], error: &coordinationError) { source, destination in
            do {
                try fileManager.moveItem(at: source, to: destination)
            } catch {
                moveError = error
            }
        }

        if let coordinationError {
            throw coordinationError
        }
        if let moveError {
            throw moveError
        }
    }

    func trashItem(at url: URL) throws {
        var resultingURL: NSURL?
        try fileManager.trashItem(at: url, resultingItemURL: &resultingURL)
    }

    func markdownFileURLs(in rootURL: URL) throws -> [URL] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isDirectoryKey, .isPackageKey, .isSymbolicLinkKey, .nameKey, .isHiddenKey]
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else {
            return []
        }

        var urls: [URL] = []
        for case let url as URL in enumerator {
            let values: URLResourceValues
            do {
                values = try url.resourceValues(forKeys: keys)
            } catch {
                continue
            }
            if values.isSymbolicLink == true {
                enumerator.skipDescendants()
                continue
            }
            if values.isDirectory == true, values.name == ".archive" {
                enumerator.skipDescendants()
                continue
            }
            if values.isRegularFile == true {
                let ext = url.pathExtension.lowercased()
                if ext == "md" || ext == "markdown" {
                    urls.append(url)
                }
            }
        }
        return urls.sorted { $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending }
    }

    func folderTree(in rootURL: URL) throws -> FolderNode {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isPackageKey, .isHiddenKey, .isSymbolicLinkKey, .nameKey]
        let contents = try fileManager.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: Array(keys))

        var childFolders: [FolderNode] = []
        for url in contents {
            do {
                let values = try url.resourceValues(forKeys: keys)
                guard values.isDirectory == true else { continue }
                guard values.isPackage != true, values.isHidden != true, values.isSymbolicLink != true else { continue }
                guard values.name != ".archive" else { continue }
                guard let childTree = try? folderTree(in: url) else { continue }
                childFolders.append(childTree)
            } catch {
                continue
            }
        }
        childFolders.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        return FolderNode(url: rootURL, children: childFolders)
    }

    func metadata(for url: URL) throws -> (id: NoteID, token: FileVersionToken, createdAt: Date, modifiedAt: Date) {
        let values = try url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey, .fileSizeKey, .fileResourceIdentifierKey])
        let identifier = values.fileResourceIdentifier.map { String(describing: $0) } ?? url.standardizedFileURL.path
        let normalizedPath = url.standardizedFileURL.path
        return (
            id: NoteID(resourceIdentifier: identifier, path: normalizedPath),
            token: FileVersionToken(modificationDate: values.contentModificationDate, fileSize: values.fileSize.map(Int64.init)),
            createdAt: values.creationDate ?? .distantPast,
            modifiedAt: values.contentModificationDate ?? .distantPast
        )
    }
}
