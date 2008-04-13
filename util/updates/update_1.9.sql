CREATE TABLE changes (
  id SERIAL NOT NULL PRIMARY KEY,
  "type" smallint NOT NULL DEFAULT 0,
  added bigint NOT NULL DEFAULT EXTRACT(EPOCH FROM NOW()),
  requester integer NOT NULL DEFAULT 0,
  ip inet NOT NULL DEFAULT '0.0.0.0',
  comments text NOT NULL DEFAULT '',
  prev integer NOT NULL DEFAULT 0,
  causedby integer NOT NULL DEFAULT 0
) WITHOUT OIDS;

INSERT INTO users (id, username, mail, rank, registered)
  VALUES (1, 'multi', 'multi@vndb.org', 0, EXTRACT(EPOCH FROM NOW()));

CREATE OR REPLACE FUNCTION get_new_id(tbl text) RETURNS integer AS $$
DECLARE
  i integer := 1;
  r RECORD;
BEGIN
  FOR r IN EXECUTE 'SELECT id FROM '||tbl||' ORDER BY id ASC' LOOP
    IF i <> r.id THEN
      EXIT;
    END IF;
    i := i + 1;
  END LOOP;
  RETURN i;
END;
$$ LANGUAGE plpgsql;




--                V i s u a l   N o v e l s 


ALTER TABLE vn RENAME TO vn_old;
ALTER TABLE vn_relations RENAME TO vn_relations_old;

CREATE TABLE vn (
  id integer NOT NULL DEFAULT get_new_id('vn') PRIMARY KEY,
  latest integer NOT NULL DEFAULT 0,
  locked smallint NOT NULL DEFAULT 0,
  rgraph bytea NOT NULL DEFAULT '',
  c_released character(7) NOT NULL DEFAULT '0000-00',
  c_languages varchar(32) NOT NULL DEFAULT '',
  c_votes character(9) NOT NULL DEFAULT '00.0|0000'
) WITHOUT OIDS;

CREATE TABLE vn_rev (
  id integer NOT NULL PRIMARY KEY,
  vid integer NOT NULL DEFAULT 0,
  title varchar(250) NOT NULL DEFAULT '',
  alias varchar(500) NOT NULL DEFAULT '',
  image bytea NOT NULL DEFAULT '',
  img_nsfw smallint NOT NULL DEFAULT 0,
  length smallint NOT NULL DEFAULT 0,
  "desc" text NOT NULL DEFAULT '',
  categories integer NOT NULL DEFAULT 0,
  l_wp varchar(150) NOT NULL DEFAULT '',
  l_cisv integer NOT NULL DEFAULT 0
) WITHOUT OIDS;

CREATE TABLE vn_relations (
  vid1 integer NOT NULL DEFAULT 0,
  vid2 integer NOT NULL DEFAULT 0,
  relation integer NOT NULL DEFAULT 0,
  PRIMARY KEY(vid1, vid2)
) WITHOUT OIDS;

CREATE OR REPLACE FUNCTION fill_vn() RETURNS void AS $$
DECLARE
  r RECORD;
  r2 RECORD;
  i integer;
  rel integer;
