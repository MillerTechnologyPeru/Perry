import Foundation
import TabularData

// Gathering trainers' examples from files: labeled directories, labeled
// file names, annotation files and tables. These work in Perry; extracting
// features from the examples (body and hand poses, image prints, sound
// features) needs Vision's and CreateML's models and throws.

enum Examples {
    static let videoExtensions: Set<String> = ["mov", "mp4", "m4v", "avi"]
    static let soundExtensions: Set<String> = ["wav", "aif", "aiff", "caf", "mp3", "m4a", "aac", "flac"]

    /// Files by label: a subdirectory of `root` for each label.
    static func byDirectory(_ root: URL, extensions: Set<String>? = nil) throws -> [String: [URL]] {
        var result: [String: [URL]] = [:]
        for directory in try _FileUtilities.getReadableSubdirectoriesOfDirectory(at: root) {
            let files = try _FileUtilities.contents(of: directory).filter {
                !_FileUtilities.isDirectory($0) && (extensions?.contains($0.pathExtension.lowercased()) ?? true)
            }
            if !files.isEmpty { result[directory.lastPathComponent] = files }
        }
        guard !result.isEmpty else { throw MLCreateError.io(reason: "\(root.path) has no labeled subdirectories of files.") }
        return result
    }

    /// Files by label: the part of each file's name before its first
    /// period, hyphen or underscore.
    static func byFileName(_ root: URL, extensions: Set<String>? = nil) throws -> [String: [URL]] {
        var result: [String: [URL]] = [:]
        for file in try _FileUtilities.contents(of: root) where !_FileUtilities.isDirectory(file) {
            guard extensions?.contains(file.pathExtension.lowercased()) ?? true else { continue }
            let name = file.lastPathComponent
            let label = name.split(whereSeparator: { ".-_".contains($0) }).first.map(String.init) ?? name
            result[label, default: []].append(file)
        }
        guard !result.isEmpty else { throw MLCreateError.io(reason: "\(root.path) has no labeled files.") }
        return result
    }

    /// The files of each label split in the proportions given, at random
    /// but in the same proportions for every label.
    static func split<RNG: RandomNumberGenerator>(_ files: [String: [URL]], proportions: [Double],
                                                   generator: inout RNG) -> [[String: [URL]]] {
        var parts = [[String: [URL]]](repeating: [:], count: proportions.count)
        for label in files.keys.sorted() {
            let shuffled = files[label]!.shuffled(using: &generator)
            for (index, range) in MLDataTable.parts(of: shuffled.count, proportions: proportions).enumerated() where !range.isEmpty {
                parts[index][label] = Array(shuffled[range])
            }
        }
        return parts
    }

    /// A table of a column of file paths and a column of their labels.
    static func table(_ files: [String: [URL]], fileColumn: String, labelColumn: String) -> MLDataTable {
        var paths: [MLDataValue] = [], labels: [MLDataValue] = []
        for label in files.keys.sorted() {
            for file in files[label]! { paths.append(.string(file.path)); labels.append(.string(label)) }
        }
        return MLDataTable(CMLTable(names: [fileColumn, labelColumn],
                                    columns: [CMLColumn(values: paths, type: .string), CMLColumn(values: labels, type: .string)]))
    }

    /// A table an annotation file holds, its file column resolved against
    /// the directory of the files it names.
    static func annotations(_ file: URL, directory: URL, fileColumn: String) throws -> MLDataTable {
        var table = try MLDataTable(contentsOf: file)
        let names = table[fileColumn]
        guard names.isValid else { throw MLCreateError.generic(reason: "The annotation file \(file.path) has no column \(fileColumn).") }
        table[fileColumn] = MLUntypedColumn(names.values.map { value -> MLDataValue in
            guard let name = value.stringValue else { return value }
            return .string(name.hasPrefix("/") ? name : directory.appendingPathComponent(name).path)
        })
        return table
    }

    /// The files of each label a table lists.
    static func byLabel(_ table: MLDataTable, fileColumn: String, labelColumn: String) throws -> [String: [URL]] {
        let storage = try table.getImpl()
        let files = try storage.column(name: fileColumn).values, labels = try storage.column(name: labelColumn).values
        var result: [String: [URL]] = [:]
        for (file, label) in zip(files, labels) {
            guard let file = file.stringValue, let label = label.stringValue ?? (label.isValid ? label.description : nil) else { continue }
            result[label, default: []].append(URL(fileURLWithPath: file))
        }
        return result
    }

