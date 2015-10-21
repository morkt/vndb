-- A small note on the function naming scheme:
--   edit_*      -> revision insertion abstraction functions
--   *_notify    -> functions issuing a PgSQL NOTIFY statement
--   notify_*    -> functions creating entries in the notifications table
--   update_*    -> functions to update a cache
--   *_update    ^  (I should probably rename these to
--   *_calc      ^   the update_* scheme for consistency)
-- I like to keep the nouns in functions singular, in contrast to the table
-- naming scheme where nouns are always plural. But I'm not very consistent
-- with that, either.


-- strip_bb_tags(text) - simple utility function to aid full-text searching
CREATE OR REPLACE FUNCTION strip_bb_tags(t text) RETURNS text AS $$
  SELECT regexp_replace(t, '\[(?:url=[^\]]+|/?(?:spoiler|quote|raw|code|url))\]', ' ', 'gi');
$$ LANGUAGE sql IMMUTABLE;


-- BUG: Since this isn't a full bbcode parser, [spoiler] tags inside [raw] or [code] are still considered spoilers.
CREATE OR REPLACE FUNCTION strip_spoilers(t text) RETURNS text AS $$
  -- The website doesn't require the [spoiler] tag to be closed, the outer replace catches that case.
  SELECT regexp_replace(regexp_replace(t, '\[spoiler\].*?\[/spoiler\]', ' ', 'ig'), '\[spoiler\].*', ' ', 'i');
$$ LANGUAGE sql IMMUTABLE;


-- update_vncache(id) - updates some c_* columns in the vn table
CREATE OR REPLACE FUNCTION update_vncache(integer) RETURNS void AS $$
  UPDATE vn SET
    c_released = COALESCE((
      SELECT MIN(r.released)
        FROM releases r
        JOIN releases_vn rv ON r.id = rv.id
       WHERE rv.vid = $1
         AND r.type <> 'trial'
         AND r.hidden = FALSE
         AND r.released <> 0
      GROUP BY rv.vid
    ), 0),
    c_olang = ARRAY(
      SELECT lang
        FROM releases_lang
       WHERE id = (
        SELECT r.id
          FROM releases_vn rv
          JOIN releases r ON rv.id = r.id
         WHERE r.released > 0
           AND NOT r.hidden
           AND rv.vid = $1
         ORDER BY r.released
         LIMIT 1
       )
    ),
    c_languages = ARRAY(
      SELECT rl.lang
        FROM releases_lang rl
        JOIN releases r ON r.id = rl.id
        JOIN releases_vn rv ON r.id = rv.id
       WHERE rv.vid = $1
         AND r.type <> 'trial'
         AND r.released <= TO_CHAR('today'::timestamp, 'YYYYMMDD')::integer
         AND r.hidden = FALSE
      GROUP BY rl.lang
      ORDER BY rl.lang
    ),
    c_platforms = ARRAY(
      SELECT rp.platform
        FROM releases_platforms rp
        JOIN releases r ON rp.id = r.id
        JOIN releases_vn rv ON rp.id = rv.id
       WHERE rv.vid = $1
        AND r.type <> 'trial'
        AND r.released <= TO_CHAR('today'::timestamp, 'YYYYMMDD')::integer
        AND r.hidden = FALSE
      GROUP BY rp.platform
      ORDER BY rp.platform
    )
  WHERE id = $1;
$$ LANGUAGE sql;



-- recalculate vn.c_popularity
CREATE OR REPLACE FUNCTION update_vnpopularity() RETURNS void AS $$
BEGIN
  -- the following queries only update rows with popularity > 0, so make sure to reset all rows first
  UPDATE vn SET c_popularity = NULL;
  CREATE OR REPLACE TEMP VIEW tmp_pop1 (uid, vid, rank) AS
      SELECT v.uid, v.vid, count(*)::real ^ 0.36788
        FROM votes v
        JOIN votes v2 ON v.uid = v2.uid AND v2.vote < v.vote
        JOIN users u ON u.id = v.uid AND NOT ign_votes
    GROUP BY v.vid, v.uid;
  CREATE OR REPLACE TEMP VIEW tmp_pop2 (vid, win) AS
    SELECT vid, sum(rank) FROM tmp_pop1 GROUP BY vid;
  UPDATE vn SET c_popularity = s1.win/(SELECT MAX(win) FROM tmp_pop2) FROM tmp_pop2 s1 WHERE s1.vid = vn.id;
  RETURN;
