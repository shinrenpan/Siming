-- 0003_functions.sql
-- Server-side helper that clears all five index tables for one resource in a
-- single function call, replacing five individual DELETE round trips with one.
CREATE OR REPLACE FUNCTION clear_index_rows(rt text, rid text) RETURNS void AS $$
BEGIN
    DELETE FROM idx_token     WHERE resource_type = rt AND resource_id = rid;
    DELETE FROM idx_string    WHERE resource_type = rt AND resource_id = rid;
    DELETE FROM idx_date      WHERE resource_type = rt AND resource_id = rid;
    DELETE FROM idx_reference WHERE resource_type = rt AND resource_id = rid;
    DELETE FROM idx_quantity  WHERE resource_type = rt AND resource_id = rid;
END;
$$ LANGUAGE plpgsql;
