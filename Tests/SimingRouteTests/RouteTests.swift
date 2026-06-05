import Foundation
import HTTPTypes
import Hummingbird
import HummingbirdTesting
import Logging
import NIOCore
import PostgresNIO
import SimingCore
import SimingServerLib
import Testing

@Suite("HTTP route tests (no DB required)")
struct RouteTests {

    // ── Router factories ──────────────────────────────────────────────────────

    /// Minimal router: FormatMiddleware + /metadata. No DB needed.
    private func makeMetadataApp() -> some ApplicationProtocol {
        let router = Router<BasicRequestContext>()
        router.middlewares.add(FormatMiddleware())
        addMetadataRoutes(to: router)
        return Application(responder: router.buildResponder())
    }

    /// Full router with phantom stores (stores won't connect until a handler
    /// actually executes a query). Handlers that validate before touching the DB
    /// (Content-Type check, strict-handling param validation) work without DB.
    private func makeFullApp() -> some ApplicationProtocol {
        var logger = Logger(label: "test")
        logger.logLevel = .critical
        let dbConfig = DatabaseConfiguration(
            host: "127.0.0.1", port: 5432,
            username: "test", password: "test", database: "test"
        )
        let client = PostgresClient(
            configuration: dbConfig.postgresClientConfiguration,
            backgroundLogger: logger
        )
        let patientStore     = PatientStore(client: client, logger: logger)
        let observationStore = ObservationStore(client: client, logger: logger)
        let encounterStore   = EncounterStore(client: client, logger: logger)
        let conditionStore   = ConditionStore(client: client, logger: logger)
        let router = Router<BasicRequestContext>()
        router.middlewares.add(FormatMiddleware())
        router.get("health") { _, _ in HTTPResponse.Status.ok }
        addMetadataRoutes(to: router)
        addPatientRoutes(to: router, store: patientStore, logger: logger)
        addObservationRoutes(to: router, store: observationStore, logger: logger)
        addEncounterRoutes(to: router, store: encounterStore, logger: logger)
        addConditionRoutes(to: router, store: conditionStore, logger: logger)
        addCompartmentRoutes(to: router, observationStore: observationStore,
                             encounterStore: encounterStore, conditionStore: conditionStore, logger: logger)
        addSystemRoutes(to: router, patientStore: patientStore, observationStore: observationStore, logger: logger)
        return Application(responder: router.buildResponder())
    }

    // ── /metadata ─────────────────────────────────────────────────────────────

    @Test("GET /metadata returns 200")
    func testMetadataOK() async throws {
        try await makeMetadataApp().test(.router) { client in
            try await client.execute(uri: "/metadata", method: .get) { response in
                #expect(response.status == .ok)
            }
        }
    }

    @Test("GET /metadata Content-Type is application/fhir+json")
    func testMetadataContentType() async throws {
        try await makeMetadataApp().test(.router) { client in
            try await client.execute(uri: "/metadata", method: .get) { response in
                let ct = response.headers[.contentType] ?? ""
                #expect(ct.contains("application/fhir+json"))
            }
        }
    }

    @Test("GET /metadata body is a CapabilityStatement")
    func testMetadataIsCapabilityStatement() async throws {
        try await makeMetadataApp().test(.router) { client in
            try await client.execute(uri: "/metadata", method: .get) { response in
                let json = try JSONSerialization.jsonObject(with: Data(response.body.readableBytesView)) as! [String: Any]
                #expect(json["resourceType"] as? String == "CapabilityStatement")
                #expect(json["fhirVersion"] as? String == "4.0.1")
            }
        }
    }

    // ── _format negotiation ───────────────────────────────────────────────────

    @Test("GET /metadata?_format=xml returns 406 OperationOutcome")
    func testFormatXmlReturns406() async throws {
        try await makeMetadataApp().test(.router) { client in
            try await client.execute(uri: "/metadata?_format=xml", method: .get) { response in
                #expect(response.status == .notAcceptable)
                let json = try JSONSerialization.jsonObject(with: Data(response.body.readableBytesView)) as! [String: Any]
                #expect(json["resourceType"] as? String == "OperationOutcome")
            }
        }
    }

