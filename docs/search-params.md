# Search parameters by resource

Supported FHIR R4 search parameters for each resource type.

**Patient** — `name`, `family`, `given`, `identifier`, `gender`, `birthdate`, `address`, `address-city`, `address-state`, `address-country`, `address-postalcode`, `phone`, `email`, `active`, `deceased`, `death-date`, `_id`, `_lastUpdated`

**Observation** — `subject`, `patient`, `code`, `status`, `category`, `date`, `value-quantity`, `value-concept`, `value-date`, `value-string`, `identifier`, `encounter`, `performer`, `based-on`, `derived-from`, `device`, `focus`, `has-member`, `part-of`, `specimen`, `component-code`, `combo-code`, `method`, `data-absent-reason`, `combo-data-absent-reason`, `component-data-absent-reason`, `component-value-concept`, `component-value-quantity`, `combo-value-concept`, `combo-value-quantity`, `code-value-quantity`, `code-value-string`, `code-value-concept`, `code-value-date`, `component-code-value-quantity`, `component-code-value-concept`, `combo-code-value-quantity`, `combo-code-value-concept`, `_id`, `_lastUpdated`

**Encounter** — `subject`, `patient`, `status`, `class`, `type`, `date`, `identifier`, `participant`, `practitioner`, `reason-code`, `reason-reference`, `part-of`, `service-provider`, `based-on`, `location`, `location-period`, `diagnosis`, `account`, `appointment`, `episode-of-care`, `participant-type`, `special-arrangement`, `length`, `_id`, `_lastUpdated`

**Condition** — `subject`, `patient`, `clinical-status`, `verification-status`, `category`, `code`, `encounter`, `onset-date`, `abatement-date`, `recorded-date`, `identifier`, `asserter`, `body-site`, `evidence`, `evidence-detail`, `severity`, `stage`, `onset-info`, `abatement-string`, `onset-age`, `abatement-age`, `_id`, `_lastUpdated`

**MedicationRequest** — `subject`, `patient`, `status`, `intent`, `medication`, `code`, `priority`, `date`, `authored-on`, `identifier`, `encounter`, `requester`, `intended-dispenser`, `intended-performer`, `intended-performertype`, `_id`, `_lastUpdated`

**AllergyIntolerance** — `patient`, `clinical-status`, `verification-status`, `type`, `category`, `criticality`, `code`, `identifier`, `date`, `manifestation`, `severity`, `route`, `last-date`, `onset`, `asserter`, `recorder`, `_id`, `_lastUpdated`

**Procedure** — `subject`, `patient`, `status`, `code`, `category`, `identifier`, `encounter`, `performer`, `based-on`, `instantiates-canonical`, `instantiates-uri`, `location`, `part-of`, `reason-code`, `reason-reference`, `date`, `_id`, `_lastUpdated`

**DiagnosticReport** — `subject`, `patient`, `status`, `code`, `category`, `identifier`, `encounter`, `performer`, `based-on`, `conclusion`, `media`, `result`, `results-interpreter`, `specimen`, `date`, `issued`, `_id`, `_lastUpdated`

**Immunization** — `patient`, `status`, `vaccine-code`, `identifier`, `date`, `performer`, `location`, `manufacturer`, `reaction`, `reaction-date`, `reason-code`, `reason-reference`, `series`, `status-reason`, `target-disease`, `lot-number`, `_id`, `_lastUpdated`

**Practitioner** — `name`, `family`, `given`, `phonetic`, `identifier`, `active`, `gender`, `address`, `address-city`, `address-state`, `address-country`, `address-postalcode`, `phone`, `email`, `communication`, `_id`, `_lastUpdated`

**Organization** — `name`, `phonetic`, `identifier`, `active`, `type`, `address`, `address-city`, `address-state`, `address-country`, `address-postalcode`, `partof`, `endpoint`, `_id`, `_lastUpdated`

**Medication** — `code`, `status`, `form`, `identifier`, `lot-number`, `ingredient-code`, `manufacturer`, `ingredient`, `expiration-date`, `_id`, `_lastUpdated`

**Location** — `name`, `identifier`, `status`, `type`, `operational-status`, `address`, `address-city`, `address-state`, `address-country`, `address-postalcode`, `organization`, `partof`, `endpoint`, `_id`, `_lastUpdated` (`near` geospatial not supported)

**RelatedPerson** — `name`, `phonetic` (alias for `name`), `identifier`, `active`, `gender`, `relationship`, `birthdate`, `address`, `address-city`, `address-state`, `address-country`, `address-postalcode`, `address-use`, `phone`, `email`, `telecom`, `patient`, `_id`, `_lastUpdated`

**ServiceRequest** — `status`, `intent`, `priority`, `code`, `category`, `body-site`, `performer-type`, `requisition`, `identifier`, `authored`, `occurrence`, `subject`, `patient`, `encounter`, `requester`, `performer`, `based-on`, `replaces`, `specimen`, `instantiates-canonical`, `instantiates-uri`, `order-detail`, `_id`, `_lastUpdated`

**Specimen** — `status`, `type`, `accession`, `identifier`, `bodysite`, `container`, `container-id`, `collected`, `subject`, `patient`, `collector`, `parent`, `_id`, `_lastUpdated`

**DocumentReference** — `status`, `type`, `category`, `identifier`, `security-label`, `facility`, `event`, `description`, `date`, `period`, `contenttype`, `format`, `language`, `setting`, `location`, `subject`, `patient`, `author`, `encounter`, `custodian`, `authenticator`, `relatesto`, `related`, `relation`, `relationship`, `_id`, `_lastUpdated`

**CarePlan** — `status`, `intent`, `category`, `identifier`, `activity-code`, `date` (period), `activity-date`, `instantiates-canonical`, `instantiates-uri`, `subject`, `patient`, `encounter`, `care-team`, `condition`, `goal`, `based-on`, `part-of`, `replaces`, `performer`, `activity-reference`, `_id`, `_lastUpdated`

**Goal** — `lifecycle-status`, `achievement-status`, `category`, `identifier`, `start-date`, `target-date`, `subject`, `patient`, `_id`, `_lastUpdated`

**MedicationStatement** — `status`, `category`, `code`, `identifier`, `effective`, `subject`, `patient`, `context`, `source`, `medication`, `part-of`, `_id`, `_lastUpdated`

**FamilyMemberHistory** — `status`, `relationship`, `sex`, `code`, `identifier`, `date`, `instantiates-canonical`, `instantiates-uri`, `patient`, `_id`, `_lastUpdated`

**Appointment** — `status`, `service-type`, `appointment-type`, `specialty`, `reason-code`, `service-category`, `part-status`, `identifier`, `date`, `supporting-info`, `patient`, `practitioner`, `location`, `actor`, `_id`, `_lastUpdated`

**MedicationAdministration** — `status`, `code`, `reason-given`, `reason-not-given`, `identifier`, `effective-time`, `subject`, `patient`, `context`, `request`, `performer`, `device`, `medication`, `_id`, `_lastUpdated`
