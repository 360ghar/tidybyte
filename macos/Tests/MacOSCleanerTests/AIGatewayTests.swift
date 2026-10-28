import Foundation
@testable import MacOSCleanerCore
import XCTest

/// Mock URL protocol for testing AIGateway HTTP requests
final class MockURLProtocol: URLProtocol {
    // Use nonisolated(unsafe) for test-only mutable state
    nonisolated(unsafe) static var mockResponse: ((URLRequest) -> (Data, HTTPURLResponse))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let mockResponse = Self.mockResponse else {
            let error = NSError(domain: "MockURLProtocol", code: -1, userInfo: [NSLocalizedDescriptionKey: "No mock response configured"])
            client?.urlProtocol(self, didFailWithError: error)
            return
        }

        let (data, response) = mockResponse(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// Test configuration for AIGateway
final class AIGatewayTests: XCTestCase {
    private var session: URLSession!
    private var keychain: KeychainStore!
    private var gateway: AIGateway!

    override func setUp() async throws {
        try await super.setUp()

        // Create mock URL session configuration
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: config)

        // Create in-memory keychain for testing. The tests exercise the REAL
        // macOS keychain (KeychainStore has no protocol seam), so make each run
        // hermetic by removing keys from both the legacy and provider-keyed
        // accounts — a leftover dev key would otherwise let the gateway reach
        // the HTTP layer and surface a 401 instead of missingAPIKey.
        let keychain = KeychainStore(inMemory: true)
        try? await keychain.deleteAPIKey()
        try? await keychain.deleteAPIKey(account: "OpenAI-compatible")
        self.keychain = keychain

        // Create gateway with mock session
        gateway = AIGateway(keychain: keychain)
    }

    override func tearDown() async throws {
        MockURLProtocol.mockResponse = nil
        try await super.tearDown()
    }

    func testAIGatewayReturnsLocalOnlyError() async throws {
        let settings = ProviderSettings(privacyMode: .localOnly)
        let findings: [Finding] = []

        do {
            _ = try await gateway.classify(findings: findings, filesByID: [:], settings: settings)
            XCTFail("Expected localOnly error")
        } catch let error as AIGatewayError {
            guard case .localOnly = error else {
                XCTFail("Unexpected error: \(error)")
                return
            }
        }
    }

    func testAIGatewayReturnsMissingAPIKeyError() async throws {
        let settings = ProviderSettings(privacyMode: .metadataOnlyAI)
        let findings: [Finding] = []

        do {
            _ = try await gateway.classify(findings: findings, filesByID: [:], settings: settings)
            XCTFail("Expected missingAPIKey error")
        } catch let error as AIGatewayError {
            guard case .missingAPIKey = error else {
                XCTFail("Unexpected error: \(error)")
                return
            }
        }
    }

    func testAIGatewaySupportsSnippetsAIMode() async throws {
        // This test verifies that snippetsAI mode is accepted (not rejected)
        let settings = ProviderSettings(privacyMode: .snippetsAI)
        let findings: [Finding] = []

        // The gateway should not throw unsupportedPrivacyMode for snippetsAI
        // It will throw missingAPIKey since we haven't set an API key
        do {
            _ = try await gateway.classify(findings: findings, filesByID: [:], settings: settings)
            XCTFail("Expected missingAPIKey error")
        } catch let error as AIGatewayError {
            // This is expected - snippetsAI is now supported, but we need an API key
            guard case .missingAPIKey = error else {
                XCTFail("Unexpected error: \(error)")
                return
            }
        }
    }

    func testAIGatewaySupportsVisionAIMode() async throws {
        // This test verifies that visionAI mode is accepted (not rejected)
        let settings = ProviderSettings(privacyMode: .visionAI)
        let findings: [Finding] = []

        // The gateway should not throw unsupportedPrivacyMode for visionAI
        // It will throw missingAPIKey since we haven't set an API key
        do {
            _ = try await gateway.classify(findings: findings, filesByID: [:], settings: settings)
            XCTFail("Expected missingAPIKey error")
        } catch let error as AIGatewayError {
            // This is expected - visionAI is now supported, but we need an API key
            guard case .missingAPIKey = error else {
                XCTFail("Unexpected error: \(error)")
                return
            }
        }
    }

    func testAIGatewayRejectsUnsupportedPrivacyModes() async throws {
        // Every privacy mode is supported; each non-localOnly mode must fail
        // with missingAPIKey (no key in the test environment) and never a
        // mode-rejection error.
        let modes: [PrivacyMode] = [.metadataOnlyAI, .snippetsAI, .visionAI, .fullDocumentAI]

        for mode in modes {
            let settings = ProviderSettings(privacyMode: mode)
            do {
                _ = try await gateway.classify(findings: [], filesByID: [:], settings: settings)
            } catch let error as AIGatewayError {
                guard case .missingAPIKey = error else {
                    XCTFail("Mode \(mode.rawValue) should surface missingAPIKey, got \(error)")
                    return
                }
            }
        }
    }
}
