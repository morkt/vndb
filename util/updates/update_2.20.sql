
ALTER TYPE notification_ltype RENAME TO tmp;
CREATE TYPE notification_ltype AS ENUM ('v', 'r', 'p', 'c', 't');
ALTER TABLE notifications ALTER COLUMN ltype TYPE notification_ltype USING ltype::text::notification_ltype;
DROP TYPE tmp;

\i util/sql/func.sql

CREATE TRIGGER notify_dbdel               AFTER  UPDATE           ON chars         FOR EACH ROW WHEN (NOT OLD.hidden AND NEW.hidden) EXECUTE PROCEDURE notify_dbdel();
CREATE TRIGGER notify_dbedit              AFTER  UPDATE           ON chars         FOR EACH ROW WHEN (OLD.latest IS DISTINCT FROM NEW.latest AND NOT NEW.hidden) EXECUTE PROCEDURE notify_dbedit();

