-- 0004_string_lower_prefix.sql
-- Functional index for case-insensitive FHIR string prefix search.
--
-- FHIR default string search is case-insensitive prefix (e.g. name=Smi matches Smith).
-- The existing idx_string_exact_idx btree(resource_type, param_name, value) cannot use
-- the value column for ILIKE prefix scans. This index exposes lower(value) with
-- text_pattern_ops so that `lower(value) LIKE lower($pattern)` hits an index range scan
-- instead of a heap filter — eliminating the per-row ILIKE evaluation on unmatched rows.
CREATE INDEX IF NOT EXISTS idx_string_lower_prefix_idx ON idx_string
    (resource_type, param_name, lower(value) text_pattern_ops);
