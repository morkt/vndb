
-- "unofficial" flag for vn<->vn relations
ALTER TABLE vn_relations ADD COLUMN official boolean NOT NULL DEFAULT TRUE;

\i util/sql/func.sql

