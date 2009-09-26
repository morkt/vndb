
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

