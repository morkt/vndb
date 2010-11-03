
-- use newlines to separate aliases
-- (note: this will go wrong with titles that contain a comma. Those have to be fixed manually)
UPDATE vn_rev SET alias = trim(both ' ' from regexp_replace(alias, ' *, *', E'\n', 'g'));


-- cache for search
ALTER TABLE vn ADD COLUMN c_search text;

\i util/sql/func.sql

CREATE TRIGGER vn_vnsearch_notify         AFTER  UPDATE           ON vn            FOR EACH ROW EXECUTE PROCEDURE vn_vnsearch_notify();
CREATE TRIGGER vn_vnsearch_notify         AFTER  UPDATE           ON releases      FOR EACH ROW EXECUTE PROCEDURE vn_vnsearch_notify();


-- two new resolutions have been added, array indexes have changed
UPDATE releases_rev SET resolution = resolution + 1 WHERE resolution >= 7;
UPDATE releases_rev SET resolution = resolution + 1 WHERE resolution >= 11;


