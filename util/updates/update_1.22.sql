
-- store relation graph image maps in the database
CREATE TABLE relgraph (
  id SERIAL NOT NULL PRIMARY KEY,
  cmap text NOT NULL DEFAULT ''
) WITHOUT OIDS;

DROP SEQUENCE relgraph_seq;
ALTER TABLE vn ALTER COLUMN rgraph DROP NOT NULL;
ALTER TABLE vn ALTER COLUMN rgraph SET DEFAULT NULL;
UPDATE vn SET rgraph = NULL;
ALTER TABLE vn ADD FOREIGN KEY (rgraph) REFERENCES relgraph (id) DEFERRABLE INITIALLY DEFERRED;


-- add foreign table constraint to changes.causedby
ALTER TABLE changes ALTER COLUMN causedby DROP NOT NULL;
ALTER TABLE changes ALTER COLUMN causedby SET DEFAULT NULL;
UPDATE changes c SET causedby = NULL
  WHERE causedby = 0
    -- yup, there are some problems caused by deleted revisions in older versions of the site
     OR NOT EXISTS(SELECT 1 FROM changes WHERE c.causedby = id);
ALTER TABLE changes ADD FOREIGN KEY (causedby) REFERENCES changes (id) DEFERRABLE INITIALLY DEFERRED;


-- another foreign key constraint: (threads.id, threads.count) -> (threads_posts.tid, threads_posts.num)
-- threads_posts converted to smallint as well
ALTER TABLE threads_posts ALTER COLUMN num TYPE smallint;
ALTER TABLE threads ADD FOREIGN KEY (id, count) REFERENCES threads_posts (tid, num) DEFERRABLE INITIALLY DEFERRED;


-- screenshots now have a relation with releases
ALTER TABLE vn_screenshots ADD COLUMN rid integer DEFAULT NULL REFERENCES releases (id) DEFERRABLE INITIALLY DEFERRED;