END;
$$ LANGUAGE plpgsql;



-- recalculate tags_vn_inherit
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
       WHERE NOT ignore
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
           (CASE WHEN AVG(spoiler) > 1.3 THEN 2 WHEN AVG(spoiler) > 0.7 THEN 1 ELSE 0 END)::smallint AS spoiler
    FROM (
      -- grouped by (tag, vid, uid), so only one user votes on one parent tag per VN entry (also removing meta tags)
      SELECT tag, vid, uid, MAX(vote)::real, AVG(spoiler)::real
      FROM tags_vn_all
      WHERE NOT meta
      GROUP BY tag, vid, uid
    ) AS t(tag, vid, uid, vote, spoiler)
    GROUP BY tag, vid
    HAVING AVG(vote) > 0;
  -- recreate index
  CREATE INDEX tags_vn_inherit_tag_vid ON tags_vn_inherit (tag, vid);
  -- and update the VN count in the tags table
  UPDATE tags SET c_items = (SELECT COUNT(*) FROM tags_vn_inherit WHERE tag = id);
  RETURN;
END;
$$ LANGUAGE plpgsql;



-- recalculate traits_chars
CREATE OR REPLACE FUNCTION traits_chars_calc() RETURNS void AS $$
BEGIN
  TRUNCATE traits_chars;
  INSERT INTO traits_chars (tid, cid, spoil)
    -- all char<->trait links of the latest revisions, including chars inherited from child traits
    -- (also includes meta traits, because they could have a normal trait as parent)
    WITH RECURSIVE traits_chars_all(lvl, tid, cid, spoiler, meta) AS (
        SELECT 15, tid, ct.id, spoil, false
        FROM chars_traits ct
        JOIN chars c ON c.id = ct.id
       WHERE NOT c.hidden
      UNION ALL
        SELECT lvl-1, tp.parent, tc.cid, tc.spoiler, t.meta
        FROM traits_chars_all tc
        JOIN traits_parents tp ON tp.trait = tc.tid
        JOIN traits t ON t.id = tp.parent
        WHERE t.state = 2
          AND tc.lvl > 0
    )
    -- now grouped by (tid, cid) and with meta traits filtered out
    SELECT tid, cid, (CASE WHEN AVG(spoiler) > 1.3 THEN 2 WHEN AVG(spoiler) > 0.7 THEN 1 ELSE 0 END)::smallint AS spoiler
    FROM traits_chars_all
    WHERE NOT meta
    GROUP BY tid, cid;
  -- and update the VN count in the tags table
  UPDATE traits SET c_items = (SELECT COUNT(*) FROM traits_chars WHERE tid = id);
  RETURN;
END;
$$ LANGUAGE plpgsql;






----------------------------------------------------------
--           revision insertion abstraction             --
----------------------------------------------------------

-- The two functions below are utility functions used by the item-specific functions in editfunc.sql

-- create temporary table for generic revision info, and returns the chid of the revision being edited (or NULL).
CREATE OR REPLACE FUNCTION edit_revtable(xtype dbentry_type, xitemid integer, xrev integer) RETURNS integer AS $$
DECLARE
  ret integer;
  x record;
BEGIN
  BEGIN
    CREATE TEMPORARY TABLE edit_revision (
      type dbentry_type NOT NULL,
      itemid integer,
      requester integer,
      ip inet,
      comments text,
      ihid boolean,
      ilock boolean
    );
  EXCEPTION WHEN duplicate_table THEN
    TRUNCATE edit_revision;
  END;
  SELECT INTO x id, ihid, ilock FROM changes c WHERE type = xtype AND itemid = xitemid AND rev = xrev;
  INSERT INTO edit_revision (type, itemid, ihid, ilock) VALUES (xtype, xitemid, COALESCE(x.ihid, FALSE), COALESCE(x.ilock, FALSE));
  RETURN x.id;
END;
$$ LANGUAGE plpgsql;



CREATE OR REPLACE FUNCTION edit_commit() RETURNS edit_rettype AS $$
DECLARE
  ret edit_rettype;
  xtype dbentry_type;
