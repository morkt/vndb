
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


-- add foreign table constraint to changes.causedby
ALTER TABLE changes ALTER COLUMN causedby DROP NOT NULL;
ALTER TABLE changes ALTER COLUMN causedby SET DEFAULT NULL;
UPDATE changes c SET causedby = NULL
  WHERE causedby = 0
    -- yup, there are some problems caused by deleted revisions in older versions of the site
     OR NOT EXISTS(SELECT 1 FROM changes WHERE c.causedby = id);
ALTER TABLE changes ADD FOREIGN KEY (causedby) REFERENCES changes (id) DEFERRABLE INITIALLY DEFERRED;

