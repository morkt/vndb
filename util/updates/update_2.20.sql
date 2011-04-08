
ALTER TYPE notification_ltype RENAME TO tmp;
CREATE TYPE notification_ltype AS ENUM ('v', 'r', 'p', 'c', 't');
ALTER TABLE notifications ALTER COLUMN ltype TYPE notification_ltype USING ltype::text::notification_ltype;
DROP TYPE tmp;

\i util/sql/func.sql

CREATE TRIGGER notify_dbdel               AFTER  UPDATE           ON chars         FOR EACH ROW WHEN (NOT OLD.hidden AND NEW.hidden) EXECUTE PROCEDURE notify_dbdel();
CREATE TRIGGER notify_dbedit              AFTER  UPDATE           ON chars         FOR EACH ROW WHEN (OLD.latest IS DISTINCT FROM NEW.latest AND NOT NEW.hidden) EXECUTE PROCEDURE notify_dbedit();


INSERT INTO stats_cache VALUES
  ('chars',  (SELECT COUNT(*) FROM chars WHERE NOT hidden)),
  ('tags',   (SELECT COUNT(*) FROM tags WHERE state = 2)),
  ('traits', (SELECT COUNT(*) FROM traits WHERE state = 2));

CREATE TRIGGER stats_cache_new            AFTER  INSERT           ON chars         FOR EACH ROW WHEN (NEW.hidden = FALSE) EXECUTE PROCEDURE update_stats_cache();
CREATE TRIGGER stats_cache_edit           AFTER  UPDATE           ON chars         FOR EACH ROW WHEN (OLD.hidden IS DISTINCT FROM NEW.hidden) EXECUTE PROCEDURE update_stats_cache();
CREATE TRIGGER stats_cache_new            AFTER  INSERT           ON tags          FOR EACH ROW WHEN (NEW.state = 2) EXECUTE PROCEDURE update_stats_cache();
CREATE TRIGGER stats_cache_edit           AFTER  UPDATE           ON tags          FOR EACH ROW WHEN (OLD.state IS DISTINCT FROM NEW.state) EXECUTE PROCEDURE update_stats_cache();
CREATE TRIGGER stats_cache_new            AFTER  INSERT           ON traits        FOR EACH ROW WHEN (NEW.state = 2) EXECUTE PROCEDURE update_stats_cache();
CREATE TRIGGER stats_cache_edit           AFTER  UPDATE           ON traits        FOR EACH ROW WHEN (OLD.state IS DISTINCT FROM NEW.state) EXECUTE PROCEDURE update_stats_cache();

