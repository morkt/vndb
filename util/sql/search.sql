
ALTER TABLE threads_posts ADD COLUMN tsmsg tsvector;
CREATE INDEX threads_posts_ts ON threads_posts USING gin(tsmsg);

CREATE OR REPLACE FUNCTION strip_bb_tags(t text) RETURNS text AS $$
BEGIN
  RETURN regexp_replace(t, '\[(?:url=[^\]]+|/?(?:b|spoiler|quote|raw|code|url|dblink))\]', ' ', 'g');
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION update_board_ts() RETURNS trigger AS $$
DECLARE
  t text;
  m text;
BEGIN
  m := strip_bb_tags(NEW.msg);
  IF NEW.num = 1 THEN
    SELECT title INTO t FROM threads WHERE id = NEW.tid;
    NEW.tsmsg := setweight(to_tsvector(t), 'A') || setweight(to_tsvector(m), 'D');
  ELSE
    NEW.tsmsg := setweight(to_tsvector(m), 'D');
  END IF;
  RETURN NEW;
END
$$ LANGUAGE plpgsql;

CREATE TRIGGER threads_posts_ts_update BEFORE INSERT OR UPDATE ON threads_posts
  FOR EACH ROW WHEN (NOT NEW.hidden) EXECUTE PROCEDURE update_board_ts();
