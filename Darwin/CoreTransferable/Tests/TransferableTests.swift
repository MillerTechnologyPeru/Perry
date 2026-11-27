import Foundation
import Testing
import UniformTypeIdentifiers
@testable import CoreTransferable

@Test func urlRepresentationRoundTrips() async throws {
    let representation = try #require(URL.transferRepresentation as? DataRepresentation<URL>)
    let export = try #require(representation.exporting)
    let importData = try #require(representation.importing)
    let url = try #require(URL(string: "https://example.com/path?q=hello%20world"))
    #expect(representation.contentType == .url)
    let data = try await export(url)
    #expect(String(data: data, encoding: .utf8) == url.absoluteString)
    #expect(try await importData(data) == url)
}

@Test func urlRepresentationRejectsInvalidUTF8() async throws {
    let representation = try #require(URL.transferRepresentation as? DataRepresentation<URL>)
    let importData = try #require(representation.importing)
    await #expect(throws: CocoaError.self) {
        _ = try await importData(Data([0xff]))
    }
}

@Test func directionalRepresentationsPreserveCapabilities() {
    let exporter = DataRepresentation<URL>(exportedContentType: .url) { Data($0.absoluteString.utf8) }
    let importer = DataRepresentation<URL>(importedContentType: .url) { _ in URL(fileURLWithPath: "/tmp") }
    #expect(exporter.exporting != nil)
    #expect(exporter.importing == nil)
    #expect(importer.exporting == nil)
    #expect(importer.importing != nil)
}
