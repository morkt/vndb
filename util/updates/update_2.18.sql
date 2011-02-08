
CREATE TYPE tag_category AS ENUM('cont', 'ero', 'tech');

ALTER TABLE tags ADD COLUMN cat tag_category NOT NULL DEFAULT 'cont';

-- load new function(s)
\i util/sql/func.sql

