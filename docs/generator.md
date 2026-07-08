# The Generator — Siming's Architectural Moat

Search in Siming is **not hand-written**. It is generated from the FHIR packages
you load. This one design decision is what lets Siming claim its headline
property:

> **Changing the IG = swap a package + regenerate. No handler rewrites.**

This page explains what the generator is, why it exists, and how to work with it.
If you only remember one thing: **never hand-edit generated files — change the
generator or the input packages instead.**

---

## What it produces

`SimingGenerator` reads the FHIR packages in `packages/*.tgz` and emits Swift
source into `Sources/SimingCore/Generated/`. Today the inputs are:

- `hl7.fhir.r4.core-4.0.1.tgz` — base FHIR R4
- `tw.gov.mohw.twcore-1.0.0.tgz` — Taiwan Core IG v1.0.0

From those it writes **two kinds of artifact**:

1. **Per-resource search extractors** — `Patient+SearchExtractor.swift`,
   `Observation+SearchExtractor.swift`, … (one file per supported resource type,
   23 in total). Each exposes a single entry point, e.g.:

   ```swift
   public func extractPatientSearchParams(_ patient: Patient) -> SearchParams
   ```

   which fans out to one small private function per search parameter and appends
   into the typed buckets of `SearchParams` (tokens / strings / references /
   dates / quantities). These buckets map 1:1 onto the five `idx_*` index tables.
   Params recognised by the R4 spec but not yet implemented are emitted as `TODO`
   markers, so the coverage gap is visible in the generated code itself.

2. **Terminology binding rules** — `TerminologyBindings.swift`, a
   `[String: [BindingRule]]` table of the *required* value-set bindings per
   resource (path, value set, `code` vs `codeableConcept`, array-or-not). This
   feeds the validation layer.

Every generated file carries the same header, so provenance is never ambiguous:

```swift
// GENERATED — do not edit directly.
// Source: packages/*.tgz (hl7.fhir.r4.core + tw.gov.mohw.twcore)
// Regenerate: swift run SimingGenerator
```

---

## The pipeline

There are **two** consumers of the same `packages/*.tgz`, and they run at
different times — this split is the core of the design:

```
                         ┌─ swift run SimingGenerator ─→ Sources/SimingCore/Generated/   (COMPILE-TIME)
packages/*.tgz  ─────────┤                                • Xxx+SearchExtractor.swift  (committed to git)
                         │                                • TerminologyBindings.swift
                         │
                         └─ server startup ────────────→ GET /metadata                   (RUNTIME)
                                                          CapabilityStatement, reflects loaded IGs
```

- **Search extractors are compile-time.** They are type-safe Swift, live on the
  hot write path, and are performance-critical — so they are turned into machine
  code and **committed to git** (reviewable, diffable).
- **CapabilityStatement is runtime.** It is built at server startup from the same
  packages, so `/metadata` always reflects whatever IGs are actually loaded.

Do not collapse these two. Moving extractors to runtime (a config table, a string
template assembled per request) would throw away the type safety and the compiled
performance that make Siming fast — and it would reintroduce exactly the
hand-maintained-schema problem the generator was built to kill.

---

## Regenerating

```bash
swift run SimingGenerator                # reads ./packages, writes ./Sources/SimingCore/Generated
swift run SimingGenerator <pkgDir> <out> # both paths are optional positional args
```

Then rebuild and run the tests:

```bash
swift build
swift test --filter SimingCoreTests
```

Commit the regenerated files together with whatever triggered the change.

---

## Swapping an IG

This is the workflow the moat exists for. To move from one IG version to another
(or add a new one):

1. Drop the new `*.tgz` into `packages/` (and remove the old one if replacing).
2. `swift run SimingGenerator`
3. Review the diff under `Sources/SimingCore/Generated/` — new/removed search
   params and binding rules show up as ordinary reviewable changes.
4. `swift build && swift test`

No handler is touched. No SQL is touched (unless the change introduces a search
param of a *type* not yet covered by the five index tables). The IG change lands
as a package swap plus a generated-code diff.

---

## Adding a new resource type

Generation is one piece; the full checklist (mirrors the operational rules in
`CLAUDE.md`, in tutorial form) is:

1. **Generator** — add the resource to `allResourceTypes` and write its
   `generate<Resource>Extractor(params:)` emitter in `Sources/SimingGenerator/`,
   then run `swift run SimingGenerator` to produce
   `Generated/<Resource>+SearchExtractor.swift`.
2. **SQL migration** — add a new numbered file under `migrations/` if the
   resource needs anything the existing schema doesn't already provide.
   (Migration files are immutable once committed — never edit an old one.)
3. **Store** — add a store property to `StoreContainer`; its `write()` calls
   `writeResource`, its `delete()` calls `deleteResource` (copy any existing
   store).
4. **Routes** — register in `RouterBuilder` via
   `addXxxRoutes(to: router, store: stores.xxx, logger: logger)`.

---

## The invariant

- **Generated code is committed to git.** It is meant to be read and diffed in
  review, not hidden behind a build step.
- **Generated code is never hand-edited.** If a generated file is wrong, the fix
  is in the generator (`Sources/SimingGenerator/`) or in the input package —
  never in `Sources/SimingCore/Generated/`.
- **The generator is the seam that keeps three doors open:** a new IG, a new
  profile binding, or a new search param arrives as *data* (a package) and
  becomes *code* (a regenerate), with no handler rewrite. If a proposed change
  would require hand-editing generated output or hard-coding a search definition,
  stop and restructure.