BEGIN
  FOR r IN SELECT * FROM vn_old ORDER BY added LOOP
    INSERT INTO changes ("type", added, requester, comments)
      VALUES (0, r.added, 1, 'Automated import from VNDB 1.8');

    SELECT currval('changes_id_seq') INTO i;

    INSERT INTO vn_rev (id, vid, title, alias, image, img_nsfw, length, "desc", l_wp, l_cisv, categories)
      VALUES (i, r.id, r.title, r.alias, r.image, r.img_nsfw, r.length, r.desc, r.l_wp, r.l_cisv, (
      -- ZOMFG DENORMALIZATION LOL!
        COALESCE((SELECT       1 FROM vn_categories WHERE vid = r.id AND category = 'eac'), 0)
       +COALESCE((SELECT       2 FROM vn_categories WHERE vid = r.id AND category = 'eco'), 0)
       +COALESCE((SELECT       4 FROM vn_categories WHERE vid = r.id AND category = 'edr'), 0)
       +COALESCE((SELECT       8 FROM vn_categories WHERE vid = r.id AND category = 'efa'), 0)
       +COALESCE((SELECT      16 FROM vn_categories WHERE vid = r.id AND category = 'eho'), 0)
       +COALESCE((SELECT      32 FROM vn_categories WHERE vid = r.id AND category = 'emy'), 0)
       +COALESCE((SELECT      64 FROM vn_categories WHERE vid = r.id AND category = 'ero'), 0)
       +COALESCE((SELECT     128 FROM vn_categories WHERE vid = r.id AND category = 'esf'), 0)
       +COALESCE((SELECT     256 FROM vn_categories WHERE vid = r.id AND category = 'eja'), 0)
       +COALESCE((SELECT     512 FROM vn_categories WHERE vid = r.id AND category = 'ena'), 0)
       +COALESCE((SELECT    1024 FROM vn_categories WHERE vid = r.id AND category = 'tfu'), 0)
       +COALESCE((SELECT    2048 FROM vn_categories WHERE vid = r.id AND category = 'tpa'), 0)
       +COALESCE((SELECT    4096 FROM vn_categories WHERE vid = r.id AND category = 'tpr'), 0)
       +COALESCE((SELECT    8192 FROM vn_categories WHERE vid = r.id AND category = 'pea'), 0)
       +COALESCE((SELECT   16384 FROM vn_categories WHERE vid = r.id AND category = 'pfw'), 0)
       +COALESCE((SELECT   32768 FROM vn_categories WHERE vid = r.id AND category = 'psp'), 0)
       +COALESCE((SELECT   65536 FROM vn_categories WHERE vid = r.id AND category = 'spa'), 0)
       +COALESCE((SELECT  131072 FROM vn_categories WHERE vid = r.id AND category = 'sbe'), 0)
       +COALESCE((SELECT  262144 FROM vn_categories WHERE vid = r.id AND category = 'sin'), 0)
       +COALESCE((SELECT  524288 FROM vn_categories WHERE vid = r.id AND category = 'slo'), 0)
       +COALESCE((SELECT 1048576 FROM vn_categories WHERE vid = r.id AND category = 'scc'), 0)
       +COALESCE((SELECT 2097152 FROM vn_categories WHERE vid = r.id AND category = 'sya'), 0)
       +COALESCE((SELECT 4194304 FROM vn_categories WHERE vid = r.id AND category = 'syu'), 0)
       +COALESCE((SELECT 8388608 FROM vn_categories WHERE vid = r.id AND category = 'sra'), 0)
      ));

    INSERT INTO vn (id, latest, locked, rgraph, c_released, c_languages, c_votes)
      VALUES (r.id, i, r.locked, r.rgraph, r.c_released, r.c_languages, r.c_votes);
  
    FOR r2 IN SELECT * FROM vn_relations_old WHERE vid2 = r.id LOOP
      INSERT INTO vn_relations (vid1, vid2, relation)
        VALUES(i, r2.vid1, r2.relation);
    END LOOP;
    FOR r2 IN SELECT * FROM vn_relations_old WHERE vid1 = r.id LOOP
      rel := r2.relation;
      IF rel = 0 OR rel = 6 OR rel = 8 THEN
        rel := rel+1;
      END IF;
      INSERT INTO vn_relations (vid1, vid2, relation)
        VALUES(i, r2.vid2, rel);
    END LOOP;
  END LOOP;
END;
$$ LANGUAGE plpgsql;
SELECT fill_vn();
DROP FUNCTION fill_vn();





--                R e l e a s e s 


ALTER TABLE vnr RENAME TO vnr_old;

CREATE TABLE releases (
  id integer NOT NULL DEFAULT get_new_id('releases') PRIMARY KEY,
  latest integer NOT NULL DEFAULT 0,
  vid integer NOT NULL DEFAULT 0,
  locked smallint NOT NULL DEFAULT 0
) WITHOUT OIDS;

CREATE TABLE releases_rev (
  id integer NOT NULL PRIMARY KEY,
  rid integer NOT NULL DEFAULT 0,
  title varchar(250) NOT NULL DEFAULT '',
  original varchar(250) NOT NULL DEFAULT '',
  "type" smallint NOT NULL DEFAULT 0,
  relation varchar(32) NOT NULL DEFAULT '', -- deprecated
  language varchar NOT NULL DEFAULT 'ja',
  website varchar(250) NOT NULL DEFAULT '',
  released varchar(10),
  notes varchar(250) NOT NULL DEFAULT '',
  minage smallint NOT NULL DEFAULT -1
) WITHOUT OIDS;

