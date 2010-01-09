
-- no more bayesian rating for VN list on tag pages, just plain averages
DROP TABLE tags_vn_bayesian;
CREATE TABLE tags_vn_inherit (
  tag integer NOT NULL,
  vid integer NOT NULL,
  users integer NOT NULL,
  rating real NOT NULL,
  spoiler smallint NOT NULL
);


-- remove unused functions
DROP FUNCTION tag_vn_childs() CASCADE;
DROP FUNCTION tag_tree(integer, integer, boolean);
DROP TYPE tag_tree_item;


-- remove changes.causedby and give the affected changes to Multi
UPDATE changes SET requester = 1 WHERE causedby IS NOT NULL;
ALTER TABLE changes DROP COLUMN causedby;
UPDATE users SET
  c_changes = COALESCE((
    SELECT COUNT(id)
    FROM changes
    WHERE requester = users.id
    GROUP BY requester
  ), 0);


-- set default on releases_rev.released, required for the revision insertion abstraction
ALTER TABLE releases_rev ALTER COLUMN released SET DEFAULT 0;


-- type used for the revision inserting functions
CREATE TYPE edit_rettype      AS (iid integer, cid integer, rev integer);


-- import the new and updated functions
\i util/sql/func.sql


-- call update_vncache() when a release is added, edited, hidden or unhidden
CREATE TRIGGER release_vncache_update AFTER UPDATE ON releases FOR EACH ROW EXECUTE PROCEDURE release_vncache_update();


-- improved relgraph notify triggers
DROP TRIGGER vn_relgraph_notify ON vn;
CREATE TRIGGER vn_relgraph_notify AFTER UPDATE ON vn FOR EACH ROW EXECUTE PROCEDURE vn_relgraph_notify();
DROP TRIGGER vn_relgraph_notify ON producers;
CREATE TRIGGER producer_relgraph_notify AFTER UPDATE ON producers FOR EACH ROW EXECUTE PROCEDURE producer_relgraph_notify();


-- more efficient version of tag_vn_calc()
SELECT tag_vn_calc();


-- regenerate the relation graphs so that they contain IDs for highlighting
UPDATE vn SET rgraph = NULL;
UPDATE producers SET rgraph = NULL;
DELETE FROM relgraphs;


