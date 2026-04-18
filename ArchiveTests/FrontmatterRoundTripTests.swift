import Testing
@testable import Archive

struct FrontmatterRoundTripTests {
    @Test
    func scannerParsesSupportedProperties() {
        let source = """
        ---
        title: Draft Review
        status: In Progress
        published: false
        tags:
          - review
          - hardware
        due: 2026-04-20
        ---

        # Heading

        Body
        """

        let parsed = FrontmatterScanner().parse(source)
        let registry = PropertyRegistry()
        let properties = parsed.frontmatter.editableProperties(using: registry)

        #expect(properties.first(where: { $0.key == "title" })?.value.stringValue == "Draft Review")
        #expect(properties.first(where: { $0.key == "status" })?.value.stringValue == "In Progress")
        #expect(properties.first(where: { $0.key == "published" })?.value == .bool(false))
        #expect(properties.first(where: { $0.key == "due" })?.value == .date("2026-04-20"))
        #expect(properties.first(where: { $0.key == "tags" })?.value == .stringList(["review", "hardware"]))
        #expect(parsed.body == "# Heading\n\nBody")
    }

    @Test
    func codecPreservesUnsupportedEntriesWhileUpdatingEditableOnes() {
        let source = """
        ---
        title: Old
        config:
          nested: true
        status: Draft
        ---

        Body
        """

        let parsed = FrontmatterScanner().parse(source)
        let codec = FrontmatterCodec()
        let output = codec.serializedFrontmatter(
            from: parsed.frontmatter,
            title: "New",
            properties: [
                EditableProperty(key: "status", kind: .singleSelect, value: .string("Published"), isReadOnly: false, issue: nil)
            ]
        )

        #expect(output != nil)
        #expect(output?.contains("title: New") == true)
        #expect(output?.contains("status: Published") == true)
        #expect(output?.contains("config:\n  nested: true") == true)
    }

    @Test
    func codecHandlesDuplicateEditableKeysWithoutCrashing() {
        let source = """
        ---
        title: Old
        status: Draft
        status: Published
        ---

        Body
        """

        let parsed = FrontmatterScanner().parse(source)
        let registry = PropertyRegistry(definitions: [
            "status": PropertyDefinition(key: "status", kind: .singleSelect, options: ["Draft", "Published", "Done"])
        ])
        let properties = parsed.frontmatter.editableProperties(using: registry)
        let codec = FrontmatterCodec()
        let output = codec.serializedFrontmatter(
            from: parsed.frontmatter,
            title: "Old",
            properties: properties.map { property in
                if property.key == "status", property.isReadOnly == false {
                    return EditableProperty(
                        key: property.key,
                        kind: property.kind,
                        value: .string("Done"),
                        isReadOnly: false,
                        issue: nil
                    )
                }
                return property
            }
        )

        #expect(output?.contains("status: Done") == true)
        #expect(output?.contains("status: Published") == true)
    }
}