ALTER TABLE vnr_media     RENAME TO releases_media;
ALTER TABLE vnr_platforms RENAME TO releases_platforms;
ALTER TABLE vnr_producers RENAME TO releases_producers;
ALTER TABLE releases_media     RENAME vnrid TO rid;
ALTER TABLE releases_platforms RENAME vnrid TO rid;
ALTER TABLE releases_producers RENAME vnrid TO rid;
ALTER TABLE releases_media     ADD COLUMN tmp_upd smallint DEFAULT 0;
ALTER TABLE releases_platforms ADD COLUMN tmp_upd smallint DEFAULT 0;
ALTER TABLE releases_producers ADD COLUMN tmp_upd smallint DEFAULT 0;
ALTER TABLE releases_platforms DROP CONSTRAINT vnv_platforms_pkey;
ALTER TABLE releases_producers DROP CONSTRAINT vnv_companies_pkey;


CREATE OR REPLACE FUNCTION fill_releases() RETURNS void AS $$
DECLARE
  r RECORD;
  i integer;
  t integer;
  ti text;
  tg text;
BEGIN
  FOR r IN SELECT * FROM vnr_old ORDER BY added LOOP
    INSERT INTO changes ("type", added, requester, comments)
      VALUES (1, r.added, 1, 'Automated import from VNDB 1.8');

    SELECT currval('changes_id_seq') INTO i;

    -- swap titles
    ti := r.romaji;
    tg := r.title;
    IF ti = '' THEN
      ti := r.title;
      tg := '';
    END IF;
    -- determine type
    t := 0;
    IF r.relation ILIKE '%trial%' OR r.relation ILIKE '%demo%' THEN
      t := 2;
    END IF;

    INSERT INTO releases_rev (id, rid, title, original, relation, language, website, released, notes, minage, "type")
      VALUES (i, r.id, ti, tg, r.relation, r.language, r.website, r.released, r.notes, r.minage, t);

    INSERT INTO releases (id, latest, vid)
      VALUES (r.id, i, r.vid);
  
    UPDATE releases_media     SET rid = i, tmp_upd = 1 WHERE rid = r.id AND tmp_upd = 0;
    UPDATE releases_producers SET rid = i, tmp_upd = 1 WHERE rid = r.id AND tmp_upd = 0;
    UPDATE releases_platforms SET rid = i, tmp_upd = 1 WHERE rid = r.id AND tmp_upd = 0;
  END LOOP;
END;
$$ LANGUAGE plpgsql;
SELECT fill_releases();
DROP FUNCTION fill_releases();

ALTER TABLE releases_media     DROP COLUMN tmp_upd;
ALTER TABLE releases_producers DROP COLUMN tmp_upd;
ALTER TABLE releases_platforms DROP COLUMN tmp_upd;
ALTER TABLE releases_producers ADD CONSTRAINT releases_producers_pkey PRIMARY KEY (pid, rid);
ALTER TABLE releases_media     ADD CONSTRAINT releases_media_pkey     PRIMARY KEY (rid, medium, qty);
ALTER TABLE releases_platforms ADD CONSTRAINT releases_platforms_pkey PRIMARY KEY (rid, platform);





--                P r o d u c e r s


ALTER TABLE producers RENAME TO producers_old;

CREATE TABLE producers (
  id integer NOT NULL DEFAULT get_new_id('producers') PRIMARY KEY,
  latest integer NOT NULL DEFAULT 0,
  locked smallint NOT NULL DEFAULT 0
) WITHOUT OIDS;

CREATE TABLE producers_rev (
  id integer NOT NULL PRIMARY KEY,
  pid integer NOT NULL DEFAULT 0,
  "type" character(2) NOT NULL DEFAULT 'co',
  name varchar(200) NOT NULL DEFAULT '',
  original varchar(200) NOT NULL DEFAULT '',
  website varchar(250) NOT NULL DEFAULT '',
  lang varchar NOT NULL DEFAULT 'ja',
  "desc" text NOT NULL DEFAULT ''
) WITHOUT OIDS;

