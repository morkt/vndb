
-- no more bayesian rating for VN list on tag pages, just plain averages
DROP TABLE tags_vn_bayesian;
CREATE TABLE tags_vn_inherit (
  tag integer NOT NULL,
  vid integer NOT NULL,
  users integer NOT NULL,
  rating real NOT NULL,
  spoiler smallint NOT NULL
);


-- more efficient version of tag_vn_calc()
CREATE OR REPLACE FUNCTION tag_vn_calc() RETURNS void AS $$
BEGIN
  DROP INDEX IF EXISTS tags_vn_inherit_tag_vid;
  TRUNCATE tags_vn_inherit;
  -- populate tags_vn_inherit
  INSERT INTO tags_vn_inherit
    -- all votes for all tags, including votes inherited by child tags
    -- (also includes meta tags, because they could have a normal tag as parent)
    WITH RECURSIVE tags_vn_all(lvl, tag, vid, uid, vote, spoiler, meta) AS (
        SELECT 15, tag, vid, uid, vote, spoiler, false
        FROM tags_vn
      UNION ALL
        SELECT lvl-1, tp.parent, ta.vid, ta.uid, ta.vote, ta.spoiler, t.meta
        FROM tags_vn_all ta
        JOIN tags_parents tp ON tp.tag = ta.tag
        JOIN tags t ON t.id = tp.parent
        WHERE t.state = 2
          AND ta.lvl > 0
    )
    -- grouped by (tag, vid)
    SELECT tag, vid, COUNT(uid) AS users, AVG(vote)::real AS rating,
           (CASE WHEN AVG(spoiler) < 0.7 THEN 0 WHEN AVG(spoiler) > 1.3 THEN 2 ELSE 1 END)::smallint AS spoiler
    FROM (
      -- grouped by (tag, vid, uid), so only one user votes on one parent tag per VN entry (also removing meta tags)
      SELECT tag, vid, uid, MAX(vote)::real, COALESCE(AVG(spoiler), 0)::real
      FROM tags_vn_all
      WHERE NOT meta
      GROUP BY tag, vid, uid
    ) AS t(tag, vid, uid, vote, spoiler)
    GROUP BY tag, vid
    HAVING AVG(vote) > 0;
  -- recreate index
  CREATE INDEX tags_vn_inherit_tag_vid ON tags_vn_inherit (tag, vid);
  -- and update the VN count in the tags table
  UPDATE tags SET c_vns = (SELECT COUNT(*) FROM tags_vn_inherit WHERE tag = id);
  RETURN;
END;
$$ LANGUAGE plpgsql;
SELECT tag_vn_calc();


-- remove unused functions
DROP FUNCTION tag_vn_childs() CASCADE;
DROP FUNCTION tag_tree(integer, integer, boolean);
DROP TYPE tag_tree_item;



-- improved relgraph notify triggers
DROP TRIGGER vn_relgraph_notify ON vn;
CREATE OR REPLACE FUNCTION vn_relgraph_notify() RETURNS trigger AS $$
BEGIN
  -- 1.
  IF NEW.rgraph IS DISTINCT FROM OLD.rgraph OR NEW.latest IS DISTINCT FROM OLD.latest THEN
    IF NEW.rgraph IS NULL AND EXISTS(SELECT 1 FROM vn_relations WHERE vid1 = NEW.latest) THEN
      NOTIFY relgraph;
    END IF;
  END IF;
  IF NEW.rgraph IS NOT NULL THEN
    IF
      -- 2.
         OLD.c_released  IS DISTINCT FROM NEW.c_released
      OR OLD.c_languages IS DISTINCT FROM NEW.c_languages
      OR OLD.latest <> 0 AND OLD.latest IS DISTINCT FROM NEW.latest AND (
        -- 3.
           EXISTS(SELECT 1 FROM vn_rev v1, vn_rev v2 WHERE v2.title <> v1.title AND v1.id = OLD.latest AND v2.id = NEW.latest)
        -- 4. (not-really-readable method of comparing two query results)
        OR EXISTS(SELECT vid2, relation FROM vn_relations WHERE vid1 = OLD.latest EXCEPT SELECT vid2, relation FROM vn_relations WHERE vid1 = NEW.latest)
        OR (SELECT COUNT(*) FROM vn_relations WHERE vid1 = OLD.latest) <> (SELECT COUNT(*) FROM vn_relations WHERE vid1 = NEW.latest)
      )
    THEN
      UPDATE vn SET rgraph = NULL WHERE id = NEW.id;
    END IF;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER vn_relgraph_notify AFTER UPDATE ON vn FOR EACH ROW EXECUTE PROCEDURE vn_relgraph_notify();


