-- 0001_init.sql
-- Core schema: history-preserving resource store + five typed search-param indexes.

-- ─── Migration tracker ───────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS schema_migrations (
    version     TEXT        PRIMARY KEY,
    applied_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ─── Main resource store ─────────────────────────────────────────────────────
-- Updates NEVER overwrite. Each write produces a new row with a higher version_id.
-- Current version = max(version_id) per (resource_type, id).
CREATE TABLE IF NOT EXISTS resources (
    resource_type   TEXT        NOT NULL,
    id              TEXT        NOT NULL,
    version_id      BIGINT      NOT NULL,
    last_updated    TIMESTAMPTZ NOT NULL DEFAULT now(),
    content         JSONB       NOT NULL,
    deleted         BOOLEAN     NOT NULL DEFAULT FALSE,
    PRIMARY KEY (resource_type, id, version_id)
);

-- Current-version lookup: most-recent version_id first per resource.
CREATE INDEX IF NOT EXISTS resources_current_version_idx
    ON resources (resource_type, id, version_id DESC);

-- Cursor pagination anchor for search results (non-deleted, current versions only).
CREATE INDEX IF NOT EXISTS resources_cursor_idx
    ON resources (resource_type, last_updated, id)
    WHERE deleted = FALSE;

-- ─── idx_token ───────────────────────────────────────────────────────────────
-- Covers: identifier, code, status.  Stores (system, code) pairs.
CREATE TABLE IF NOT EXISTS idx_token (
    resource_type   TEXT    NOT NULL,
    resource_id     TEXT    NOT NULL,
    param_name      TEXT    NOT NULL,
    system          TEXT,
    code            TEXT    NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_token_code_idx
    ON idx_token (resource_type, param_name, code);

CREATE INDEX IF NOT EXISTS idx_token_system_code_idx
    ON idx_token (resource_type, param_name, system, code);

-- ─── idx_string ──────────────────────────────────────────────────────────────
-- Covers: name, address.  Trigram GIN for starts-with / contains search.
CREATE TABLE IF NOT EXISTS idx_string (
    resource_type   TEXT    NOT NULL,
    resource_id     TEXT    NOT NULL,
    param_name      TEXT    NOT NULL,
    value           TEXT    NOT NULL
);

CREATE EXTENSION IF NOT EXISTS pg_trgm;

CREATE INDEX IF NOT EXISTS idx_string_trgm_idx
    ON idx_string USING GIN (value gin_trgm_ops);

CREATE INDEX IF NOT EXISTS idx_string_exact_idx
    ON idx_string (resource_type, param_name, value);

-- ─── idx_reference ───────────────────────────────────────────────────────────
-- Covers: subject, patient.  Stores target resource type + id.
CREATE TABLE IF NOT EXISTS idx_reference (
    resource_type   TEXT    NOT NULL,
    resource_id     TEXT    NOT NULL,
    param_name      TEXT    NOT NULL,
    ref_type        TEXT,
    ref_id          TEXT    NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_reference_lookup_idx
    ON idx_reference (resource_type, param_name, ref_type, ref_id);

-- ─── idx_date ────────────────────────────────────────────────────────────────
-- Covers: birthdate, date, period.  Stored as [date_start, date_end] for range ops.
CREATE TABLE IF NOT EXISTS idx_date (
    resource_type   TEXT        NOT NULL,
    resource_id     TEXT        NOT NULL,
    param_name      TEXT        NOT NULL,
    date_start      TIMESTAMPTZ NOT NULL,
    date_end        TIMESTAMPTZ NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_date_start_idx
    ON idx_date (resource_type, param_name, date_start);

CREATE INDEX IF NOT EXISTS idx_date_end_idx
    ON idx_date (resource_type, param_name, date_end);

-- ─── idx_quantity ────────────────────────────────────────────────────────────
-- Covers: value-quantity.  Optional unit system + code, numeric value.
CREATE TABLE IF NOT EXISTS idx_quantity (
    resource_type   TEXT    NOT NULL,
    resource_id     TEXT    NOT NULL,
    param_name      TEXT    NOT NULL,
    system          TEXT,
    code            TEXT,
    value           NUMERIC NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_quantity_value_idx
    ON idx_quantity (resource_type, param_name, value);
