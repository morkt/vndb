
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



CREATE TABLE affiliate_links (
  id SERIAL PRIMARY KEY,
  rid integer NOT NULL REFERENCES releases (id),
  hidden boolean NOT NULL DEFAULT false, -- to hide a link for some reason
  priority smallint NOT NULL DEFAULT 0,  -- manual ordering when competing on a VN page, usually not necessary
  affiliate smallint NOT NULL DEFAULT 0, -- index to a semi-static array in data/config.pl
  url varchar NOT NULL,
  version varchar NOT NULL DEFAULT '', -- "x edition" or "x version", default used is "<language> version"
  lastfetch timestamptz, -- last update of price
  price varchar NOT NULL DEFAULT '', -- formatted, including currency, e.g. "$50" or "€34.95 / $50.46"
  data varchar NOT NULL DEFAULT '' -- to be used by a fetch bot, if any
);

CREATE INDEX affiliate_links_rid ON affiliate_links (rid) WHERE NOT hidden;



-- rank -> permissions

ALTER TABLE users RENAME rank TO perm;
ALTER TABLE users ALTER COLUMN perm SET DEFAULT 1+4+16;
UPDATE users SET perm = CASE
  WHEN perm = 2 THEN 1
  WHEN perm = 3 THEN 1+4+16
  WHEN perm = 4 THEN 1+2+4+8+16+32+64
  WHEN perm = 5 THEN 1+2+4+8+16+32+64+128+256
  ELSE 0 END;

