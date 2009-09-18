

-- add a flag to users whose votes we want to ignore
ALTER TABLE users ADD COLUMN ign_votes boolean NOT NULL DEFAULT FALSE;

CREATE OR REPLACE FUNCTION update_vnpopularity() RETURNS void AS $$
BEGIN
  CREATE OR REPLACE TEMP VIEW tmp_pop1 (uid, vid, rank) AS
      SELECT v.uid, v.vid, sqrt(count(*))::real
        FROM votes v
--        JOIN users u ON u.id = v.uid AND NOT u.ign_votes  -- slow
        JOIN votes v2 ON v.uid = v2.uid AND v2.vote < v.vote
        WHERE v.uid NOT IN(SELECT id FROM users WHERE ign_votes) -- faster
    GROUP BY v.vid, v.uid;
  CREATE OR REPLACE TEMP VIEW tmp_pop2 (vid, win) AS
    SELECT vid, sum(rank) FROM tmp_pop1 GROUP BY vid;
  UPDATE vn SET c_popularity = COALESCE((SELECT win/(SELECT MAX(win) FROM tmp_pop2) FROM tmp_pop2 WHERE vid = id), 0);
  RETURN;
END;
$$ LANGUAGE plpgsql;



-- VN relations cleanup

UPDATE vn_relations SET relation = relation + 50 WHERE relation IN(8, 9, 10);
UPDATE vn_relations SET relation = relation - 1  WHERE relation > 3 AND relation < 50;
UPDATE vn_relations SET relation = 7 WHERE relation = 60;
DELETE FROM vn_relations WHERE relation > 50;

-- Be sure to execute the following query after restarting Multi, to regenerate the relation graphs:
--   UPDATE vn SET rgraph = NULL;





-- set freeware flag for all trials with internet download as medium

CREATE FUNCTION tmp_edit_release(iid integer) RETURNS void AS $$
DECLARE
  cid integer;
  oid integer;
BEGIN
  SELECT INTO oid latest FROM releases WHERE id = iid;
  INSERT INTO changes (type, requester, ip, comments, rev)
    VALUES (1, 1, '0.0.0.0',
      E'Automated edit with the update to VNDB 2.7.\n\nThis release is a downloadable trial, freeware flag is assumed.',
      (SELECT rev+1 FROM changes WHERE id = oid))
    RETURNING id INTO cid;
  INSERT INTO releases_rev (id, rid, title, original, type, website, released, notes,
      minage, gtin, patch, catalog, resolution, voiced, freeware, doujin, ani_story, ani_ero)
    SELECT cid, rid, title, original, type, website, released, notes,
        minage, gtin, patch, catalog, resolution, voiced, true, doujin, ani_story, ani_ero
      FROM releases_rev WHERE id = oid;
  INSERT INTO releases_media (rid, medium, qty) SELECT cid, medium, qty FROM releases_media WHERE rid = oid;
  INSERT INTO releases_platforms (rid, platform) SELECT cid, platform FROM releases_platforms WHERE rid = oid;
  INSERT INTO releases_producers (rid, pid) SELECT cid, pid FROM releases_producers WHERE rid = oid;
  INSERT INTO releases_lang (rid, lang) SELECT cid, lang FROM releases_lang WHERE rid = oid;
  INSERT INTO releases_vn (rid, vid) SELECT cid, vid FROM releases_vn WHERE rid = oid;
  UPDATE releases SET latest = cid WHERE id = iid;
END;
$$ LANGUAGE plpgsql;

SELECT tmp_edit_release(r.id)
  FROM releases r
  JOIN releases_rev rr ON rr.id = r.latest
 WHERE r.hidden = FALSE
   AND rr.type = 2
   AND NOT rr.freeware
   AND EXISTS(SELECT 1 FROM releases_media rm WHERE rm.medium = 'in ' AND rm.rid = rr.id)
 ORDER BY r.id;

DROP FUNCTION tmp_edit_release(integer);



-- Really don't consider VNs with AVG(vote) < 0 on tag pages
CREATE OR REPLACE FUNCTION tag_vn_calc() RETURNS void AS $$
BEGIN
  -- all votes for all tags
  CREATE OR REPLACE TEMPORARY VIEW tags_vn_all AS
    SELECT * FROM tags_vn UNION SELECT * FROM tag_vn_childs();
  -- grouped by (tag, vid, uid), so only one user votes on one parent tag per VN entry
  CREATE OR REPLACE TEMPORARY VIEW tags_vn_grouped AS
    SELECT tag, vid, uid, MAX(vote)::real AS vote, COALESCE(AVG(spoiler), 0)::real AS spoiler
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

