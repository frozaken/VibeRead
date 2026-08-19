import Foundation
import Testing
@testable import Vibe_Read

struct EnvironmentKeyImporterTests {
    @Test func readsPlainQuotedAndExportedValues() {
        let contents = """
        # Local provider keys
        ELEVENLABS_API_KEY=plain-value
        export GROQ_API_KEY="quoted-value"
        OPENROUTER_API_KEY='single-quoted-value'
        """

        #expect(EnvironmentKeyImporter.value(named: "ELEVENLABS_API_KEY", in: contents) == "plain-value")
        #expect(EnvironmentKeyImporter.value(named: "GROQ_API_KEY", in: contents) == "quoted-value")
        #expect(EnvironmentKeyImporter.value(named: "OPENROUTER_API_KEY", in: contents) == "single-quoted-value")
    }

    @Test func ignoresCommentsOtherVariablesAndMissingNames() {
        let contents = """
        # ELEVENLABS_API_KEY=commented-out
        SOME_OTHER_KEY=value
        """

        #expect(EnvironmentKeyImporter.value(named: "ELEVENLABS_API_KEY", in: contents) == nil)
    }

    @Test func environmentNamesMatchProviderCredentials() {
        #expect(ProviderCredential.elevenLabs.environmentVariableName == "ELEVENLABS_API_KEY")
        #expect(ProviderCredential.groq.environmentVariableName == "GROQ_API_KEY")
        #expect(ProviderCredential.openRouter.environmentVariableName == "OPENROUTER_API_KEY")
        #expect(ProviderCredential.openAI.environmentVariableName == "OPENAI_API_KEY")
    }
}
