

-- we don't use PgSQL's OIDS
SET default_with_oids = false;

-- for the functions to work, the following query must
-- be executed on the database by a superuser:
--  CREATE PROCEDURAL LANGUAGE plpgsql






-----------------------------------------
--  T A B L E   D E F I N I T I O N S  --
-----------------------------------------


-- anime
CREATE TABLE anime (
  id integer NOT NULL PRIMARY KEY,
  year smallint,
  ann_id integer,
  nfo_id varchar(200),
  type smallint,
  title_romaji,
  title_kanji,
  lastfetch timestamp
);

-- changes
CREATE TABLE changes (
  id SERIAL NOT NULL PRIMARY KEY,
  type smallint NOT NULL DEFAULT 0,
  rev integer NOT NULL DEFAULT 1,
  added bigint NOT NULL DEFAULT DATE_PART('epoch', NOW()),
  requester integer NOT NULL DEFAULT 0,
  ip inet NOT NULL DEFAULT '0.0.0.0',
  comments text NOT NULL DEFAULT '',
  causedby integer
);

-- producers
CREATE TABLE producers (
  id SERIAL NOT NULL PRIMARY KEY,
  latest integer NOT NULL DEFAULT 0,
  locked boolean NOT NULL DEFAULT FALSE,
  hidden boolean NOT NULL DEFAULT FALSE
);

-- producers_rev
CREATE TABLE producers_rev (
  id integer NOT NULL PRIMARY KEY,
  pid integer NOT NULL DEFAULT 0,
  type character(2) NOT NULL DEFAULT 'co',
  name varchar(200) NOT NULL DEFAULT '',
  original varchar(200) NOT NULL DEFAULT '',
  website varchar(250) NOT NULL DEFAULT '',
  lang varchar NOT NULL DEFAULT 'ja',
  "desc" text NOT NULL DEFAULT '',
  alias varchar(500) NOT NULL DEFAULT ''
);


-- quotes
CREATE TABLE quotes (
  vid integer NOT NULL,
  quote varchar(250) NOT NULL,
  PRIMARY KEY(vid, quote)
);


-- releases
CREATE TABLE releases (
  id SERIAL NOT NULL PRIMARY KEY,
  latest integer NOT NULL DEFAULT 0,
  locked boolean NOT NULL DEFAULT FALSE,
  hidden boolean NOT NULL DEFAULT FALSE
);

-- releases_lang
CREATE TABLE releases_lang (
  rid integer NOT NULL,
  lang varchar NOT NULL,
  PRIMARY KEY(rid, lang)
);

-- releases_media
CREATE TABLE releases_media (
  rid integer NOT NULL DEFAULT 0,
  medium character(3) NOT NULL DEFAULT '',
  qty smallint NOT NULL DEFAULT 1,
  PRIMARY KEY(rid, medium, qty)
);

-- releases_platforms
CREATE TABLE releases_platforms (
  rid integer NOT NULL DEFAULT 0,
  platform character(3) NOT NULL DEFAULT 0,
  PRIMARY KEY(rid, platform)
);

-- releases_producers
CREATE TABLE releases_producers (
  rid integer NOT NULL,
  pid integer NOT NULL,
  PRIMARY KEY(pid, rid)
);

-- releases_rev
CREATE TABLE releases_rev (
  id integer NOT NULL PRIMARY KEY,
  rid integer NOT NULL DEFAULT 0,
  title varchar(250) NOT NULL DEFAULT '',
  original varchar(250) NOT NULL DEFAULT '',
  type smallint NOT NULL DEFAULT 0,
  website varchar(250) NOT NULL DEFAULT '',
  released integer NOT NULL,
  notes text NOT NULL DEFAULT '',
  minage smallint NOT NULL DEFAULT -1,
  gtin bigint NOT NULL DEFAULT 0,
  patch boolean NOT NULL DEFAULT FALSE,
  catalog varchar(50) NOT NULL DEFAULT '',
  resolution smallint NOT NULL DEFAULT 0,
  voiced smallint NOT NULL DEFAULT 0,
  freeware boolean NOT NULL DEFAULT FALSE,
  doujin boolean NOT NULL DEFAULT FALSE,
  ani_story smallint NOT NULL DEFAULT 0,
  ani_ero smallint NOT NULL DEFAULT 0
);