CREATE OR REPLACE FUNCTION fill_producers() RETURNS void AS $$
DECLARE
  r RECORD;
  i integer;
BEGIN
  FOR r IN SELECT * FROM producers_old ORDER BY added LOOP
    INSERT INTO changes ("type", added, requester, comments)
      VALUES (2, r.added, 1, 'Automated import from VNDB 1.8');

    SELECT currval('changes_id_seq') INTO i;

    INSERT INTO producers_rev (id, pid, "type", name, original, website, lang, "desc")
      VALUES (i, r.id, r.type, r.name, r.original, r.website, r.lang, r.desc);

    INSERT INTO producers (id, latest, locked)
      VALUES (r.id, i, 0);
  END LOOP;
END;
$$ LANGUAGE plpgsql;
SELECT fill_producers();
DROP FUNCTION fill_producers();







DROP TABLE vn_old;
DROP TABLE vn_relations_old;
DROP TABLE vn_categories;
DROP TABLE vnr_old;
DROP TABLE producers_old;
DROP FUNCTION get_new_id();


UPDATE users SET rank = rank+1;
ALTER TABLE users ALTER COLUMN rank SET DEFAULT 2;





--                     F u n c t i o n s


-- ids = empty string or comma-seperated list of id's (as a string)
CREATE OR REPLACE FUNCTION update_prev(tbl text, ids text) RETURNS void AS $$
DECLARE
  r RECORD;
  r2 RECORD;
  i integer;
  t text;
  e text;
BEGIN
  SELECT INTO t SUBSTRING(tbl, 0, 1);
  e := '';
  IF ids <> '' THEN
    e := ' WHERE id IN('||ids||')';
  END IF;
  FOR r IN EXECUTE 'SELECT id FROM '||tbl||e LOOP
    i := 0;
    FOR r2 IN EXECUTE 'SELECT id FROM '||tbl||'_rev WHERE '||t||'id = '||r.id||' ORDER BY id ASC' LOOP
      UPDATE changes SET prev = i WHERE id = r2.id;
      i := r2.id;
    END LOOP;
  END LOOP;
END;
$$ LANGUAGE plpgsql;

-- /what/ bitflags: released, languages, votes
-- Typical yorhel-code: ugly...
CREATE OR REPLACE FUNCTION update_vncache(what integer, id integer) RETURNS void AS $$
DECLARE
  s text := '';
  w text := '';
BEGIN
  IF what < 1 OR what > 7 THEN
    RETURN;
  END IF;
  IF what & 1 = 1 THEN
    s := 'c_released = COALESCE((SELECT
      SUBSTRING(COALESCE(MIN(rr1.released), ''0000-00'') from 1 for 7)
      FROM releases r1
      JOIN releases_rev rr1 ON r1.latest = rr1.id
      WHERE r1.vid = vn.id
        AND rr1.type <> 2
      GROUP BY r1.vid
    ), ''0000-00'')';
  END IF;
  IF what & 2 = 2 THEN
    IF s <> '' THEN
      s := s||', ';
    END IF;
    s := s||'c_languages = COALESCE(ARRAY_TO_STRING(ARRAY(
      SELECT language
      FROM releases r2
      JOIN releases_rev rr2 ON r2.latest = rr2.id
      WHERE r2.vid = vn.id
        AND rr2.type <> 2
      GROUP BY rr2.language
      ORDER BY rr2.language
    ), ''/''), '''')';
  END IF;
  IF what & 4 = 4 THEN
    IF s <> '' THEN
      s := s||', ';
    END IF;
    s := s||'c_votes = COALESCE((SELECT
      TO_CHAR(CASE WHEN COUNT(uid) < 2 THEN 0 ELSE AVG(vote) END,  ''FM00D0'')||''|''||TO_CHAR(COUNT(uid), ''FM0000'')
      FROM votes
      WHERE vid = vn.id
      GROUP BY vid
    ), ''00.0|0000'')';
  END IF;
  IF id > 0 THEN
    w := ' WHERE id = '||id;
  END IF;
  EXECUTE 'UPDATE vn SET '||s||w;
END;
$$ LANGUAGE plpgsql;




