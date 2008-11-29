

-- cache users vote and edit count
ALTER TABLE users ADD COLUMN c_votes integer NOT NULL DEFAULT 0;
ALTER TABLE users ADD COLUMN c_changes integer NOT NULL DEFAULT 0;


-- may be an idea to run this query as a monthly cron or something
UPDATE users SET
  c_votes = COALESCE(
    (SELECT COUNT(vid)
    FROM votes
    WHERE uid = users.id
    GROUP BY uid
  ), 0),
  c_changes = COALESCE(
    (SELECT COUNT(id)
    FROM changes
    WHERE requester = users.id
    GROUP BY requester
  ), 0);


-- one function to rule them all
CREATE OR REPLACE FUNCTION update_users_cache() RETURNS TRIGGER AS $$
BEGIN
  IF TG_TABLE_NAME = 'votes' THEN
    IF TG_OP = 'INSERT' THEN
      UPDATE users SET c_votes = c_votes + 1 WHERE id = NEW.uid;
    ELSE
      UPDATE users SET c_votes = c_votes - 1 WHERE id = OLD.uid;
    END IF;
  ELSE
    IF TG_OP = 'INSERT' THEN
      UPDATE users SET c_changes = c_changes + 1 WHERE id = NEW.requester;
    ELSE
      UPDATE users SET c_changes = c_changes - 1 WHERE id = OLD.requester;
    END IF;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE 'plpgsql';

CREATE TRIGGER users_changes_update AFTER INSERT OR DELETE ON changes FOR EACH ROW EXECUTE PROCEDURE update_users_cache();
CREATE TRIGGER users_votes_update   AFTER INSERT OR DELETE ON votes   FOR EACH ROW EXECUTE PROCEDURE update_users_cache();




-- users.flags -> users.(show_nsfw|show_list)
ALTER TABLE users ADD COLUMN show_nsfw boolean NOT NULL DEFAULT FALSE;
ALTER TABLE users ADD COLUMN show_list boolean NOT NULL DEFAULT TRUE;

UPDATE users SET
  show_nsfw = (flags & 8 = 8),
  show_list = (flags & 4 = 4);

ALTER TABLE users DROP COLUMN flags;




-- get rid of \r
UPDATE vn_rev
  SET "desc"   = translate("desc",   E'\r', ''),
      alias    = translate(alias,    E'\r', '');
UPDATE releases_rev
  SET notes    = translate(notes,    E'\r', '');
UPDATE producers_rev
  SET "desc"   = translate("desc",   E'\r', '');
UPDATE changes
  SET comments = translate(comments, E'\r', '');
UPDATE threads_posts
  SET msg      = translate(msg,      E'\r', '');




-- cache some database statistics
CREATE TABLE stats_cache (
  section varchar(25) NOT NULL PRIMARY KEY,
  count integer NOT NULL DEFAULT 0
);
INSERT INTO stats_cache (section, count) VALUES
  ('users',         (SELECT COUNT(*) FROM users)-1),
  ('vn',            (SELECT COUNT(*) FROM vn            WHERE hidden = FALSE)),
  ('producers',     (SELECT COUNT(*) FROM producers     WHERE hidden = FALSE)),
  ('releases',      (SELECT COUNT(*) FROM releases      WHERE hidden = FALSE)),
  ('threads',       (SELECT COUNT(*) FROM threads       WHERE hidden = FALSE)),
  ('threads_posts', (SELECT COUNT(*) FROM threads_posts WHERE hidden = FALSE AND EXISTS(SELECT 1 FROM threads WHERE threads.id = tid AND threads.hidden = FALSE)));

CREATE OR REPLACE FUNCTION update_stats_cache() RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF TG_TABLE_NAME = 'users' THEN
      UPDATE stats_cache SET count = count+1 WHERE section = TG_TABLE_NAME;
    ELSIF NEW.hidden = FALSE THEN
      IF TG_TABLE_NAME = 'threads_posts' THEN
        IF EXISTS(SELECT 1 FROM threads WHERE id = NEW.tid AND hidden = FALSE) THEN
          UPDATE stats_cache SET count = count+1 WHERE section = TG_TABLE_NAME;
        END IF;
      ELSE
        UPDATE stats_cache SET count = count+1 WHERE section = TG_TABLE_NAME;
      END IF;
    END IF;

  ELSIF TG_OP = 'UPDATE' AND TG_TABLE_NAME <> 'users' THEN
    IF OLD.hidden = TRUE AND NEW.hidden = FALSE THEN
      IF TG_TABLE_NAME = 'threads' THEN
        UPDATE stats_cache SET count = count+NEW.count WHERE section = 'threads_posts';
      END IF;
      UPDATE stats_cache SET count = count+1 WHERE section = TG_TABLE_NAME;
    ELSIF OLD.hidden = FALSE AND NEW.hidden = TRUE THEN
      IF TG_TABLE_NAME = 'threads' THEN
        UPDATE stats_cache SET count = count-NEW.count WHERE section = 'threads_posts';
      END IF;
      UPDATE stats_cache SET count = count-1 WHERE section = TG_TABLE_NAME;
    END IF;

  ELSIF TG_OP = 'DELETE' AND TG_TABLE_NAME = 'users' THEN
    UPDATE stats_cache SET count = count-1 WHERE section = TG_TABLE_NAME;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE 'plpgsql';

CREATE TRIGGER vn_stats_update            AFTER INSERT OR UPDATE ON vn            FOR EACH ROW EXECUTE PROCEDURE update_stats_cache();
CREATE TRIGGER producers_stats_update     AFTER INSERT OR UPDATE ON producers     FOR EACH ROW EXECUTE PROCEDURE update_stats_cache();
CREATE TRIGGER releases_stats_update      AFTER INSERT OR UPDATE ON releases      FOR EACH ROW EXECUTE PROCEDURE update_stats_cache();
CREATE TRIGGER threads_stats_update       AFTER INSERT OR UPDATE ON threads       FOR EACH ROW EXECUTE PROCEDURE update_stats_cache();
CREATE TRIGGER threads_posts_stats_update AFTER INSERT OR UPDATE ON threads_posts FOR EACH ROW EXECUTE PROCEDURE update_stats_cache();
CREATE TRIGGER users_stats_update         AFTER INSERT OR DELETE ON users         FOR EACH ROW EXECUTE PROCEDURE update_stats_cache();


