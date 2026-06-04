-- 0002_search_indexes.sql
-- Covering indexes for search: enable index-only scans on idx_* tables
-- and a partial resources index so the ids CTE avoids heap access.

-- ── resources: partial covering index (non-deleted only) ─────────────────────
-- Enables index-only scan in the `ids` CTE (deferred-content pattern):
--   SELECT DISTINCT ON (r.id) r.id, r.version_id, r.last_updated
--   FROM resources r ... WHERE r.resource_type = 'X' AND r.deleted = false
-- All projected columns (id, version_id, last_updated) are in the index.
CREATE INDEX IF NOT EXISTS resources_live_idx
    ON resources (resource_type, id, version_id DESC, last_updated)
    WHERE deleted = FALSE;

-- ── idx_token: add resource_id for index-only DISTINCT resource_id scans ─────
DROP INDEX IF EXISTS idx_token_code_idx;
DROP INDEX IF EXISTS idx_token_system_code_idx;

CREATE INDEX IF NOT EXISTS idx_token_lookup_idx
    ON idx_token (resource_type, param_name, code, resource_id);

CREATE INDEX IF NOT EXISTS idx_token_system_lookup_idx
    ON idx_token (resource_type, param_name, system, code, resource_id);

-- ── idx_string: B-tree covering index for Bitmap AND with GIN ────────────────
-- GIN trigram handles the ILIKE filter. This covering index supplies the
-- equality conditions (resource_type, param_name) and resource_id so
-- PostgreSQL can Bitmap-AND both indexes instead of heap-scanning after GIN.
CREATE INDEX IF NOT EXISTS idx_string_param_idx
    ON idx_string (resource_type, param_name, resource_id);

-- ── idx_reference: add resource_id ───────────────────────────────────────────
DROP INDEX IF EXISTS idx_reference_lookup_idx;

CREATE INDEX IF NOT EXISTS idx_reference_lookup_idx
    ON idx_reference (resource_type, param_name, ref_type, ref_id, resource_id);

CREATE INDEX IF NOT EXISTS idx_reference_id_only_idx
    ON idx_reference (resource_type, param_name, ref_id, resource_id);

-- ── idx_date: single covering index for range queries ────────────────────────
-- Replaces two single-column indexes with one covering index.
-- (resource_type, param_name) equality + date_end range + resource_id covers ge/gt.
-- For le/lt (date_start) PostgreSQL Bitmap-ANDs with the start index below.
DROP INDEX IF EXISTS idx_date_start_idx;
DROP INDEX IF EXISTS idx_date_end_idx;

CREATE INDEX IF NOT EXISTS idx_date_end_covering_idx
    ON idx_date (resource_type, param_name, date_end, resource_id);

CREATE INDEX IF NOT EXISTS idx_date_start_covering_idx
    ON idx_date (resource_type, param_name, date_start, resource_id);
