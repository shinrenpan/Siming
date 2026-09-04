-- 0006_resources_current_idx.sql
-- Follows the deleted-row fix in buildIdsInner / buildCountIdsInner.
--
-- The `ids` CTE used to pick the current version with `deleted = false` inside
-- the DISTINCT ON / LATERAL subquery, which made a deleted resource fall back to
-- its last live version instead of disappearing. The predicate now runs AFTER
-- the current-version pick, so the pick itself must read tombstones too — and
-- can therefore no longer use the partial `resources_live_idx`.
--
-- INCLUDE, not trailing key columns: last_updated and deleted are payload, never
-- ordering. Keeping the key at three columns matches resources_pkey's width, so
-- the planner still chooses this index and gets an index-only scan, and the
-- index stays 6.6 MB instead of 22 MB at 100k versions.
--
-- Measured at 100k versions / 45k live resources, against the pre-fix baseline:
--   LATERAL path (any filtered search)   81.7 ms -> 85.6 ms
--   DISTINCT ON path (unfiltered scan)   12.2 ms -> 14.1 ms
-- Spelling the index with trailing key columns instead of INCLUDE costs 17.7 ms
-- on the second one, and omitting it entirely 30 ms (the planner then falls back
-- to resources_pkey and pays for heap access).
CREATE INDEX IF NOT EXISTS resources_current_covering_idx
    ON resources (resource_type, id, version_id DESC)
    INCLUDE (last_updated, deleted);

-- resources_live_idx (0002) had `WHERE deleted = FALSE`. No query carries that
-- predicate any more, so it can never be chosen. Drop it rather than pay for it
-- on every write.
DROP INDEX IF EXISTS resources_live_idx;

-- resources_current_version_idx (0001) is (resource_type, id, version_id DESC) —
-- exactly the key of the index above, so it can serve nothing that index cannot,
-- and the planner prefers the covering one anyway. Drop it too.
DROP INDEX IF EXISTS resources_current_version_idx;
