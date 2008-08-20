

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
  year smallint NOT NULL DEFAULT 0,
  ann_id integer NOT NULL DEFAULT 0,
  nfo_id varchar(200) NOT NULL DEFAULT '',
  type smallint NOT NULL DEFAULT 0,
  title_romaji varchar(200) NOT NULL DEFAULT '',
  title_kanji varchar(200) NOT NULL DEFAULT '',
  lastfetch bigint NOT NULL DEFAULT 0
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
  "desc" text NOT NULL DEFAULT ''
);

-- releases
CREATE TABLE releases (
  id SERIAL NOT NULL PRIMARY KEY,
  latest integer NOT NULL DEFAULT 0,
  locked boolean NOT NULL DEFAULT FALSE,
  hidden boolean NOT NULL DEFAULT FALSE
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
  language varchar NOT NULL DEFAULT 'ja',
  website varchar(250) NOT NULL DEFAULT '',
  released integer NOT NULL,
  notes text NOT NULL DEFAULT '',
  minage smallint NOT NULL DEFAULT -1,
  gtin bigint NOT NULL DEFAULT 0
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

-- threads_tags
CREATE TABLE threads_tags (
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
  rank smallint NOT NULL DEFAULT 2,
  passwd bytea NOT NULL DEFAULT '',
  registered bigint NOT NULL DEFAULT 0,
  flags integer NOT NULL DEFAULT 7
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
  c_platforms varchar(32) NOT NULL DEFAULT ''
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
  PRIMARY KEY(vid, scr)
);

-- vnlists
CREATE TABLE vnlists (
  uid integer DEFAULT 0,
  vid integer NOT NULL DEFAULT 0,
  status smallint NOT NULL DEFAULT 0,
  date bigint NOT NULL DEFAULT 0,
  comments varchar(500) NOT NULL DEFAULT '',
  PRIMARY KEY(uid, vid)
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
ALTER TABLE releases           ADD FOREIGN KEY (latest)    REFERENCES releases_rev  (id) DEFERRABLE INITIALLY DEFERRED;
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
ALTER TABLE threads            ADD FOREIGN KEY (id, count) REFERENCES threads_posts (tid, num) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE threads_posts      ADD FOREIGN KEY (tid)       REFERENCES threads       (id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE threads_posts      ADD FOREIGN KEY (uid)       REFERENCES users         (id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE threads_tags       ADD FOREIGN KEY (tid)       REFERENCES threads       (id) DEFERRABLE INITIALLY DEFERRED;
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
      SELECT language
      FROM releases_rev rr2
      JOIN releases r2 ON rr2.id = r2.latest
      JOIN releases_vn rv2 ON rr2.id = rv2.rid
      WHERE rv2.vid = vn.id
      AND rr2.type <> 2
      AND rr2.released <= TO_CHAR(''today''::timestamp, ''YYYYMMDD'')::integer
      AND r2.hidden = FALSE
      GROUP BY rr2.language
      ORDER BY rr2.language
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






---------------------------------
--  M I S C E L L A N E O U S  --
---------------------------------


-- Sequences used for ID generation of items not in the DB
CREATE SEQUENCE covers_seq;

INSERT INTO users (id, username, mail, rank)
  VALUES (0, 'deleted', 'del@vndb.org', 0);
INSERT INTO users (username, mail, rank, registered)
  VALUES ('multi', 'multi@vndb.org', 0, EXTRACT(EPOCH FROM NOW()));

