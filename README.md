# Siming

[![CI](https://github.com/shinrenpan/Siming/actions/workflows/ci.yml/badge.svg)](https://github.com/shinrenpan/Siming/actions/workflows/ci.yml)

A high-performance FHIR R4 server written in Swift. Designed for Taiwan healthcare — TW Core IG compliant, one-command deployment, built-in resource browser.

**Stack:** [Hummingbird 2](https://github.com/hummingbird-project/hummingbird) (SwiftNIO) · [PostgresNIO](https://github.com/vapor/postgres-nio) (no ORM) · [FHIRModels](https://github.com/apple/FHIRModels)

## Quick start

### Docker (one-command)

Requires Docker Desktop. Works on macOS, Linux, and Windows.

```bash
git clone https://github.com/shinrenpan/Siming.git
cd Siming
bash scripts/setup.sh
```

Server ready at `http://localhost:8080` · FHIR Browser at `http://localhost:8080/ui`

### macOS (native, for development)

Requires Swift 6.2+ and Docker (for Postgres only).

```bash
bash scripts/fetch-packages.sh   # one-time
bash scripts/run-macOS.sh
```

## Scope

Siming is a **clinical data server** — it stores and searches clinical resources for small clinics. It is not a terminology server: CodeSystem/ValueSet CRUD and operations (`$expand`, `$lookup`) are out of scope. Terminology validation is handled by the optional HL7 Validator sidecar.

## Capabilities

- **23 FHIR R4 resource types** — CRUD, search, history, compartment, transaction bundle
- **TW Core IG v1.0.0** — 9/9 profiles validated; `$validate` with optional HL7 Validator sidecar
- **Search** — chained, `_has`, `_include`/`_revinclude`, `_summary`, `_elements`, cursor pagination
- **Security** — SMART on FHIR JWT bearer (opt-in), per-IP rate limiting (opt-in), CORS
- **Built-in browser** — `GET /ui` — CRUD for all resource types, JSON editor, response-time indicator
- **Observability** — Prometheus metrics (`GET /metrics`), `X-Request-ID` trace header
- **Generated search** — search extractors are generated from the loaded FHIR packages, not hand-written; changing the IG is a package swap + regenerate, no handler rewrites ([details](docs/generator.md))

→ **[Full documentation](https://github.com/shinrenpan/Siming/wiki)**

## Benchmarks

Release build · 5 000 patients · both servers on PostgreSQL. See [`benchmarks/README.md`](benchmarks/README.md).

| Scenario | Siming | HAPI FHIR | Ratio |
|---|---|---|---|
| `GET /Patient/:id` | 15 515 RPS | 6 883 RPS | **2.25×** |
| `GET /Patient?name=Wang` | 2 512 RPS | 1 627 RPS | **1.54×** |

## License

MIT — see [LICENSE](LICENSE).

---

Built with [Claude Code](https://claude.ai/claude-code)
