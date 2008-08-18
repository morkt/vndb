
-- store relation graph image maps in the database
CREATE TABLE relgraph (
  id SERIAL NOT NULL PRIMARY KEY,
  cmap text NOT NULL DEFAULT ''
) WITHOUT OIDS;

SELECT SETVAL('relgraph_id_seq', NEXTVAL('relgraph_seq'));
DROP SEQUENCE relgraph_seq;

ALTER TABLE vn ALTER COLUMN rgraph DROP NOT NULL;
ALTER TABLE vn ALTER COLUMN rgraph SET DEFAULT NULL;
UPDATE vn SET rgraph = NULL WHERE rgraph = 0;