-- releases_vn
CREATE TABLE releases_vn (
  rid integer NOT NULL DEFAULT 0,
  vid integer NOT NULL DEFAULT 0,
  PRIMARY KEY(rid, vid)
);

-- relgraph
CREATE TABLE relgraph (
  id SERIAL NOT NULL PRIMARY KEY,
  cmap text NOT NULL DEFAULT ''
);

-- rlists
CREATE TABLE rlists (
  uid integer NOT NULL DEFAULT 0,
  rid integer NOT NULL DEFAULT 0,
  vstat smallint NOT NULL DEFAULT 0,
  rstat smallint NOT NULL DEFAULT 0,
  added bigint NOT NULL DEFAULT DATE_PART('epoch', NOW()),
  PRIMARY KEY(uid, rid)
);

-- screenshots
CREATE TABLE screenshots (
  id SERIAL NOT NULL PRIMARY KEY,
  status smallint NOT NULL DEFAULT 0,
  width smallint NOT NULL DEFAULT 0,
  height smallint NOT NULL DEFAULT 0
);

-- stats_cache
CREATE TABLE stats_cache (
  section varchar(25) NOT NULL PRIMARY KEY,
  count integer NOT NULL DEFAULT 0
);

-- tags
CREATE TABLE tags (
  id SERIAL NOT NULL PRIMARY KEY,
  name varchar(250) NOT NULL UNIQUE,
  description text NOT NULL DEFAULT '',
  meta boolean NOT NULL DEFAULT FALSE,
  added bigint NOT NULL DEFAULT DATE_PART('epoch'::text, NOW()),
  state smallint NOT NULL DEFAULT 0,
  c_vns integer NOT NULL DEFAULT 0,
  addedby integer NOT NULL DEFAULT 1
);

-- tags_aliases
CREATE TABLE tags_aliases (
  alias varchar(250) NOT NULL PRIMARY KEY,
  tag integer NOT NULL,
);

-- tags_parents
CREATE TABLE tags_parents (
  tag integer NOT NULL,
  parent integer NOT NULL,
  PRIMARY KEY(tag, parent)
);

-- tags_vn
CREATE TABLE tags_vn (
  tag integer NOT NULL,
  vid integer NOT NULL,
  uid integer NOT NULL,
  vote smallint NOT NULL DEFAULT 3 CHECK (vote >= -3 AND vote <= 3 AND vote <> 0),
  spoiler smallint CHECK(spoiler >= 0 AND spoiler <= 2),
  PRIMARY KEY(tag, vid, uid)
);

-- tags_vn_bayesian
CREATE TABLE tags_vn_bayesian (
  tag integer NOT NULL,
  vid integer NOT NULL,
  users integer NOT NULL,
  rating real NOT NULL,
  spoiler smallint NOT NULL
);

-- threads
CREATE TABLE threads (
  id SERIAL NOT NULL PRIMARY KEY,
  title varchar(50) NOT NULL DEFAULT '',
  locked boolean NOT NULL DEFAULT FALSE,
  hidden boolean NOT NULL DEFAULT FALSE,
  count smallint NOT NULL DEFAULT 0
);

-- threads_posts
CREATE TABLE threads_posts (
  tid integer NOT NULL DEFAULT 0,
  num smallint NOT NULL DEFAULT 0,
  uid integer NOT NULL DEFAULT 0,
  date bigint NOT NULL DEFAULT DATE_PART('epoch', NOW()),
  edited bigint NOT NULL DEFAULT 0,
  msg text NOT NULL DEFAULT '',
  hidden boolean NOT NULL DEFAULT FALSE,
  PRIMARY KEY(tid, num)
);

-- threads_boards
CREATE TABLE threads_boards (
  tid integer NOT NULL DEFAULT 0,
  type character(2) NOT NULL DEFAULT 0,
  iid integer NOT NULL DEFAULT 0,
  PRIMARY KEY(tid, type, iid)
);

