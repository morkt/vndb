
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

