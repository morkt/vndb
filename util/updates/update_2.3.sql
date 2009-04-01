
-- some random VN quotes
CREATE TABLE quotes (
  vid integer NOT NULL REFERENCES vn (id),
  quote varchar(250) NOT NULL,
  PRIMARY KEY(vid, quote)
) WITHOUT OIDS;


-- catalog numbers for releases
ALTER TABLE releases_rev ADD COLUMN catalog varchar(50) NOT NULL DEFAULT '';


-- aliases field for producers
ALTER TABLE producers_rev ADD COLUMN alias varchar(500) NOT NULL DEFAULT '';



-- tagging system

CREATE TABLE tags (
  id          SERIAL       NOT NULL PRIMARY KEY,
  name        varchar(250) NOT NULL UNIQUE,
  description text         NOT NULL DEFAULT '',
  meta        boolean      NOT NULL DEFAULT FALSE,
  added       bigint       NOT NULL DEFAULT DATE_PART('epoch'::text, NOW()),
  state       smallint     NOT NULL DEFAULT 0, -- 0: awaiting moderation, 1: deleted, 2: accepted
  c_vns       integer      NOT NULL DEFAULT 0
) WITHOUT OIDS;

CREATE TABLE tags_aliases (
  alias  varchar(250) NOT NULL PRIMARY KEY,
  tag    integer      NOT NULL REFERENCES tags (id) DEFERRABLE INITIALLY DEFERRED
) WITHOUT OIDS;

CREATE TABLE tags_parents (
  tag    integer NOT NULL REFERENCES tags (id) DEFERRABLE INITIALLY DEFERRED,
  parent integer NOT NULL REFERENCES tags (id) DEFERRABLE INITIALLY DEFERRED,
  PRIMARY KEY(tag, parent)
) WITHOUT OIDS;

CREATE TABLE tags_vn (
  tag     integer  NOT NULL REFERENCES tags  (id) DEFERRABLE INITIALLY DEFERRED,
  vid     integer  NOT NULL REFERENCES vn    (id) DEFERRABLE INITIALLY DEFERRED,
  uid     integer  NOT NULL REFERENCES users (id) DEFERRABLE INITIALLY DEFERRED,
  vote    smallint NOT NULL DEFAULT 3 CHECK (vote >= -3 AND vote <= 3 AND vote <> 0),
  spoiler smallint CHECK(spoiler >= 0 AND spoiler <= 2),
  PRIMARY KEY(tag, vid, uid)
) WITHOUT OIDS;

CREATE TABLE tags_vn_bayesian (
  tag     integer  NOT NULL,
  vid     integer  NOT NULL,
  users   integer  NOT NULL,
  rating  real     NOT NULL,
  spoiler smallint NOT NULL
) WITHOUT OIDS;


CREATE TYPE tag_tree_item AS (lvl smallint, tag integer, name text, c_vns integer);

-- tag: tag to start with,
-- lvl: recursion level
-- dir: direction, true = parent->child, false = child->parent
CREATE OR REPLACE FUNCTION tag_tree(tag integer, lvl integer, dir boolean) RETURNS SETOF tag_tree_item AS $$
DECLARE
  r tag_tree_item%rowtype;
  r2 tag_tree_item%rowtype;
BEGIN
  IF dir AND tag = 0 THEN
    FOR r IN
      SELECT lvl, t.id, t.name, t.c_vns
        FROM tags t
        WHERE state = 2 AND NOT EXISTS(SELECT 1 FROM tags_parents tp WHERE tp.tag = t.id)
        ORDER BY t.name
    LOOP
      RETURN NEXT r;
      IF lvl-1 <> 0 THEN
        FOR r2 IN SELECT * FROM tag_tree(r.tag, lvl-1, dir) LOOP
          RETURN NEXT r2;
        END LOOP;
      END IF;
    END LOOP;
  ELSIF dir THEN
    FOR r IN
      SELECT lvl, tp.tag, t.name, t.c_vns
        FROM tags_parents tp
        JOIN tags t ON t.id = tp.tag
        WHERE tp.parent = tag
          AND state = 2
        ORDER BY t.name
    LOOP
      RETURN NEXT r;
      IF lvl-1 <> 0 THEN
        FOR r2 IN SELECT * FROM tag_tree(r.tag, lvl-1, dir) LOOP
          RETURN NEXT r2;
        END LOOP;
      END IF;
    END LOOP;
  ELSE
    FOR r IN
      SELECT lvl, tp.parent, t.name, t.c_vns
        FROM tags_parents tp
        JOIN tags t ON t.id = tp.parent
        WHERE tp.tag = tag
          AND state = 2
        ORDER BY t.name
    LOOP
      RETURN NEXT r;
      IF lvl-1 <> 0 THEN
        FOR r2 IN SELECT * FROM tag_tree(r.tag, lvl-1, dir) LOOP
          RETURN NEXT r2;
        END LOOP;
      END IF;
    END LOOP;
  END IF;
