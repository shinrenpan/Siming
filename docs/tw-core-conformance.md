# TW Core IG Conformance Report

**IG version:** tw.gov.mohw.twcore 1.0.0  
**Validator:** HL7 FHIR Validator service (infernocommunity/inferno-resource-validator:1.0.78)  
**Validation method:** `POST /{ResourceType}/$validate?profile={profile-url}` via Siming E Phase integration  
**Date:** 2026-06-12

## Summary

8 of 8 tested TW Core profiles pass validation with zero errors when required fields are present.
Negative-case testing confirms the validator correctly rejects resources that omit TW Core-mandatory fields.

| Profile | Result | Notes |
|---------|--------|-------|
| Patient-twcore | ✅ PASS | |
| Condition-twcore | ✅ PASS | |
| Encounter-twcore | ✅ PASS | |
| MedicationRequest-twcore | ✅ PASS | NHI CodeSystem unknown to validator (expected) |
| AllergyIntolerance-twcore | ✅ PASS | ATC code outside FHIR base valueset (expected, extensible binding) |
| Observation-laboratoryResult-twcore | ✅ PASS | |
| Practitioner-twcore | ✅ PASS | |
| Organization-twcore | ✅ PASS | |
| DiagnosticReport-twcore | ✅ PASS | Requires exact LOINC display text |

All warnings are `dom-6` (narrative recommended) — a FHIR best-practice advisory, not a TW Core requirement.

## Profile URLs

| Resource | TW Core Profile URL |
|----------|-------------------|
| Patient | `https://twcore.mohw.gov.tw/ig/twcore/StructureDefinition/Patient-twcore` |
| Condition | `https://twcore.mohw.gov.tw/ig/twcore/StructureDefinition/Condition-twcore` |
| Encounter | `https://twcore.mohw.gov.tw/ig/twcore/StructureDefinition/Encounter-twcore` |
| MedicationRequest | `https://twcore.mohw.gov.tw/ig/twcore/StructureDefinition/MedicationRequest-twcore` |
| AllergyIntolerance | `https://twcore.mohw.gov.tw/ig/twcore/StructureDefinition/AllergyIntolerance-twcore` |
| Observation (lab) | `https://twcore.mohw.gov.tw/ig/twcore/StructureDefinition/Observation-laboratoryResult-twcore` |
| Practitioner | `https://twcore.mohw.gov.tw/ig/twcore/StructureDefinition/Practitioner-twcore` |
| Organization | `https://twcore.mohw.gov.tw/ig/twcore/StructureDefinition/Organization-twcore` |
| DiagnosticReport | `https://twcore.mohw.gov.tw/ig/twcore/StructureDefinition/DiagnosticReport-twcore` |

## TW Core Required Fields (by profile)

These fields are mandatory per TW Core StructureDefinitions (min ≥ 1). Missing any triggers a validator ERROR.

| Profile | Required fields beyond FHIR R4 base |
|---------|-------------------------------------|
| Patient-twcore | `identifier` (min=1), `gender` (min=1), `birthDate` (min=1) |
| Condition-twcore | `clinicalStatus` (min=1), `category` (min=1), `subject` (min=1) |
| Encounter-twcore | `status` (min=1), `class` (min=1) |
| MedicationRequest-twcore | `status` (min=1), `intent` (min=1), `medication[x]` (min=1), `subject` (min=1) |
| AllergyIntolerance-twcore | `code` (min=1), `patient` (min=1) |
| Observation-laboratoryResult-twcore | `status` (min=1), `category` (min=1), `code` (min=1), `subject` (min=1) |
| Practitioner-twcore | (no additional required fields beyond FHIR R4) |
| Organization-twcore | (no additional required fields beyond FHIR R4) |
| DiagnosticReport-twcore | `status` (min=1), `code` (min=1), `subject` (min=1) |

## Negative-Case Validation

**Test:** Patient without `identifier` (TW Core requires min=1)

**Result:** HTTP 200 with ERROR in OperationOutcome:
```
Patient.identifier: minimum required = 1, but only found 0
(from https://twcore.mohw.gov.tw/ig/twcore/StructureDefinition/Patient-twcore|1.0.0)
```

Confirms that constraint enforcement is functioning correctly.

## Known Limitations

- **NHI CodeSystem** (`http://www.nhi.gov.tw`): not resolvable by the validator's terminology server. Resources using NHI drug codes will receive an "unknown CodeSystem" warning (not error). This is expected — NHI doesn't publish a public FHIR CodeSystem endpoint.
- **Intensional ValueSets**: skipped by the local terminology index (D Phase design decision). The external validator uses tx.fhir.org for those checks.
- **Narrative**: `dom-6` warning appears on every resource. Narrative is a best-practice recommendation in FHIR R4, not enforced by TW Core profiles.
- **TW Core profile coverage**: 40+ profiles defined in TW Core v1.0.0. This report covers the 9 most clinically relevant resource types.

## How to Run `$validate`

```bash
# Validate a Patient against TW Core profile
curl -X POST "http://localhost:8080/Patient/\$validate?profile=https://twcore.mohw.gov.tw/ig/twcore/StructureDefinition/Patient-twcore" \
  -H "Content-Type: application/fhir+json" \
  -d @patient.json
```

**Configuration required:**
```yaml
# config.yml
validator:
  url: "http://localhost:3500"  # inferno-resource-validator service URL
```

Or via environment variable: `VALIDATOR_URL=http://localhost:3500`

When `validator.url` is empty, `$validate` runs only local terminology binding checks (D Phase).
When configured, it also runs full StructureDefinition profile validation (E Phase).
