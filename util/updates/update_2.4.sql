

-- don't consider vns with vote < 0 on tag pages

CREATE OR REPLACE FUNCTION tag_vn_calc() RETURNS void AS $$
BEGIN
  -- all votes for all tags
  CREATE OR REPLACE TEMPORARY VIEW tags_vn_all AS
    SELECT * FROM tags_vn UNION SELECT * FROM tag_vn_childs();
  -- grouped by (tag, vid, uid), so only one user votes on one parent tag per VN entry
  CREATE OR REPLACE TEMPORARY VIEW tags_vn_grouped AS
    SELECT tag, vid, uid, MAX(vote)::real AS vote, COALESCE(AVG(spoiler), 0)::real AS spoiler
    FROM tags_vn_all WHERE vote > 0 GROUP BY tag, vid, uid;
  -- grouped by (tag, vid) and serialized into a table
  DROP INDEX IF EXISTS tags_vn_bayesian_tag;
  TRUNCATE tags_vn_bayesian;
  INSERT INTO tags_vn_bayesian
      SELECT tag, vid, COUNT(uid) AS users, AVG(vote)::real AS rating,
          (CASE WHEN AVG(spoiler) < 0.7 THEN 0 WHEN AVG(spoiler) > 1.3 THEN 2 ELSE 1 END)::smallint AS spoiler
        FROM tags_vn_grouped
    GROUP BY tag, vid;
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




-- resolution field
ALTER TABLE releases_rev ADD COLUMN resolution smallint NOT NULL DEFAULT 0;
-- voiced
ALTER TABLE releases_rev ADD COLUMN voiced smallint NOT NULL DEFAULT 0;
-- freeware / doujin
ALTER TABLE releases_rev ADD COLUMN freeware boolean NOT NULL DEFAULT FALSE;
ALTER TABLE releases_rev ADD COLUMN doujin boolean NOT NULL DEFAULT FALSE;
-- animated
ALTER TABLE releases_rev ADD COLUMN ani_story smallint NOT NULL DEFAULT 0;
ALTER TABLE releases_rev ADD COLUMN ani_ero smallint NOT NULL DEFAULT 0;




-- set doujin flag for all non-patch releases which have an "amateur group" as producer
-- set freeware flag for all patches
-- (the revision system makes this slightly more complex than doing a simple UPDATE)

CREATE FUNCTION tmp_edit_release(iid integer) RETURNS void AS $$
DECLARE
  cid integer;
  oid integer;
  fw boolean;
  do boolean;
  comm text;
BEGIN
  SELECT INTO oid latest FROM releases WHERE id = iid;
  SELECT INTO fw EXISTS(SELECT 1 FROM releases_rev WHERE id = oid AND patch);
  SELECT INTO do EXISTS(SELECT 1 FROM releases_producers rp JOIN releases_rev rr ON rp.rid = rr.id
    JOIN producers p ON p.id = rp.pid JOIN producers_rev pr ON pr.id = p.latest WHERE rp.rid = oid AND pr.type = 'ng' AND rr.patch = false);
  IF NOT do AND NOT fw THEN
    RETURN;
  END IF;
  comm := E'Automated edit with the update to VNDB 2.4.\n\n';
  IF fw THEN
    comm := comm || E'This release is a patch, freeware flag is assumed\n';
  END IF;
  IF do THEN
    comm := comm || E'This release has an \'amateur group\' as producer and as such is likely to be a doujin release.\n';
  END IF;
  comm := comm || E'Feel free to revert if this assumption happens to be incorrect for this entry.';
  INSERT INTO changes (type, requester, ip, comments, rev)
    VALUES (1, 1, '0.0.0.0', comm, (SELECT rev+1 FROM changes WHERE id = oid))
    RETURNING id INTO cid;
  INSERT INTO releases_media (rid, medium, qty) SELECT cid, medium, qty FROM releases_media WHERE rid = oid;
  INSERT INTO releases_platforms (rid, platform) SELECT cid, platform FROM releases_platforms WHERE rid = oid;
  INSERT INTO releases_producers (rid, pid) SELECT cid, pid FROM releases_producers WHERE rid = oid;
  INSERT INTO releases_rev (id, rid, title, original, type, language, website, released, notes,
      minage, gtin, patch, catalog, resolution, voiced, freeware, doujin, ani_story, ani_ero)
    SELECT cid, rid, title, original, type, language, website, released, notes,
        minage, gtin, patch, catalog, resolution, voiced, fw, do, ani_story, ani_ero
      FROM releases_rev WHERE id = oid;
  INSERT INTO releases_vn (rid, vid) SELECT cid, vid FROM releases_vn WHERE rid = oid;
  UPDATE releases SET latest = cid WHERE id = iid;
END;
$$ LANGUAGE plpgsql;

-- this can be done a lot more efficiently, but this method is just easier :-)
SELECT tmp_edit_release(id) FROM releases WHERE hidden = FALSE;

DROP FUNCTION tmp_edit_release(integer);


