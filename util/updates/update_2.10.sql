
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