    /// The error extracting features throws.
    static func featuresUnavailable(_ what: String) -> MLCreateError {
        unavailable("Extracting \(what)")
    }
}

// Image classifiers.

extension MLImageClassifier.DataSource {
    func gatherLabeledImages() throws -> [String: [URL]] {
        switch self {
        case .labeledDirectories(let url): return try Examples.byDirectory(url, extensions: _FileUtilities.imageExtensions)
        case .labeledFiles(let url): return try Examples.byFileName(url, extensions: _FileUtilities.imageExtensions)
        case .filesByLabel(let files): return files
        }
    }
}

// Sound classifiers.

extension MLSoundClassifier.DataSource {
    func gatherLabeledSounds() throws -> [String: [URL]] {
        switch self {
        case .labeledDirectories(let url): return try Examples.byDirectory(url, extensions: Examples.soundExtensions)
        case .labeledFiles(let url): return try Examples.byFileName(url, extensions: Examples.soundExtensions)
        case .filesByLabel(let files): return files
        case .features, .featuresDataFrame:
            throw MLCreateError.generic(reason: "A data source of extracted features has no sound files.")
        }
    }
}

// Text classifiers.

extension MLTextClassifier.DataSource {
    func gatherLabeledTexts() throws -> [String: [String]] {
        switch self {
        case .labeledDirectories(let url):
            var result: [String: [String]] = [:]
            for (label, files) in try Examples.byDirectory(url) {
                result[label] = try files.map { file in
                    guard let text = (try? String(contentsOf: file, encoding: .utf8)) ?? (try? String(contentsOf: file, encoding: .isoLatin1)) else {
                        throw MLCreateError.io(reason: "\(file.path) isn't text.")
                    }
                    return text
                }
            }
            return result
        }
    }
}

// Action and pose classifiers: videos and images by label.

/// What the action, hand action and hand pose classifiers' data sources
/// have in common.
struct MediaSource {
    enum Kind { case directories(URL), files(URL), annotated(file: URL, directory: URL, fileColumn: String, labelColumn: String),
                table(MLDataTable, fileColumn: String, labelColumn: String), keypoints }
    let kind: Kind
    let extensions: Set<String>
    let fileColumn: String
    let labelColumn: String

    func labeledMedia() throws -> [String: [URL]] {
        switch kind {
        case .directories(let url): return try Examples.byDirectory(url, extensions: extensions)
        case .files(let url): return try Examples.byFileName(url, extensions: extensions)
        case .annotated(let file, let directory, let fileColumn, let labelColumn):
            return try Examples.byLabel(Examples.annotations(file, directory: directory, fileColumn: fileColumn),
                                        fileColumn: fileColumn, labelColumn: labelColumn)
        case .table(let table, let fileColumn, let labelColumn):
            return try Examples.byLabel(table, fileColumn: fileColumn, labelColumn: labelColumn)
        case .keypoints:
            throw MLCreateError.generic(reason: "A data source of keypoints has no media files.")
        }
    }

    /// The files and labels as a table; nil for keypoints.
    func annotatedTable() throws -> MLDataTable? {
        switch kind {
        case .annotated(let file, let directory, let fileColumn, _):
            return try Examples.annotations(file, directory: directory, fileColumn: fileColumn)
        case .table(let table, _, _): return table
        case .keypoints: return nil
        default: return Examples.table(try labeledMedia(), fileColumn: fileColumn, labelColumn: labelColumn)
        }
    }

    func stratifiedSplit(proportions: [Double], seed: Int, labelColumn: String) throws -> MLDataTable {
        guard let table = try annotatedTable() else {
            throw MLCreateError.generic(reason: "A data source of keypoints can't be split by its media.")
        }
        let column = table.columnNames.contains(labelColumn) ? labelColumn : self.labelColumn
        return try table.stratifiedSplit(proportions: proportions, on: column, seed: seed)
    }
}