BEGIN
  SELECT type INTO xtype FROM edit_revision;
  SELECT itemid INTO ret.itemid FROM edit_revision;
  -- figure out revision number
  SELECT MAX(rev)+1 INTO ret.rev FROM changes WHERE type = xtype AND itemid = ret.itemid;
  SELECT COALESCE(ret.rev, 1) INTO ret.rev;
  -- insert DB item
  IF ret.itemid IS NULL THEN
    CASE xtype
      WHEN 'v' THEN INSERT INTO vn        DEFAULT VALUES RETURNING id INTO ret.itemid;
      WHEN 'r' THEN INSERT INTO releases  DEFAULT VALUES RETURNING id INTO ret.itemid;
      WHEN 'p' THEN INSERT INTO producers DEFAULT VALUES RETURNING id INTO ret.itemid;
      WHEN 'c' THEN INSERT INTO chars     DEFAULT VALUES RETURNING id INTO ret.itemid;
      WHEN 's' THEN INSERT INTO staff     DEFAULT VALUES RETURNING id INTO ret.itemid;
    END CASE;
  END IF;
  -- insert change
  INSERT INTO changes (type, itemid, rev, requester, ip, comments, ihid, ilock)
    SELECT type, ret.itemid, ret.rev, requester, ip, comments, ihid, ilock FROM edit_revision RETURNING id INTO ret.chid;
  RETURN ret;
END;
$$ LANGUAGE plpgsql;



-- Check for stuff to be done when an item has been changed
CREATE OR REPLACE FUNCTION edit_committed(xtype dbentry_type, xedit edit_rettype) RETURNS void AS $$
DECLARE
  xoldchid integer;
