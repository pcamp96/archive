import Testing
@testable import Archive

struct NoteIDTests {
    @Test
    func noteIdentityUsesPathAcrossAtomicSaves() {
        let original = NoteID(resourceIdentifier: "original-resource-id", path: "/Archive/Untitled.md")
        let replaced = NoteID(resourceIdentifier: "replacement-resource-id", path: "/Archive/Untitled.md")

        #expect(original == replaced)
        #expect(original.id == replaced.id)
    }
}
