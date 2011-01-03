
-- tag overrule feature
ALTER TABLE tags_vn ADD COLUMN ignore boolean NOT NULL DEFAULT false;


-- load new function(s)
\i util/sql/func.sql