BEGIN
  SELECT id INTO xoldchid FROM changes WHERE type = xtype AND itemid = xedit.itemid AND rev = xedit.rev-1;

  -- Set producers.rgraph to NULL and notify when:
  -- 1. There's a new producer entry with some relations
  -- 2. The producer name/type/language has changed
  -- 3. The producer relations have been changed
  IF xtype = 'p' THEN
    IF -- 1.
         (xoldchid IS NULL AND EXISTS(SELECT 1 FROM producers_relations_hist WHERE chid = xedit.chid))
      OR (xoldchid IS NOT NULL AND (
        -- 2.
           EXISTS(SELECT 1 FROM producers_hist p1, producers_hist p2 WHERE (p2.name <> p1.name OR p2.type <> p1.type OR p2.lang <> p1.lang) AND p1.chid = xoldchid AND p2.chid = xedit.chid)
        -- 3.
        OR EXISTS(SELECT pid, relation FROM producers_relations_hist WHERE chid = xoldchid   EXCEPT SELECT pid, relation FROM producers_relations_hist WHERE chid = xedit.chid)
        OR EXISTS(SELECT pid, relation FROM producers_relations_hist WHERE chid = xedit.chid EXCEPT SELECT pid, relation FROM producers_relations_hist WHERE chid = xoldchid)
      ))
    THEN
      UPDATE producers SET rgraph = NULL WHERE id = xedit.itemid;
      NOTIFY relgraph; -- This notify is not done by the producer_relgraph_notify trigger for new entries or if rgraph was already NULL
    END IF;
  END IF;

  -- Set vn.rgraph to NULL and notify when:
  -- 1. There's a new vn entry with some relations
  -- 2. The vn title has changed
  -- 3. The vn relations have been changed
  IF xtype = 'v' THEN
    IF -- 1.
         (xoldchid IS NULL AND EXISTS(SELECT 1 FROM vn_relations_hist WHERE chid = xedit.chid))
      OR (xoldchid IS NOT NULL AND (
        -- 2.
           EXISTS(SELECT 1 FROM vn_hist v1, vn_hist v2 WHERE v2.title <> v1.title AND v1.chid = xoldchid AND v2.chid = xedit.chid)
        -- 3.
        OR EXISTS(SELECT vid, relation, official FROM vn_relations_hist WHERE chid = xoldchid   EXCEPT SELECT vid, relation, official FROM vn_relations_hist WHERE chid = xedit.chid)
        OR EXISTS(SELECT vid, relation, official FROM vn_relations_hist WHERE chid = xedit.chid EXCEPT SELECT vid, relation, official FROM vn_relations_hist WHERE chid = xoldchid)
      ))
    THEN
      UPDATE vn SET rgraph = NULL WHERE id = xedit.itemid;
      NOTIFY relgraph;
    END IF;
  END IF;

  -- Set c_search to NULL and notify when
  -- 1. A new VN entry is created
  -- 2. The vn title/original/alias has changed
  IF xtype = 'v' THEN
    IF -- 1.
       xoldchid IS NULL OR
       -- 2.
       EXISTS(SELECT 1 FROM vn_hist v1, vn_hist v2 WHERE (v2.title <> v1.title OR v2.original <> v1.original OR v2.alias <> v1.alias) AND v1.chid = xoldchid AND v2.chid = xedit.chid)
    THEN
      UPDATE vn SET c_search = NULL WHERE id = xedit.itemid;
      NOTIFY vnsearch;
    END IF;
  END IF;

  -- Set related vn.c_search columns to NULL and notify when
  -- 1. A new release is created
  -- 2. A release has been hidden or unhidden
  -- 3. The release title/original has changed
  -- 4. The releases_vn table differs from a previous revision
  IF xtype = 'r' THEN
    IF -- 1.
       xoldchid IS NULL OR
       -- 2.
       EXISTS(SELECT 1 FROM changes c1, changes c2 WHERE c1.ihid IS DISTINCT FROM c2.ihid AND c1.id = xedit.chid AND c2.id = xoldchid) OR
       -- 3.
       EXISTS(SELECT 1 FROM releases_hist r1, releases_hist r2 WHERE (r2.title <> r1.title OR r2.original <> r1.original) AND r1.chid = xoldchid AND r2.chid = xedit.chid) OR
       -- 4.
       EXISTS(SELECT vid FROM releases_vn_hist WHERE chid = xoldchid   EXCEPT SELECT vid FROM releases_vn_hist WHERE chid = xedit.chid) OR
       EXISTS(SELECT vid FROM releases_vn_hist WHERE chid = xedit.chid EXCEPT SELECT vid FROM releases_vn_hist WHERE chid = xoldchid)
    THEN
      UPDATE vn SET c_search = NULL WHERE id IN(SELECT vid FROM releases_vn_hist WHERE chid IN(xedit.chid, xoldchid));
      NOTIFY vnsearch;
    END IF;
  END IF;

  -- Call update_vncache() for related VNs when a release has been created or edited
  -- (This could be made more specific, but update_vncache() is fast enough that it's not worth the complexity)
  IF xtype = 'r' THEN
    PERFORM update_vncache(vid) FROM (
      SELECT DISTINCT vid FROM releases_vn_hist WHERE chid IN(xedit.chid, xoldchid)
    ) AS v(vid);
  END IF;

  -- Call notify_dbdel() if an entry has been deleted
  -- Call notify_listdel() if a vn/release entry has been deleted
  IF xoldchid IS NOT NULL
     AND EXISTS(SELECT 1 FROM changes WHERE id = xoldchid AND NOT ihid)
     AND EXISTS(SELECT 1 FROM changes WHERE id = xedit.chid AND ihid)
  THEN
    PERFORM notify_dbdel(xtype, xedit);
    IF xtype = 'v' OR xtype = 'r' THEN
      PERFORM notify_listdel(xtype, xedit);
    END IF;
  END IF;

  -- Call notify_dbedit() if a non-hidden entry has been edited
  IF xoldchid IS NOT NULL AND EXISTS(SELECT 1 FROM changes WHERE id = xedit.chid AND NOT ihid)
  THEN
    PERFORM notify_dbedit(xtype, xedit);
  END IF;
END;
$$ LANGUAGE plpgsql;



----------------------------------------------------------
--                  trigger functions                   --
----------------------------------------------------------


-- keep the c_* columns in the users table up to date
CREATE OR REPLACE FUNCTION update_users_cache() RETURNS TRIGGER AS $$
BEGIN
  IF TG_TABLE_NAME = 'votes' THEN
    IF TG_OP = 'INSERT' THEN
      UPDATE users SET c_votes = c_votes + 1 WHERE id = NEW.uid;
    ELSE
      UPDATE users SET c_votes = c_votes - 1 WHERE id = OLD.uid;
    END IF;
  ELSIF TG_TABLE_NAME = 'changes' THEN
    IF TG_OP = 'INSERT' THEN
      UPDATE users SET c_changes = c_changes + 1 WHERE id = NEW.requester;
    ELSE
      UPDATE users SET c_changes = c_changes - 1 WHERE id = OLD.requester;
    END IF;
  ELSIF TG_TABLE_NAME = 'tags_vn' THEN
    IF TG_OP = 'INSERT' THEN
      UPDATE users SET c_tags = c_tags + 1 WHERE id = NEW.uid;
    ELSE
      UPDATE users SET c_tags = c_tags - 1 WHERE id = OLD.uid;
    END IF;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE 'plpgsql';



-- the stats_cache table
CREATE OR REPLACE FUNCTION update_stats_cache() RETURNS TRIGGER AS $$
DECLARE
  unhidden boolean;
  hidden boolean;
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF TG_TABLE_NAME = 'users' THEN
      UPDATE stats_cache SET count = count+1 WHERE section = TG_TABLE_NAME;
    ELSE
      IF TG_TABLE_NAME = 'threads_posts' THEN
        IF EXISTS(SELECT 1 FROM threads WHERE id = NEW.tid AND threads.hidden = FALSE) THEN
          UPDATE stats_cache SET count = count+1 WHERE section = TG_TABLE_NAME;
        END IF;
      ELSE
        UPDATE stats_cache SET count = count+1 WHERE section = TG_TABLE_NAME;
      END IF;
    END IF;

  ELSIF TG_OP = 'UPDATE' THEN
    IF TG_TABLE_NAME IN('tags', 'traits') THEN
      unhidden := OLD.state <> 2 AND NEW.state = 2;
      hidden := OLD.state = 2 AND NEW.state <> 2;
    ELSE
      unhidden := OLD.hidden AND NOT NEW.hidden;
      hidden := NOT unhidden;
    END IF;
    IF unhidden THEN
      IF TG_TABLE_NAME = 'threads' THEN
        UPDATE stats_cache SET count = count+NEW.count WHERE section = 'threads_posts';
      END IF;
      UPDATE stats_cache SET count = count+1 WHERE section = TG_TABLE_NAME;
    ELSIF hidden THEN
      IF TG_TABLE_NAME = 'threads' THEN
        UPDATE stats_cache SET count = count-NEW.count WHERE section = 'threads_posts';
      END IF;
      UPDATE stats_cache SET count = count-1 WHERE section = TG_TABLE_NAME;
    END IF;

  ELSIF TG_OP = 'DELETE' AND TG_TABLE_NAME = 'users' THEN
    UPDATE stats_cache SET count = count-1 WHERE section = TG_TABLE_NAME;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE 'plpgsql';



-- insert rows into anime for new vn_anime.aid items
-- (this is a BEFORE trigger)
CREATE OR REPLACE FUNCTION vn_anime_aid() RETURNS trigger AS $$
BEGIN
  IF NOT EXISTS(SELECT 1 FROM anime WHERE id = NEW.aid) THEN
    INSERT INTO anime (id) VALUES (NEW.aid);
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;



-- For each row in rlists, there should be at least one corresponding row in
-- vnlists for at least one of the VNs linked to that release.
-- 1. When a row is deleted from vnlists, also remove all rows from rlists that
--    would otherwise not have a corresponding row in vnlists
-- 2. When a row is inserted to rlists and there is not yet a corresponding row
--    in vnlists, add a row in vnlists (with status=unknown) for each vn linked
--    to the release.
CREATE OR REPLACE FUNCTION update_vnlist_rlist() RETURNS trigger AS $$
BEGIN
  -- 1.
  IF TG_TABLE_NAME = 'vnlists' THEN
    DELETE FROM rlists WHERE uid = OLD.uid AND rid IN(SELECT rv.id
      -- fetch all related rows in rlists
      FROM releases_vn rv
      JOIN rlists rl ON rl.rid = rv.id
     WHERE rv.vid = OLD.vid AND rl.uid = OLD.uid
       -- and test for a corresponding row in vnlists
       AND NOT EXISTS(
        SELECT 1
          FROM releases_vn rvi
          JOIN vnlists vl ON vl.vid = rvi.vid AND uid = OLD.uid
         WHERE rvi.id = rv.id
       ));

  -- 2.
  ELSE
   INSERT INTO vnlists (uid, vid) SELECT NEW.uid, rv.vid
     -- all VNs linked to the release
      FROM releases_vn rv
     WHERE rv.id = NEW.rid
       -- but only if there are no corresponding rows in vnlists yet
       AND NOT EXISTS(
        SELECT 1
          FROM releases_vn rvi
          JOIN vnlists vl ON vl.vid = rvi.vid
         WHERE rvi.id = NEW.rid AND vl.uid = NEW.uid
       );
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;



-- Send a notify whenever anime info should be fetched
CREATE OR REPLACE FUNCTION anime_fetch_notify() RETURNS trigger AS $$
  BEGIN NOTIFY anime; RETURN NULL; END;
$$ LANGUAGE plpgsql;



-- 1. Send a notify when vn.rgraph is set to NULL, and there are related entries in vn_relations
-- 2. Set rgraph to NULL when c_languages or c_released has changed
CREATE OR REPLACE FUNCTION vn_relgraph_notify() RETURNS trigger AS $$
BEGIN
  IF EXISTS(SELECT 1 FROM vn_relations WHERE id = NEW.id) THEN
    -- 1.
    IF NEW.rgraph IS NULL THEN
      NOTIFY relgraph;
    -- 2.
    ELSE
      UPDATE vn SET rgraph = NULL WHERE id = NEW.id;
    END IF;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;


-- Send a notify when producers.rgraph is set to NULL, and there are related entries in producers_relations
CREATE OR REPLACE FUNCTION producer_relgraph_notify() RETURNS trigger AS $$
BEGIN
  IF EXISTS(SELECT 1 FROM producers_relations WHERE id = NEW.id) THEN
    NOTIFY relgraph;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;



-- NOTIFY on insert into changes/posts/tags/trait
CREATE OR REPLACE FUNCTION insert_notify() RETURNS trigger AS $$
BEGIN
  IF TG_TABLE_NAME = 'changes' THEN
    NOTIFY newrevision;
  ELSIF TG_TABLE_NAME = 'threads_posts' THEN
    NOTIFY newpost;
  ELSIF TG_TABLE_NAME = 'tags' THEN
    NOTIFY newtag;
  ELSIF TG_TABLE_NAME = 'traits' THEN
    NOTIFY newtrait;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;



-- Send a vnsearch notification when the c_search column is set to NULL.
CREATE OR REPLACE FUNCTION vn_vnsearch_notify() RETURNS trigger AS $$
  BEGIN NOTIFY vnsearch; RETURN NULL; END;
$$ LANGUAGE plpgsql;




----------------------------------------------------------
--                notification functions                --
----------------------------------------------------------


-- called on INSERT INTO threads_posts
CREATE OR REPLACE FUNCTION notify_pm() RETURNS trigger AS $$
BEGIN
  INSERT INTO notifications (ntype, ltype, uid, iid, subid, c_title, c_byuser)
    SELECT 'pm', 't', tb.iid, t.id, NEW.num, t.title, NEw.uid
      FROM threads t
      JOIN threads_boards tb ON tb.tid = t.id
     WHERE t.id = NEW.tid
       AND tb.type = 'u'
       AND tb.iid <> NEW.uid -- don't notify when posting in your own board
       AND NOT EXISTS( -- don't notify when you haven't read an earlier post in the thread yet
         SELECT 1
           FROM notifications n
          WHERE n.uid = tb.iid
            AND n.ntype = 'pm'
            AND n.iid = t.id
            AND n.read IS NULL
       );
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;



-- called when an entry has been deleted
CREATE OR REPLACE FUNCTION notify_dbdel(xtype dbentry_type, xedit edit_rettype) RETURNS void AS $$
  INSERT INTO notifications (ntype, ltype, uid, iid, subid, c_title, c_byuser)
    SELECT DISTINCT 'dbdel'::notification_ntype, xtype::text::notification_ltype, h.requester, xedit.itemid, xedit.rev, x.title, h2.requester
      FROM changes h
      -- join info about the deletion itself
      JOIN changes h2 ON h2.id = xedit.chid
      -- Fetch the latest name/title of the entry
      -- this method may look a bit unintuitive, but it's way faster than doing LEFT JOINs
      JOIN (  SELECT v.title FROM vn v WHERE xtype = 'v' AND v.id = xedit.itemid
        UNION SELECT r.title FROM releases r WHERE xtype = 'r' AND r.id = xedit.itemid
        UNION SELECT p.name  FROM producers p WHERE xtype = 'p' AND p.id = xedit.itemid
        UNION SELECT c.name  FROM chars c WHERE xtype = 'c' AND c.id = xedit.itemid
        UNION SELECT sa.name FROM staff s JOIN staff_alias sa ON sa.aid = s.aid WHERE xtype = 's' AND s.id = xedit.itemid
      ) x(title) ON true
     WHERE h.type = xtype AND h.itemid = xedit.itemid
       AND h.requester <> 1 -- exclude Multi
       AND h.requester <> h2.requester; -- exclude the user who deleted the entry
$$ LANGUAGE sql;



-- Called when a non-deleted item has been edited.
CREATE OR REPLACE FUNCTION notify_dbedit(xtype dbentry_type, xedit edit_rettype) RETURNS void AS $$
  INSERT INTO notifications (ntype, ltype, uid, iid, subid, c_title, c_byuser)
    SELECT DISTINCT 'dbedit'::notification_ntype, xtype::text::notification_ltype, h.requester, xedit.itemid, xedit.rev, x.title, h2.requester
      FROM changes h
      -- join info about the edit itself
      JOIN changes h2 ON h2.id = xedit.chid
      -- Fetch the latest name/title of the entry
      JOIN (  SELECT v.title FROM vn v WHERE xtype = 'v' AND v.id = xedit.itemid
        UNION SELECT r.title FROM releases r WHERE xtype = 'r' AND r.id = xedit.itemid
        UNION SELECT p.name  FROM producers p WHERE xtype = 'p' AND p.id = xedit.itemid
        UNION SELECT c.name  FROM chars c WHERE xtype = 'c' AND c.id = xedit.itemid
        UNION SELECT sa.name FROM staff s JOIN staff_alias sa ON sa.aid = s.aid WHERE xtype = 's' AND s.id = xedit.itemid
      ) x(title) ON true
     WHERE h.type = xtype AND h.itemid = xedit.itemid
       AND h.requester <> h2.requester -- exclude the user who edited the entry
       -- exclude users who don't want this notify
       AND NOT EXISTS(SELECT 1 FROM users_prefs up WHERE uid = h.requester AND key = 'notify_nodbedit');
$$ LANGUAGE sql;



-- called when a VN/release entry has been deleted
CREATE OR REPLACE FUNCTION notify_listdel(xtype dbentry_type, xedit edit_rettype) RETURNS void AS $$
  INSERT INTO notifications (ntype, ltype, uid, iid, subid, c_title, c_byuser)
    SELECT DISTINCT 'listdel'::notification_ntype, xtype::text::notification_ltype, u.uid, xedit.itemid, xedit.rev, x.title, c.requester
      -- look for users who should get this notify
      FROM (
              SELECT uid FROM votes   WHERE xtype = 'v' AND vid = xedit.itemid
        UNION SELECT uid FROM vnlists WHERE xtype = 'v' AND vid = xedit.itemid
        UNION SELECT uid FROM wlists  WHERE xtype = 'v' AND vid = xedit.itemid
        UNION SELECT uid FROM rlists  WHERE xtype = 'r' AND rid = xedit.itemid
      ) u
      -- fetch info about this edit
      JOIN changes c ON c.id = xedit.chid
      JOIN (
              SELECT title FROM vn       WHERE xtype = 'v' AND id = xedit.itemid
        UNION SELECT title FROM releases WHERE xtype = 'r' AND id = xedit.itemid
      ) x ON true
     WHERE c.requester <> u.uid;
$$ LANGUAGE sql;


-- called on INSERT INTO threads_posts when (NEW.num = 1)
CREATE OR REPLACE FUNCTION notify_announce() RETURNS trigger AS $$
BEGIN
  INSERT INTO notifications (ntype, ltype, uid, iid, subid, c_title, c_byuser)
    SELECT 'announce', 't', up.uid, t.id, 1, t.title, NEw.uid
      FROM threads t
      JOIN threads_boards tb ON tb.tid = t.id
      -- get the users who want this announcement
      JOIN users_prefs up ON up.key = 'notify_announce'
     WHERE t.id = NEW.tid
       AND tb.type = 'an' -- announcement board
       AND NOT t.hidden;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;