    @Test("GET /metadata?_format=json returns 200")
    func testFormatJsonAccepted() async throws {
        try await makeMetadataApp().test(.router) { client in
            try await client.execute(uri: "/metadata?_format=json", method: .get) { response in
                #expect(response.status == .ok)
            }
        }
    }

    @Test("GET /metadata?_format=application%2Ffhir%2Bjson returns 200")
    func testFormatFhirJsonAccepted() async throws {
        try await makeMetadataApp().test(.router) { client in
            try await client.execute(
                uri: "/metadata?_format=application%2Ffhir%2Bjson", method: .get
            ) { response in
                #expect(response.status == .ok)
            }
        }
    }

    // ── Content-Type enforcement ──────────────────────────────────────────────

    @Test("POST /Patient without Content-Type returns 415 OperationOutcome")
    func testPostPatientNoContentTypeReturns415() async throws {
        try await makeFullApp().test(.router) { client in
            try await client.execute(
                uri: "/Patient", method: .post,
                headers: HTTPFields(),
                body: ByteBuffer(string: "{}")
            ) { response in
                #expect(response.status == .unsupportedMediaType)
                let json = try JSONSerialization.jsonObject(with: Data(response.body.readableBytesView)) as! [String: Any]
                #expect(json["resourceType"] as? String == "OperationOutcome")
            }
        }
    }

    @Test("POST /Observation without Content-Type returns 415 OperationOutcome")
    func testPostObservationNoContentTypeReturns415() async throws {
        try await makeFullApp().test(.router) { client in
            try await client.execute(
                uri: "/Observation", method: .post,
                headers: HTTPFields(),
                body: ByteBuffer(string: "{}")
            ) { response in
                #expect(response.status == .unsupportedMediaType)
                let json = try JSONSerialization.jsonObject(with: Data(response.body.readableBytesView)) as! [String: Any]
                #expect(json["resourceType"] as? String == "OperationOutcome")
            }
        }
    }

    // ── Prefer: handling=strict ───────────────────────────────────────────────

    @Test("GET /Patient with unknown param + handling=strict returns 400 OperationOutcome")
    func testStrictHandlingPatientUnknownParam() async throws {
        try await makeFullApp().test(.router) { client in
            var headers = HTTPFields()
            headers[HTTPField.Name("Prefer")!] = "handling=strict"
            try await client.execute(
                uri: "/Patient?unknownXYZ=foo",
                method: .get,
                headers: headers
            ) { response in
                #expect(response.status == .badRequest)
                let json = try JSONSerialization.jsonObject(with: Data(response.body.readableBytesView)) as! [String: Any]
                #expect(json["resourceType"] as? String == "OperationOutcome")
            }
        }
    }

    @Test("GET /Observation with unknown param + handling=strict returns 400 OperationOutcome")
    func testStrictHandlingObservationUnknownParam() async throws {
        try await makeFullApp().test(.router) { client in
            var headers = HTTPFields()
            headers[HTTPField.Name("Prefer")!] = "handling=strict"
            try await client.execute(
                uri: "/Observation?unknownXYZ=foo",
                method: .get,
                headers: headers
            ) { response in
                #expect(response.status == .badRequest)
                let json = try JSONSerialization.jsonObject(with: Data(response.body.readableBytesView)) as! [String: Any]
                #expect(json["resourceType"] as? String == "OperationOutcome")
            }
        }
    }

    // ── /health ───────────────────────────────────────────────────────────────

    @Test("GET /health returns 200")
    func testHealthEndpoint() async throws {
        try await makeFullApp().test(.router) { client in
            try await client.execute(uri: "/health", method: .get) { response in
                #expect(response.status == .ok)
            }
        }
    }
}