-- users
CREATE TABLE users (
  id SERIAL NOT NULL PRIMARY KEY,
  username varchar(20) NOT NULL UNIQUE,
  mail varchar(100) NOT NULL,
  rank smallint NOT NULL DEFAULT 3,
  passwd bytea NOT NULL DEFAULT '',
  registered bigint NOT NULL DEFAULT 0,
  show_nsfw boolean NOT NULL DEFAULT FALSE,
  show_list boolean NOT NULL DEFAULT TRUE,
  c_votes integer NOT NULL DEFAULT 0,
  c_changes integer NOT NULL DEFAULT 0,
  skin varchar(128) NOT NULL DEFAULT '',
  customcss text NOT NULL DEFAULT '',
  ip inet NOT NULL DEFAULT '0.0.0.0',
  c_tags integer NOT NULL DEFAULT 0
);

-- vn
CREATE TABLE vn (
  id SERIAL NOT NULL PRIMARY KEY,
  latest integer NOT NULL DEFAULT 0,
  locked boolean NOT NULL DEFAULT FALSE,
  hidden boolean NOT NULL DEFAULT FALSE,
  rgraph integer,
  c_released integer NOT NULL DEFAULT 0,
  c_languages varchar(32) NOT NULL DEFAULT '',
  c_platforms varchar(32) NOT NULL DEFAULT '',
  c_popularity real NOT NULL DEFAULT 0
);

-- vn_anime
CREATE TABLE vn_anime (
  vid integer NOT NULL,
  aid integer NOT NULL,
  PRIMARY KEY(vid, aid)
);

-- vn_categories
CREATE TABLE vn_categories (
  vid integer NOT NULL DEFAULT 0,
  cat character(3) NOT NULL DEFAULT '',
  lvl smallint NOT NULL DEFAULT 3,
  PRIMARY KEY(vid, cat)
);

-- vn_relations
CREATE TABLE vn_relations (
  vid1 integer NOT NULL DEFAULT 0,
  vid2 integer NOT NULL DEFAULT 0,
  relation integer NOT NULL DEFAULT 0,
  PRIMARY KEY(vid1, vid2)
);

-- vn_rev
CREATE TABLE vn_rev (
  id integer NOT NULL PRIMARY KEY,
  vid integer NOT NULL DEFAULT 0,
  title varchar(250) NOT NULL DEFAULT '',
  original varchar(250) NOT NULL DEFAULT '',
  alias varchar(500) NOT NULL DEFAULT '',
  img_nsfw boolean NOT NULL DEFAULT FALSE,
  length smallint NOT NULL DEFAULT 0,
  "desc" text NOT NULL DEFAULT '',
  l_wp varchar(150) NOT NULL DEFAULT '',
  l_vnn integer NOT NULL DEFAULT 0,
  image integer NOT NULL DEFAULT 0,
  l_encubed varchar(100) NOT NULL DEFAULT '',
  l_renai varchar(100) NOT NULL DEFAULT ''
);

-- vn_screenshots
CREATE TABLE vn_screenshots (
  vid integer NOT NULL DEFAULT 0,
  scr integer NOT NULL DEFAULT 0,
  nsfw boolean NOT NULL DEFAULT FALSE,
  rid integer DEFAULT NULL,
  PRIMARY KEY(vid, scr)
);

-- votes
CREATE TABLE votes (
  vid integer NOT NULL DEFAULT 0,
  uid integer NOT NULL DEFAULT 0,
  vote integer NOT NULL DEFAULT 0,
  date bigint NOT NULL DEFAULT 0,
  PRIMARY KEY(vid, uid)
);

-- wlists
CREATE TABLE wlists (
  uid integer NOT NULL DEFAULT 0,
  vid integer NOT NULL DEFAULT 0,
  wstat smallint NOT NULL DEFAULT 0,
  added bigint NOT NULL DEFAULT DATE_PART('epoch', NOW()),
  PRIMARY KEY(uid, vid)
);