END;
$$ LANGUAGE plpgsql;

-- returns all votes inherited by childs
-- UNION this with tags_vn and you have all votes for all tags
CREATE OR REPLACE FUNCTION tag_vn_childs() RETURNS SETOF tags_vn AS $$
DECLARE
  r tags_vn%rowtype;
  i RECORD;
  l RECORD;
BEGIN
  FOR l IN SElECT id FROM tags WHERE meta = FALSE AND state = 2 AND EXISTS(SELECT 1 FROM tags_parents WHERE parent = id) LOOP
    FOR i IN SELECT tag FROM tag_tree(l.id, 0, true) LOOP
      FOR r IN SELECT l.id, vid, uid, vote, spoiler FROM tags_vn WHERE tag = i.tag LOOP
        RETURN NEXT r;
      END LOOP;
    END LOOP;
  END LOOP;
END;
$$ LANGUAGE plpgsql;

-- updates tags_vn_bayesian with rankings of tags
CREATE OR REPLACE FUNCTION tag_vn_calc() RETURNS void AS $$
BEGIN
  -- all votes for all tags
  CREATE OR REPLACE TEMPORARY VIEW tags_vn_all AS
    SELECT * FROM tags_vn UNION SELECT * FROM tag_vn_childs();
  -- grouped by (tag, vid, uid), so only one user votes on one parent tag per VN entry
  CREATE OR REPLACE TEMPORARY VIEW tags_vn_grouped AS
    SELECT tag, vid, uid, MAX(vote)::real AS vote, COALESCE(AVG(spoiler), 0)::real AS spoiler
    FROM tags_vn_all GROUP BY tag, vid, uid;
  -- grouped by (tag, vid) and serialized into a table
  DROP INDEX IF EXISTS tags_vn_bayesian_tag;
  TRUNCATE tags_vn_bayesian;
  INSERT INTO tags_vn_bayesian
      SELECT tag, vid, COUNT(uid) AS users, AVG(vote)::real AS rating,
          (CASE WHEN AVG(spoiler) < 0.7 THEN 0 WHEN AVG(spoiler) > 1.3 THEN 2 ELSE 1 END)::smallint AS spoiler
        FROM tags_vn_grouped
    GROUP BY tag, vid;
  CREATE INDEX tags_vn_bayesian_tag ON tags_vn_bayesian (tag);
  -- now perform the bayesian ranking calculation
  UPDATE tags_vn_bayesian tvs SET rating =
      ((SELECT AVG(users)::real * AVG(rating)::real FROM tags_vn_bayesian WHERE tag = tvs.tag) + users*rating)
    / ((SELECT AVG(users)::real FROM tags_vn_bayesian WHERE tag = tvs.tag) + users)::real;
  -- and update the VN count in the tags table as well
  UPDATE tags SET c_vns = (SELECT COUNT(*) FROM tags_vn_bayesian WHERE tag = id);
  RETURN;
END;
$$ LANGUAGE plpgsql;
SELECT tag_vn_calc();



-- Cache users tag vote count
ALTER TABLE users ADD COLUMN c_tags integer NOT NULL DEFAULT 0;
UPDATE users SET c_tags = (SELECT COUNT(*) FROM tags_vn WHERE uid = id);

CREATE OR REPLACE FUNCTION update_users_cache() RETURNS TRIGGER AS $$
BEGIN
  IF TG_TABLE_NAME = 'votes' THEN
    IF TG_OP = 'INSERT' THEN
      UPDATE users SET c_votes = c_votes + 1 WHERE id = NEW.uid;
    ELSE
      UPDATE users SET c_votes = c_votes - 1 WHERE id = OLD.uid;
    END IF;
  ELSIF TG_TABLE_NAME = 'changes' THEN
    IF TG_OP = 'INSERT' THEN
      UPDATE users SET c_changes = c_changes + 1 WHERE id = NEW.requester;
    ELSE
      UPDATE users SET c_changes = c_changes - 1 WHERE id = OLD.requester;
    END IF;
  ELSIF TG_TABLE_NAME = 'tags_vn' THEN
    IF TG_OP = 'INSERT' THEN
      UPDATE users SET c_tags = c_tags + 1 WHERE id = NEW.uid;
    ELSE
      UPDATE users SET c_tags = c_tags - 1 WHERE id = OLD.uid;
    END IF;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE 'plpgsql';

CREATE TRIGGER users_tags_update AFTER INSERT OR DELETE ON tags_vn FOR EACH ROW EXECUTE PROCEDURE update_users_cache();



-- rename threads tags to boards
ALTER TABLE threads_tags RENAME TO threads_boards;