extension MLActionClassifier.DataSource {
    var media: MediaSource {
        let defaults = (file: MLActionClassifier.__Defaults.videoColumnName, label: MLActionClassifier.__Defaults.labelColumnName)
        switch self {
        case .directoryWithVideosAndAnnotation(let url, let file, let videoColumn, let labelColumn, _, _):
            return MediaSource(kind: .annotated(file: file, directory: url, fileColumn: videoColumn, labelColumn: labelColumn),
                               extensions: Examples.videoExtensions, fileColumn: videoColumn, labelColumn: labelColumn)
        case .labeledDirectories(let url):
            return MediaSource(kind: .directories(url), extensions: Examples.videoExtensions, fileColumn: defaults.file, labelColumn: defaults.label)
        case .labeledFiles(let url):
            return MediaSource(kind: .files(url), extensions: Examples.videoExtensions, fileColumn: defaults.file, labelColumn: defaults.label)
        case .labeledVideoData(let table, let videoColumn, let labelColumn, _, _):
            return MediaSource(kind: .table(table, fileColumn: videoColumn, labelColumn: labelColumn),
                               extensions: Examples.videoExtensions, fileColumn: videoColumn, labelColumn: labelColumn)
        case .labeledVideoDataFrame(let frame, let videoColumn, let labelColumn, _, _):
            return MediaSource(kind: .table(makeDataTable(frame), fileColumn: videoColumn, labelColumn: labelColumn),
                               extensions: Examples.videoExtensions, fileColumn: videoColumn, labelColumn: labelColumn)
        case .labeledKeypointsData, .labeledKeypointsDataFrame:
            return MediaSource(kind: .keypoints, extensions: Examples.videoExtensions, fileColumn: defaults.file, labelColumn: defaults.label)
        }
    }
}

extension MLHandActionClassifier.DataSource {
    var media: MediaSource {
        let defaults = (file: MLHandActionClassifier.__Defaults.videoColumnName, label: MLHandActionClassifier.__Defaults.labelColumnName)
        switch self {
        case .directoryWithVideosAndAnnotation(let url, let file, let videoColumn, let labelColumn, _, _):
            return MediaSource(kind: .annotated(file: file, directory: url, fileColumn: videoColumn, labelColumn: labelColumn),
                               extensions: Examples.videoExtensions, fileColumn: videoColumn, labelColumn: labelColumn)
        case .labeledDirectories(let url):
            return MediaSource(kind: .directories(url), extensions: Examples.videoExtensions, fileColumn: defaults.file, labelColumn: defaults.label)
        case .labeledFiles(let url):
            return MediaSource(kind: .files(url), extensions: Examples.videoExtensions, fileColumn: defaults.file, labelColumn: defaults.label)
        case .labeledVideoData(let table, let videoColumn, let labelColumn, _, _):
            return MediaSource(kind: .table(table, fileColumn: videoColumn, labelColumn: labelColumn),
                               extensions: Examples.videoExtensions, fileColumn: videoColumn, labelColumn: labelColumn)
        case .labeledVideoDataFrame(let frame, let videoColumn, let labelColumn, _, _):
            return MediaSource(kind: .table(makeDataTable(frame), fileColumn: videoColumn, labelColumn: labelColumn),
                               extensions: Examples.videoExtensions, fileColumn: videoColumn, labelColumn: labelColumn)
        case .labeledKeypointsData, .labeledKeypointsDataFrame:
            return MediaSource(kind: .keypoints, extensions: Examples.videoExtensions, fileColumn: defaults.file, labelColumn: defaults.label)
        }
    }
}

extension MLHandPoseClassifier.DataSource {
    var media: MediaSource {
        let defaults = (file: MLHandPoseClassifier.__Defaults.imageColumnName, label: MLHandPoseClassifier.__Defaults.labelColumnName)
        let images = _FileUtilities.imageExtensions
        switch self {
        case .directoryWithImagesAndAnnotation(let url, let file, let imageColumn, let labelColumn):
            return MediaSource(kind: .annotated(file: file, directory: url, fileColumn: imageColumn, labelColumn: labelColumn),
                               extensions: images, fileColumn: imageColumn, labelColumn: labelColumn)
        case .labeledDirectories(let url):
            return MediaSource(kind: .directories(url), extensions: images, fileColumn: defaults.file, labelColumn: defaults.label)
        case .labeledFiles(let url):
            return MediaSource(kind: .files(url), extensions: images, fileColumn: defaults.file, labelColumn: defaults.label)
        case .labeledImageData(let table, let imageColumn, let labelColumn):
            return MediaSource(kind: .table(table, fileColumn: imageColumn, labelColumn: labelColumn),
                               extensions: images, fileColumn: imageColumn, labelColumn: labelColumn)
        case .labeledImageDataFrame(let frame, let imageColumn, let labelColumn):
            return MediaSource(kind: .table(makeDataTable(frame), fileColumn: imageColumn, labelColumn: labelColumn),
                               extensions: images, fileColumn: imageColumn, labelColumn: labelColumn)
        case .labeledKeypointsData, .labeledKeypointsDataFrame:
            return MediaSource(kind: .keypoints, extensions: images, fileColumn: defaults.file, labelColumn: defaults.label)
        }
    }
}

