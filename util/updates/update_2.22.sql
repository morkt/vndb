

DROP TRIGGER vn_vnsearch_notify ON vn;

CREATE TRIGGER vn_vnsearch_notify AFTER UPDATE ON vn FOR EACH ROW
  WHEN (OLD.c_search IS NOT NULL AND NEW.c_search IS NULL
     OR NEW.latest IS DISTINCT FROM OLD.latest
  ) EXECUTE PROCEDURE vn_vnsearch_notify();

\i util/sql/func.sql

