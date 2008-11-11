

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


