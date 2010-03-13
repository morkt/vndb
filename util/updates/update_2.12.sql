
-- cache for search
ALTER TABLE vn ADD COLUMN c_search text;

\i util/sql/func.sql

CREATE TRIGGER vn_vnsearch_notify         AFTER  UPDATE           ON vn            FOR EACH ROW EXECUTE PROCEDURE vn_vnsearch_notify();
CREATE TRIGGER vn_vnsearch_notify         AFTER  UPDATE           ON releases      FOR EACH ROW EXECUTE PROCEDURE vn_vnsearch_notify();