-----------------------------------------------
--  F O R E I G N   K E Y   C H E C K I N G  --
-----------------------------------------------


ALTER TABLE changes            ADD FOREIGN KEY (requester) REFERENCES users         (id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE changes            ADD FOREIGN KEY (causedby)  REFERENCES changes       (id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE producers          ADD FOREIGN KEY (latest)    REFERENCES producers_rev (id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE producers_rev      ADD FOREIGN KEY (id)        REFERENCES changes       (id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE producers_rev      ADD FOREIGN KEY (pid)       REFERENCES producers     (id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE quotes             ADD FOREIGN KEY (vid)       REFERENCES vn            (id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE releases           ADD FOREIGN KEY (latest)    REFERENCES releases_rev  (id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE releases_lang      ADD FOREIGN KEY (rid)       REFERENCES releases_rev  (id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE releases_media     ADD FOREIGN KEY (rid)       REFERENCES releases_rev  (id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE releases_platforms ADD FOREIGN KEY (rid)       REFERENCES releases_rev  (id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE releases_producers ADD FOREIGN KEY (rid)       REFERENCES releases_rev  (id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE releases_producers ADD FOREIGN KEY (pid)       REFERENCES producers     (id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE releases_rev       ADD FOREIGN KEY (id)        REFERENCES changes       (id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE releases_rev       ADD FOREIGN KEY (rid)       REFERENCES releases      (id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE releases_vn        ADD FOREIGN KEY (rid)       REFERENCES releases_rev  (id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE releases_vn        ADD FOREIGN KEY (vid)       REFERENCES vn            (id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE rlists             ADD FOREIGN KEY (uid)       REFERENCES users         (id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE rlists             ADD FOREIGN KEY (rid)       REFERENCES releases      (id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE tags               ADD FOREIGN KEY (addedby)   REFERENCES users         (id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE tags_aliases       ADD FOREIGN KEY (tag)       REFERENCES tags          (id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE tags_parents       ADD FOREIGN KEY (tag)       REFERENCES tags          (id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE tags_parents       ADD FOREIGN KEY (parent)    REFERENCES tags          (id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE tags_vn            ADD FOREIGN KEY (tag)       REFERENCES tags          (id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE tags_vn            ADD FOREIGN KEY (vid)       REFERENCES vn            (id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE tags_vn            ADD FOREIGN KEY (uid)       REFERENCES users         (id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE threads            ADD FOREIGN KEY (id, count) REFERENCES threads_posts (tid, num) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE threads_posts      ADD FOREIGN KEY (tid)       REFERENCES threads       (id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE threads_posts      ADD FOREIGN KEY (uid)       REFERENCES users         (id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE threads_boards     ADD FOREIGN KEY (tid)       REFERENCES threads       (id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE vn                 ADD FOREIGN KEY (latest)    REFERENCES vn_rev        (id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE vn                 ADD FOREIGN KEY (rgraph)    REFERENCES relgraph      (id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE vn_anime           ADD FOREIGN KEY (aid)       REFERENCES anime         (id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE vn_anime           ADD FOREIGN KEY (vid)       REFERENCES vn_rev        (id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE vn_categories      ADD FOREIGN KEY (vid)       REFERENCES vn_rev        (id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE vn_relations       ADD FOREIGN KEY (vid1)      REFERENCES vn_rev        (id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE vn_relations       ADD FOREIGN KEY (vid2)      REFERENCES vn            (id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE vn_rev             ADD FOREIGN KEY (id)        REFERENCES changes       (id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE vn_rev             ADD FOREIGN KEY (vid)       REFERENCES vn            (id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE vn_screenshots     ADD FOREIGN KEY (vid)       REFERENCES vn_rev        (id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE vn_screenshots     ADD FOREIGN KEY (scr)       REFERENCES screenshots   (id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE vn_screenshots     ADD FOREIGN KEY (rid)       REFERENCES releases      (id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE vnlists            ADD FOREIGN KEY (uid)       REFERENCES users         (id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE vnlists            ADD FOREIGN KEY (vid)       REFERENCES vn            (id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE votes              ADD FOREIGN KEY (uid)       REFERENCES users         (id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE votes              ADD FOREIGN KEY (vid)       REFERENCES vn            (id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE wlists             ADD FOREIGN KEY (uid)       REFERENCES users         (id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE wlists             ADD FOREIGN KEY (vid)       REFERENCES vn            (id) DEFERRABLE INITIALLY DEFERRED;






-------------------------
--  F U N C T I O N S  --
-------------------------

 
-- update_rev(table, ids) - updates the rev column in the changes table
CREATE FUNCTION update_rev(tbl text, ids text) RETURNS void AS $$
DECLARE
  r RECORD;
  r2 RECORD;
  i integer;
  t text;
  e text;
BEGIN
  SELECT INTO t SUBSTRING(tbl, 1, 1);
  e := '';
  IF ids <> '' THEN
    e := ' WHERE id IN('||ids||')';
  END IF;
  FOR r IN EXECUTE 'SELECT id FROM '||tbl||e LOOP
    i := 1;
    FOR r2 IN EXECUTE 'SELECT id FROM '||tbl||'_rev WHERE '||t||'id = '||r.id||' ORDER BY id ASC' LOOP
      UPDATE changes SET rev = i WHERE id = r2.id;
      i := i+1;
    END LOOP;
  END LOOP;
END;
$$ LANGUAGE plpgsql;


-- update_vncache(id) - updates the c_* columns in the vn table
CREATE FUNCTION update_vncache(id integer) RETURNS void AS $$
DECLARE
  w text := '';
BEGIN
  IF id > 0 THEN
    w := ' WHERE id = '||id;
  END IF;
  EXECUTE 'UPDATE vn SET 
    c_released = COALESCE((SELECT
      MIN(rr1.released)
      FROM releases_rev rr1
      JOIN releases r1 ON rr1.id = r1.latest
      JOIN releases_vn rv1 ON rr1.id = rv1.rid
      WHERE rv1.vid = vn.id
      AND rr1.type <> 2
      AND r1.hidden = FALSE
      AND rr1.released <> 0
      GROUP BY rv1.vid
    ), 0),
    c_languages = COALESCE(ARRAY_TO_STRING(ARRAY(
      SELECT rl2.lang
      FROM releases_rev rr2
      JOIN releases_lang rl2 ON rl2.rid = rr2.id
      JOIN releases r2 ON rr2.id = r2.latest
      JOIN releases_vn rv2 ON rr2.id = rv2.rid
      WHERE rv2.vid = vn.id
      AND rr2.type <> 2
      AND rr2.released <= TO_CHAR(''today''::timestamp, ''YYYYMMDD'')::integer
      AND r2.hidden = FALSE
      GROUP BY rl2.lang
      ORDER BY rl2.lang
    ), ''/''), ''''),
    c_platforms = COALESCE(ARRAY_TO_STRING(ARRAY(
      SELECT rp3.platform
      FROM releases_platforms rp3
      JOIN releases_rev rr3 ON rp3.rid = rr3.id
      JOIN releases r3 ON rp3.rid = r3.latest
      JOIN releases_vn rv3 ON rp3.rid = rv3.rid
      WHERE rv3.vid = vn.id
      AND rr3.type <> 2
      AND rr3.released <= TO_CHAR(''today''::timestamp, ''YYYYMMDD'')::integer
      AND r3.hidden = FALSE
      GROUP BY rp3.platform
      ORDER BY rp3.platform
    ), ''/''), '''')
  '||w;
END;
$$ LANGUAGE plpgsql;


-- recalculate vn.c_popularity
CREATE OR REPLACE FUNCTION update_vnpopularity() RETURNS void AS $$
BEGIN
  CREATE OR REPLACE TEMP VIEW tmp_pop1 (uid, vid, rank) AS
    SELECT v.uid, v.vid, sqrt(count(*))::real FROM votes v JOIN votes v2 ON v.uid = v2.uid AND v2.vote < v.vote GROUP BY v.vid, v.uid;
  CREATE OR REPLACE TEMP VIEW tmp_pop2 (vid, win) AS
    SELECT vid, sum(rank) FROM tmp_pop1 GROUP BY vid;
  UPDATE vn SET c_popularity = COALESCE((SELECT win/(SELECT MAX(win) FROM tmp_pop2) FROM tmp_pop2 WHERE vid = id), 0);
  RETURN;
END;
$$ LANGUAGE plpgsql;


-- tag: tag to start with,
-- lvl: recursion level
-- dir: direction, true = parent->child, false = child->parent
CREATE TYPE tag_tree_item AS (lvl smallint, tag integer, name text, c_vns integer);
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


-- recalculate tags_vn_bayesian
CREATE OR REPLACE FUNCTION tag_vn_calc() RETURNS void AS $$
BEGIN
  -- all votes for all tags
  CREATE OR REPLACE TEMPORARY VIEW tags_vn_all AS
    SELECT * FROM tags_vn UNION SELECT * FROM tag_vn_childs();
  -- grouped by (tag, vid, uid), so only one user votes on one parent tag per VN entry
  CREATE OR REPLACE TEMPORARY VIEW tags_vn_grouped AS
    SELECT tag, vid, uid, MAX(vote)::real AS vote, COALESCE(AVG(spoiler), 0)::real AS spoiler
    FROM tags_vn_all WHERE vote > 0 GROUP BY tag, vid, uid;
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





-----------------------
--  T R I G G E R S  --
-----------------------


-- keep the c_* columns in the users table up to date
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

CREATE TRIGGER users_changes_update AFTER INSERT OR DELETE ON changes FOR EACH ROW EXECUTE PROCEDURE update_users_cache();
CREATE TRIGGER users_votes_update   AFTER INSERT OR DELETE ON votes   FOR EACH ROW EXECUTE PROCEDURE update_users_cache();
CREATE TRIGGER users_tags_update    AFTER INSERT OR DELETE ON tags_vn FOR EACH ROW EXECUTE PROCEDURE update_users_cache();


-- the stats_cache table
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


-- insert rows into anime for new vn_anime.aid items
CREATE OR REPLACE FUNCTION vn_anime_aid() RETURNS trigger AS $$
BEGIN
  IF NOT EXISTS(SELECT 1 FROM anime WHERE id = NEW.aid) THEN
    INSERT INTO anime (id) VALUES (NEW.aid);
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER vn_anime_aid BEFORE INSERT OR UPDATE ON vn_anime FOR EACH ROW EXECUTE PROCEDURE vn_anime_aid();


-- Send a notify whenever anime info should be fetched
CREATE OR REPLACE FUNCTION anime_fetch_notify() RETURNS trigger AS $$
BEGIN
  IF NEW.lastfetch IS NULL THEN
    NOTIFY anime;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER anime_fetch_notify AFTER INSERT OR UPDATE ON anime FOR EACH ROW EXECUTE PROCEDURE anime_fetch_notify();


-- Send a notify when a new cover image is uploaded
CREATE OR REPLACE FUNCTION vn_rev_image_notify() RETURNS trigger AS $$
BEGIN
  IF NEW.image < 0 THEN
    NOTIFY coverimage;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER vn_rev_image_notify AFTER INSERT OR UPDATE ON vn_rev FOR EACH ROW EXECUTE PROCEDURE vn_rev_image_notify();







---------------------------------
--  M I S C E L L A N E O U S  --
---------------------------------


-- Sequences used for ID generation of items not in the DB
CREATE SEQUENCE covers_seq;


-- Rows that are assumed to be available
INSERT INTO users (id, username, mail, rank)
  VALUES (0, 'deleted', 'del@vndb.org', 0);
INSERT INTO users (username, mail, rank, registered)
  VALUES ('multi', 'multi@vndb.org', 0, EXTRACT(EPOCH FROM NOW()));

INSERT INTO stats_cache (section, count) VALUES
  ('users',         1),
  ('vn',            0),
  ('producers',     0),
  ('releases',      0),
  ('threads',       0),
  ('threads_posts', 0);

