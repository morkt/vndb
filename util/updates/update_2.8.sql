
-- !BEFORE! running this SQL file, make sure to kill Multi,
-- After running this SQL file, also make sure to do a:
--  $ rm -r static/rg/
-- And start multi again

-- VN Relation graphs are stored in the database as SVG - no cmaps and .png anymore
UPDATE vn SET rgraph = NULL;
ALTER TABLE vn DROP CONSTRAINT vn_rgraph_fkey;
DROP TABLE relgraph;
CREATE TABLE vn_graphs (
  id SERIAL PRIMARY KEY,
  svg xml NOT NULL
);
ALTER TABLE vn ADD FOREIGN KEY (rgraph) REFERENCES vn_graphs (id);


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