// Object detectors: images and the boxes annotated in them.

extension MLObjectDetector.DataSource {
    /// A table of a column "image" of image paths and a column
    /// "annotation" of each image's boxes.
    func annotatedImages() throws -> (table: MLDataTable, imageColumn: String, annotationColumn: String) {
        func read(_ file: URL, directory: URL) throws -> MLDataTable {
            guard let entries = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [[String: Any]] else {
                throw MLCreateError.io(reason: "\(file.path) isn't an array of image annotations.")
            }
            var images: [MLDataValue] = [], annotations: [MLDataValue] = []
            for entry in entries {
                guard let image = entry["image"] as? String ?? entry["imagefilename"] as? String else { continue }
                images.append(.string(image.hasPrefix("/") ? image : directory.appendingPathComponent(image).path))
                annotations.append((try? MLDataValue(fromAny: entry["annotations"] ?? entry["annotation"] ?? [])) ?? .invalid)
            }
            return MLDataTable(CMLTable(names: ["image", "annotation"],
                                        columns: [CMLColumn(values: images, type: .string), CMLColumn(values: annotations, type: .sequence)]))
        }
        switch self {
        case .directoryWithImagesAndJsonAnnotation(let url):
            let files = try _FileUtilities.contents(of: url).filter { $0.pathExtension.lowercased() == "json" }
            guard files.count == 1 else {
                throw MLCreateError.io(reason: "\(url.path) must hold one JSON annotation file; it has \(files.count).")
            }
            return (try read(files[0], directory: url), "image", "annotation")
        case .directoryWithImages(let url, let file):
            return (try read(file, directory: url), "image", "annotation")
        case .table(let table, let imageColumn, let annotationColumn):
            return (table, imageColumn, annotationColumn)
        case .frame(let frame, let imageColumn, let annotationColumn):
            return (makeDataTable(frame), imageColumn, annotationColumn)
        }
    }
}

// Activity classifiers: sensor recordings by label.

extension MLActivityClassifier.DataSource {
    /// The rows of every recording, with a column of their label and a
    /// column of the file each came from.
    func sensorTable(featureColumns: [String], labelColumn: String, recordingFileColumn: String) throws -> MLDataTable {
        switch self {
        case .labeledDirectories(let url):
            var result = MLDataTable()
            for (label, files) in try Examples.byDirectory(url).sorted(by: { $0.key < $1.key }) {
                for file in files {
                    var recording = try MLDataTable(contentsOf: file)[featureColumns]
                    if let error = recording.error { throw error }
                    let rows = recording.size.rows
                    recording.addColumn(MLUntypedColumn(repeating: .string(label), count: rows), named: labelColumn)
                    recording.addColumn(MLUntypedColumn(repeating: .string(file.path), count: rows), named: recordingFileColumn)
                    result.append(contentsOf: recording)
                }
            }
            if let error = result.error { throw error }
            return result
        case .directoryWithDataAndAnnotation(let url, let annotationFileName, let timeStampColumn, let startColumn, let endColumn):
            // Each annotation row labels the rows of a recording between
            // its start and end times.
            let annotations = try MLDataTable(contentsOf: url.appendingPathComponent(annotationFileName)).getImpl()
            let fileNames = try annotations.column(name: annotations.names.first { $0 != startColumn && $0 != endColumn && $0 != "label" } ?? "")
            let starts = try annotations.column(name: startColumn), ends = try annotations.column(name: endColumn)
            let labels = try annotations.column(name: annotations.names.contains("label") ? "label" : labelColumn)
            var result = MLDataTable()
            for row in 0..<annotations.rowCount {
                guard let name = fileNames.values[row].stringValue, let start = starts.values[row].number,
                      let end = ends.values[row].number else { continue }
                let file = url.appendingPathComponent(name)
                let recording = try MLDataTable(contentsOf: file)
                let times = recording[timeStampColumn]
                var slice = recording[(times >= start) && (times <= end)][featureColumns + [timeStampColumn]]
                let count = slice.size.rows
                slice.addColumn(MLUntypedColumn(repeating: labels.values[row], count: count), named: labelColumn)
                slice.addColumn(MLUntypedColumn(repeating: .string(file.path), count: count), named: recordingFileColumn)
                result.append(contentsOf: slice)
            }
            if let error = result.error { throw error }
            return result
        case .dataFrame(let frame):
            return makeDataTable(frame)
        }
    }
}
