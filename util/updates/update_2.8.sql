
-- !BEFORE! running this SQL file, make sure to kill Multi,
-- After running this SQL file, also make sure to do a:
--  $ rm -r static/rg/
-- And start multi again

-- VN Relation graphs are stored in the database as SVG - no cmaps and .png anymore
UPDATE vn SET rgraph = NULL;
ALTER TABLE vn DROP CONSTRAINT vn_rgraph_fkey;
DROP TABLE relgraph;
CREATE TABLE relgraphs (
  id SERIAL PRIMARY KEY,
  svg xml NOT NULL
);
ALTER TABLE vn ADD FOREIGN KEY (rgraph) REFERENCES relgraphs (id);


-- VN relations stored as enum
CREATE TYPE vn_relation AS ENUM ('seq', 'preq', 'set', 'alt', 'char', 'side', 'par', 'ser', 'fan', 'orig');
ALTER TABLE vn_relations ALTER COLUMN relation DROP DEFAULT;
ALTER TABLE vn_relations ALTER COLUMN relation TYPE vn_relation USING
  CASE
    WHEN relation = 0 THEN 'seq'::vn_relation
    WHEN relation = 1 THEN 'preq'
    WHEN relation = 2 THEN 'set'
    WHEN relation = 3 THEN 'alt'
    WHEN relation = 4 THEN 'char'
    WHEN relation = 5 THEN 'side'
    WHEN relation = 6 THEN 'par'
    WHEN relation = 7 THEN 'ser'
    WHEN relation = 8 THEN 'fan'
    ELSE 'orig'
  END;


-- producer relations
CREATE TYPE producer_relation AS ENUM ('old', 'new', 'par', 'sub', 'imp', 'ipa');
CREATE TABLE producers_relations (
  pid1 integer NOT NULL REFERENCES producers_rev (id),
  pid2 integer NOT NULL REFERENCES producers (id),
  relation producer_relation NOT NULL,
  PRIMARY KEY(pid1, pid2)
);


-- Anime types stored as enum
CREATE TYPE anime_type AS ENUM ('tv', 'ova', 'mov', 'oth', 'web', 'spe', 'mv');
ALTER TABLE anime ALTER COLUMN type TYPE anime_type USING
  CASE
    WHEN type = 0 THEN 'tv'::anime_type
    WHEN type = 1 THEN 'ova'
    WHEN type = 2 THEN 'mov'
    WHEN type = 3 THEN 'oth'
    WHEN type = 4 THEN 'web'
    WHEN type = 5 THEN 'spe'
    WHEN type = 6 THEN 'mv'
    ELSE NULL
  END;


-- Release media stored as enum
CREATE TYPE medium AS ENUM ('cd', 'dvd', 'gdr', 'blr', 'flp', 'mrt', 'mem', 'umd', 'nod', 'in', 'otc');
ALTER TABLE releases_media ALTER COLUMN medium DROP DEFAULT;
ALTER TABLE releases_media ALTER COLUMN medium TYPE medium USING TRIM(both ' ' from medium)::medium;


-- Differentiate between publishers and developers
ALTER TABLE releases_producers ADD COLUMN developer boolean NOT NULL DEFAULT FALSE;
ALTER TABLE releases_producers ADD COLUMN publisher boolean NOT NULL DEFAULT TRUE;
ALTER TABLE releases_producers ADD CHECK(developer OR publisher);


-- Keep track of last read post for PMs
ALTER TABLE threads_boards ADD COLUMN lastread smallint;


-- changes.type stored as enum
CREATE TYPE dbentry_type AS ENUM ('v', 'r', 'p');
ALTER TABLE changes ALTER COLUMN type DROP DEFAULT;
ALTER TABLE changes ALTER COLUMN type TYPE dbentry_type USING
  CASE
    WHEN type = 0 THEN 'v'::dbentry_type
    WHEN type = 1 THEN 'r'
    WHEN type = 2 THEN 'p'
    ELSE NULL -- not allowed to happen, otherwise FIX YOUR DATABASE!
  END;


-- releases_rev.type stored as enum
CREATE TYPE release_type AS ENUM ('complete', 'partial', 'trial');
ALTER TABLE releases_rev ALTER COLUMN type DROP DEFAULT;
ALTER TABLE releases_rev ALTER COLUMN type TYPE release_type USING
  CASE
    WHEN type = 0 THEN 'complete'::release_type
    WHEN type = 1 THEN 'partial'
    WHEN type = 2 THEN 'trial'
    ELSE NULL
  END;
ALTER TABLE releases_rev ALTER COLUMN type SET DEFAULT 'complete';

CREATE OR REPLACE FUNCTION update_vncache(id integer) RETURNS void AS $$
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
      AND rr1.type <> ''trial''
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
      AND rr2.type <> ''trial''
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
      AND rr3.type <> ''trial''
      AND rr3.released <= TO_CHAR(''today''::timestamp, ''YYYYMMDD'')::integer
      AND r3.hidden = FALSE
      GROUP BY rp3.platform
      ORDER BY rp3.platform
    ), ''/''), '''')
  '||w;
END;
$$ LANGUAGE plpgsql;



-- fix calculation of the tags_vn_bayesian.spoiler column

CREATE OR REPLACE FUNCTION tag_vn_calc() RETURNS void AS $$
BEGIN
  -- all votes for all tags
  CREATE OR REPLACE TEMPORARY VIEW tags_vn_all AS
    SELECT * FROM tags_vn UNION SELECT * FROM tag_vn_childs();
  -- grouped by (tag, vid, uid), so only one user votes on one parent tag per VN entry
  CREATE OR REPLACE TEMPORARY VIEW tags_vn_grouped AS
    SELECT tag, vid, uid, MAX(vote)::real AS vote, AVG(spoiler)::real AS spoiler
    FROM tags_vn_all GROUP BY tag, vid, uid;
  -- grouped by (tag, vid) and serialized into a table
  DROP INDEX IF EXISTS tags_vn_bayesian_tag;
  TRUNCATE tags_vn_bayesian;
  INSERT INTO tags_vn_bayesian
      SELECT tag, vid, COUNT(uid) AS users, AVG(vote)::real AS rating,
          (CASE WHEN AVG(spoiler) < 0.7 THEN 0 WHEN AVG(spoiler) > 1.3 THEN 2 ELSE 1 END)::smallint AS spoiler
        FROM tags_vn_grouped
    GROUP BY tag, vid
      HAVING AVG(vote) > 0;
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

