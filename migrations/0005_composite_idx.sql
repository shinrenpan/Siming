-- 0005_composite_idx.sql
-- Composite search parameter index table for tuple-matching composite params
-- (e.g. component-code-value-quantity, combo-code-value-*).
-- Each row stores one (code1, value2/code2) pair extracted from a single
-- resource tuple (component, root-level, etc.).
CREATE TABLE IF NOT EXISTS idx_composite (
    resource_type TEXT               NOT NULL,
    resource_id   TEXT               NOT NULL,
    param_name    TEXT               NOT NULL,
    code1_system  TEXT,
    code1_code    TEXT               NOT NULL DEFAULT '',
    code2_system  TEXT,
    code2_code    TEXT,
    value2        DOUBLE PRECISION,
    date2_start   TIMESTAMPTZ,
    date2_end     TIMESTAMPTZ,
    string2       TEXT
);

CREATE INDEX IF NOT EXISTS idx_composite_lookup
    ON idx_composite (resource_type, param_name, code1_code);
CREATE INDEX IF NOT EXISTS idx_composite_rid
    ON idx_composite (resource_id);

-- Update clear_index_rows to also delete from idx_composite.
CREATE OR REPLACE FUNCTION clear_index_rows(rt text, rid text) RETURNS void AS $$
BEGIN
    DELETE FROM idx_token     WHERE resource_type = rt AND resource_id = rid;
    DELETE FROM idx_string    WHERE resource_type = rt AND resource_id = rid;
    DELETE FROM idx_date      WHERE resource_type = rt AND resource_id = rid;
    DELETE FROM idx_reference WHERE resource_type = rt AND resource_id = rid;
    DELETE FROM idx_quantity  WHERE resource_type = rt AND resource_id = rid;
    DELETE FROM idx_composite WHERE resource_type = rt AND resource_id = rid;
END;
$$ LANGUAGE plpgsql;