DROP TRIGGER vn_relgraph_notify ON producers;
CREATE OR REPLACE FUNCTION producer_relgraph_notify() RETURNS trigger AS $$
BEGIN
  -- 1.
  IF NEW.rgraph IS DISTINCT FROM OLD.rgraph OR NEW.latest IS DISTINCT FROM OLD.latest THEN
    IF NEW.rgraph IS NULL AND EXISTS(SELECT 1 FROM producers_relations WHERE pid1 = NEW.latest) THEN
      NOTIFY relgraph;
    END IF;
  END IF;
  IF NEW.rgraph IS NOT NULL THEN
    -- 2.
    IF OLD.latest <> 0 AND OLD.latest IS DISTINCT FROM NEW.latest AND (
        -- 3.
           EXISTS(SELECT 1 FROM producers_rev p1, producers_rev p2 WHERE (p2.name <> p1.name OR p2.type <> p1.type OR p2.lang <> p1.lang) AND p1.id = OLD.latest AND p2.id = NEW.latest)
        -- 4. (not-really-readable method of comparing two query results)
        OR EXISTS(SELECT p1.pid2, p1.relation FROM producers_relations p1 WHERE p1.pid1 = OLD.latest EXCEPT SELECT p2.pid2, p2.relation FROM producers_relations p2 WHERE p2.pid1 = NEW.latest)
        OR (SELECT COUNT(*) FROM producers_relations WHERE pid1 = OLD.latest) <> (SELECT COUNT(*) FROM producers_relations WHERE pid1 = NEW.latest)
      )
    THEN
      UPDATE producers SET rgraph = NULL WHERE id = NEW.id;
    END IF;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER producer_relgraph_notify AFTER UPDATE ON producers FOR EACH ROW EXECUTE PROCEDURE producer_relgraph_notify();


-- don't allow vid=0 for update_vncache
CREATE OR REPLACE FUNCTION update_vncache(integer) RETURNS void AS $$
  UPDATE vn SET
    c_released = COALESCE((SELECT
      MIN(rr1.released)
      FROM releases_rev rr1
      JOIN releases r1 ON rr1.id = r1.latest
      JOIN releases_vn rv1 ON rr1.id = rv1.rid
      WHERE rv1.vid = vn.id
      AND rr1.type <> 'trial'
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
      AND rr2.type <> 'trial'
      AND rr2.released <= TO_CHAR('today'::timestamp, 'YYYYMMDD')::integer
      AND r2.hidden = FALSE
      GROUP BY rl2.lang
      ORDER BY rl2.lang
    ), '/'), ''),
    c_platforms = COALESCE(ARRAY_TO_STRING(ARRAY(
      SELECT rp3.platform
      FROM releases_platforms rp3
      JOIN releases_rev rr3 ON rp3.rid = rr3.id
      JOIN releases r3 ON rp3.rid = r3.latest
      JOIN releases_vn rv3 ON rp3.rid = rv3.rid
      WHERE rv3.vid = vn.id
      AND rr3.type <> 'trial'
      AND rr3.released <= TO_CHAR('today'::timestamp, 'YYYYMMDD')::integer
      AND r3.hidden = FALSE
      GROUP BY rp3.platform
      ORDER BY rp3.platform
    ), '/'), '')
  WHERE id = $1;
$$ LANGUAGE sql;


-- call update_vncache() when a release is added, edited, hidden or unhidden
CREATE OR REPLACE FUNCTION release_vncache_update() RETURNS trigger AS $$
BEGIN
  IF OLD.latest IS DISTINCT FROM NEW.latest OR OLD.hidden IS DISTINCT FROM NEW.hidden THEN
    PERFORM update_vncache(vid) FROM (
      SELECT DISTINCT vid FROM releases_vn WHERE rid = OLD.latest OR rid = NEW.latest
    ) AS v(vid);
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER release_vncache_update AFTER UPDATE ON releases FOR EACH ROW EXECUTE PROCEDURE release_vncache_update();


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

