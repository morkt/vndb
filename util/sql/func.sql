
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



-- update_vncache(id) - updates the c_* columns in the vn table
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
    c_olang = ARRAY(
      SELECT lang
        FROM releases_lang
       WHERE rid = (
        SELECT r.latest
          FROM releases_vn rv
          JOIN releases r ON rv.rid = r.latest
          JOIN releases_rev rr ON rr.id = r.latest AND rr.rid = r.id
         WHERE rr.released > 0
           AND NOT r.hidden
           AND rv.vid = $1
         ORDER BY rr.released
         LIMIT 1
       )
    ),
    c_languages = ARRAY(
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
    ),
    c_platforms = ARRAY(
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
        SELECT 15, tid, c.id, spoil, false
        FROM chars_traits ct
        JOIN chars c ON c.latest = ct.cid
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


-- IMPORTANT: these functions will need to be updated on each change in the DB structure
--   of the relevant tables


-- create temporary table for generic revision info
CREATE OR REPLACE FUNCTION edit_revtable(t dbentry_type, i integer) RETURNS void AS $$
BEGIN
  BEGIN
    CREATE TEMPORARY TABLE edit_revision (
      type dbentry_type NOT NULL,
      iid integer,
      requester integer,
      ip inet,
      comments text,
      ihid boolean,
      ilock boolean
    );
  EXCEPTION WHEN duplicate_table THEN
    TRUNCATE edit_revision;
  END;
  INSERT INTO edit_revision (type, iid, ihid, ilock) VALUES (t,
    (       SELECT vid FROM vn_rev WHERE id = i
      UNION SELECT rid FROM releases_rev WHERE id = i
      UNION SELECT cid FROM chars_rev WHERE id = i
      UNION SELECT pid FROM producers_rev WHERE id = i
      UNION SELECT sid FROM staff_rev WHERE id = i),
    COALESCE((SELECT ihid FROM changes WHERE id = i), FALSE),
    COALESCE((SELECT ilock FROM changes WHERE id = i), FALSE)
  );
END;
$$ LANGUAGE plpgsql;



CREATE OR REPLACE FUNCTION edit_commit() RETURNS edit_rettype AS $$
DECLARE
  r edit_rettype;
  t dbentry_type;
  i integer;
BEGIN
  SELECT type INTO t FROM edit_revision;
  SELECT iid INTO i FROM edit_revision;
  -- figure out revision number
  IF i IS NULL THEN
    r.rev := 1;
  ELSE
    SELECT c.rev+1 INTO r.rev FROM changes c
      JOIN (  SELECT id FROM vn_rev        WHERE t = 'v' AND vid = i
        UNION SELECT id FROM releases_rev  WHERE t = 'r' AND rid = i
        UNION SELECT id FROM producers_rev WHERE t = 'p' AND pid = i
        UNION SELECT id FROM chars_rev     WHERE t = 'c' AND cid = i
        UNION SELECT id FROM staff_rev     WHERE t = 's' AND sid = i
      ) x(id) ON x.id = c.id
      ORDER BY c.id DESC
      LIMIT 1;
  END IF;
  -- insert change
  INSERT INTO changes (type, requester, ip, comments, ihid, ilock, rev)
    SELECT t, requester, ip, comments, ihid, ilock, r.rev
    FROM edit_revision
    RETURNING id INTO r.cid;
  -- insert DB item
  IF i IS NULL THEN
    CASE t
      WHEN 'v' THEN INSERT INTO vn        (latest) VALUES (0) RETURNING id INTO r.iid;
      WHEN 'r' THEN INSERT INTO releases  (latest) VALUES (0) RETURNING id INTO r.iid;
      WHEN 'p' THEN INSERT INTO producers (latest) VALUES (0) RETURNING id INTO r.iid;
      WHEN 'c' THEN INSERT INTO chars     (latest) VALUES (0) RETURNING id INTO r.iid;
      WHEN 's' THEN INSERT INTO staff     (latest) VALUES (0) RETURNING id INTO r.iid;
    END CASE;
  ELSE
    r.iid := i;
  END IF;
  RETURN r;
END;
$$ LANGUAGE plpgsql;



CREATE OR REPLACE FUNCTION edit_vn_init(cid integer) RETURNS void AS $$
#variable_conflict use_variable
BEGIN
  -- create tables, based on existing tables (so that the column types are always synchronised)
  BEGIN
    CREATE TEMPORARY TABLE edit_vn (LIKE vn_rev INCLUDING DEFAULTS INCLUDING CONSTRAINTS);
    ALTER TABLE edit_vn DROP COLUMN id;
    ALTER TABLE edit_vn DROP COLUMN vid;
    CREATE TEMPORARY TABLE edit_vn_anime (LIKE vn_anime INCLUDING DEFAULTS INCLUDING CONSTRAINTS);
    ALTER TABLE edit_vn_anime DROP COLUMN vid;
    CREATE TEMPORARY TABLE edit_vn_relations (LIKE vn_relations INCLUDING DEFAULTS INCLUDING CONSTRAINTS);
    ALTER TABLE edit_vn_relations DROP COLUMN vid1;
    ALTER TABLE edit_vn_relations RENAME COLUMN vid2 TO vid;
    CREATE TEMPORARY TABLE edit_vn_screenshots (LIKE vn_screenshots INCLUDING DEFAULTS INCLUDING CONSTRAINTS);
    ALTER TABLE edit_vn_screenshots DROP COLUMN vid;
    CREATE TEMPORARY TABLE edit_vn_staff (LIKE vn_staff INCLUDING DEFAULTS INCLUDING CONSTRAINTS);
    ALTER TABLE edit_vn_staff DROP COLUMN vid;
    CREATE TEMPORARY TABLE edit_vn_seiyuu (LIKE vn_seiyuu INCLUDING DEFAULTS INCLUDING CONSTRAINTS);
    ALTER TABLE edit_vn_seiyuu DROP COLUMN vid;
  EXCEPTION WHEN duplicate_table THEN
    TRUNCATE edit_vn, edit_vn_anime, edit_vn_relations, edit_vn_screenshots, edit_vn_staff, edit_vn_seiyuu;
  END;
  PERFORM edit_revtable('v', cid);
  -- new VN, load defaults
  IF cid IS NULL THEN
    INSERT INTO edit_vn DEFAULT VALUES;
  -- otherwise, load revision
  ELSE
    INSERT INTO edit_vn SELECT title, alias, img_nsfw, length, "desc", l_wp, image, l_encubed, l_renai, original FROM vn_rev WHERE id = cid;
    INSERT INTO edit_vn_anime SELECT aid FROM vn_anime WHERE vid = cid;
    INSERT INTO edit_vn_relations SELECT vid2, relation, official FROM vn_relations WHERE vid1 = cid;
    INSERT INTO edit_vn_screenshots SELECT scr, nsfw, rid FROM vn_screenshots WHERE vid = cid;
    INSERT INTO edit_vn_staff SELECT aid, role, note FROM vn_staff WHERE vid = cid;
    INSERT INTO edit_vn_seiyuu SELECT aid, vs.cid, note FROM vn_seiyuu vs WHERE vid = cid;
  END IF;
END;
$$ LANGUAGE plpgsql;



CREATE OR REPLACE FUNCTION edit_vn_commit() RETURNS edit_rettype AS $$
DECLARE
  r edit_rettype;
BEGIN
  IF (SELECT COUNT(*) FROM edit_vn) <> 1 THEN
    RAISE 'edit_vn must have exactly one row!';
  END IF;
  SELECT INTO r * FROM edit_commit();
  INSERT INTO vn_rev SELECT r.cid, r.iid, title, alias, img_nsfw, length, "desc", l_wp, image, l_encubed, l_renai, original FROM edit_vn;
  INSERT INTO vn_anime SELECT r.cid, aid FROM edit_vn_anime;
  INSERT INTO vn_relations SELECT r.cid, vid, relation, official FROM edit_vn_relations;
  INSERT INTO vn_screenshots SELECT r.cid, scr, nsfw, rid FROM edit_vn_screenshots;
  INSERT INTO vn_staff SELECT r.cid, aid, role, note FROM edit_vn_staff;
  INSERT INTO vn_seiyuu SELECT r.cid, aid, cid, note FROM edit_vn_seiyuu;
  UPDATE vn SET latest = r.cid WHERE id = r.iid;
  RETURN r;
END;
$$ LANGUAGE plpgsql;



CREATE OR REPLACE FUNCTION edit_release_init(cid integer) RETURNS void AS $$
BEGIN
  -- temp. tables
  BEGIN
    CREATE TEMPORARY TABLE edit_release (LIKE releases_rev INCLUDING DEFAULTS INCLUDING CONSTRAINTS);
    ALTER TABLE edit_release DROP COLUMN id;
    ALTER TABLE edit_release DROP COLUMN rid;
    CREATE TEMPORARY TABLE edit_release_lang (LIKE releases_lang INCLUDING DEFAULTS INCLUDING CONSTRAINTS);
    ALTER TABLE edit_release_lang DROP COLUMN rid;
    CREATE TEMPORARY TABLE edit_release_media (LIKE releases_media INCLUDING DEFAULTS INCLUDING CONSTRAINTS);
    ALTER TABLE edit_release_media DROP COLUMN rid;
    CREATE TEMPORARY TABLE edit_release_platforms (LIKE releases_platforms INCLUDING DEFAULTS INCLUDING CONSTRAINTS);
    ALTER TABLE edit_release_platforms DROP COLUMN rid;
    CREATE TEMPORARY TABLE edit_release_producers (LIKE releases_producers INCLUDING DEFAULTS INCLUDING CONSTRAINTS);
    ALTER TABLE edit_release_producers DROP COLUMN rid;
    CREATE TEMPORARY TABLE edit_release_vn (LIKE releases_vn INCLUDING DEFAULTS INCLUDING CONSTRAINTS);
    ALTER TABLE edit_release_vn DROP COLUMN rid;
  EXCEPTION WHEN duplicate_table THEN
    TRUNCATE edit_release, edit_release_lang, edit_release_media, edit_release_platforms, edit_release_producers, edit_release_vn;
  END;
  PERFORM edit_revtable('r', cid);
  -- new release
  IF cid IS NULL THEN
    INSERT INTO edit_release DEFAULT VALUES;
  -- load revision
  ELSE
    INSERT INTO edit_release SELECT title, original, type, website, released, notes, minage, gtin, patch, catalog, resolution, voiced, freeware, doujin, ani_story, ani_ero FROM releases_rev WHERE id = cid;
    INSERT INTO edit_release_lang SELECT lang FROM releases_lang WHERE rid = cid;
    INSERT INTO edit_release_media SELECT medium, qty FROM releases_media WHERE rid = cid;
    INSERT INTO edit_release_platforms SELECT platform FROM releases_platforms WHERE rid = cid;
    INSERT INTO edit_release_producers SELECT pid, developer, publisher FROM releases_producers WHERE rid = cid;
    INSERT INTO edit_release_vn SELECT vid FROM releases_vn WHERE rid = cid;
  END IF;
END;
$$ LANGUAGE plpgsql;



CREATE OR REPLACE FUNCTION edit_release_commit() RETURNS edit_rettype AS $$
DECLARE
  r edit_rettype;
BEGIN
  IF (SELECT COUNT(*) FROM edit_release) <> 1 THEN
    RAISE 'edit_release must have exactly one row!';
  ELSIF NOT EXISTS(SELECT 1 FROM edit_release_vn) THEN
    RAISE 'edit_release_vn must have at least one row!';
  END IF;
  SELECT INTO r * FROM edit_commit();
  INSERT INTO releases_rev SELECT r.cid, r.iid, title, original, type, website, released, notes, minage, gtin, patch, catalog, resolution, voiced, freeware, doujin, ani_story, ani_ero FROM edit_release;
  INSERT INTO releases_lang SELECT r.cid, lang FROM edit_release_lang;
  INSERT INTO releases_media SELECT r.cid, medium, qty FROM edit_release_media;
  INSERT INTO releases_platforms SELECT r.cid, platform FROM edit_release_platforms;
  INSERT INTO releases_producers SELECT pid, r.cid, developer, publisher FROM edit_release_producers;
  INSERT INTO releases_vn SELECT r.cid, vid FROM edit_release_vn;
  UPDATE releases SET latest = r.cid WHERE id = r.iid;
  RETURN r;
END;
$$ LANGUAGE plpgsql;



CREATE OR REPLACE FUNCTION edit_producer_init(cid integer) RETURNS void AS $$
BEGIN
  BEGIN
    CREATE TEMPORARY TABLE edit_producer (LIKE producers_rev INCLUDING DEFAULTS INCLUDING CONSTRAINTS);
    ALTER TABLE edit_producer DROP COLUMN id;
    ALTER TABLE edit_producer DROP COLUMN pid;
    CREATE TEMPORARY TABLE edit_producer_relations (LIKE producers_relations INCLUDING DEFAULTS INCLUDING CONSTRAINTS);
    ALTER TABLE edit_producer_relations DROP COLUMN pid1;
    ALTER TABLE edit_producer_relations RENAME COLUMN pid2 TO pid;
  EXCEPTION WHEN duplicate_table THEN
    TRUNCATE edit_producer, edit_producer_relations;
  END;
  PERFORM edit_revtable('p', cid);
  -- new producer
  IF cid IS NULL THEN
    INSERT INTO edit_producer DEFAULT VALUES;
  -- load revision
  ELSE
    INSERT INTO edit_producer SELECT type, name, original, website, lang, "desc", alias, l_wp FROM producers_rev WHERE id = cid;
    INSERT INTO edit_producer_relations SELECT pid2, relation FROM producers_relations WHERE pid1 = cid;
  END IF;
END;
$$ LANGUAGE plpgsql;



CREATE OR REPLACE FUNCTION edit_producer_commit() RETURNS edit_rettype AS $$
DECLARE
  r edit_rettype;
BEGIN
  IF (SELECT COUNT(*) FROM edit_producer) <> 1 THEN
    RAISE 'edit_producer must have exactly one row!';
  END IF;
  SELECT INTO r * FROM edit_commit();
  INSERT INTO producers_rev SELECT r.cid, r.iid, type, name, original, website, lang, "desc", alias, l_wp FROM edit_producer;
  INSERT INTO producers_relations SELECT r.cid, pid, relation FROM edit_producer_relations;
  UPDATE producers SET latest = r.cid WHERE id = r.iid;
  RETURN r;
END;
$$ LANGUAGE plpgsql;



CREATE OR REPLACE FUNCTION edit_char_init(hid integer) RETURNS void AS $$
BEGIN
  BEGIN
    CREATE TEMPORARY TABLE edit_char (LIKE chars_rev INCLUDING DEFAULTS INCLUDING CONSTRAINTS);
    ALTER TABLE edit_char DROP COLUMN id;
    ALTER TABLE edit_char DROP COLUMN cid;
    CREATE TEMPORARY TABLE edit_char_traits (LIKE chars_traits INCLUDING DEFAULTS INCLUDING CONSTRAINTS);
    ALTER TABLE edit_char_traits DROP COLUMN cid;
    CREATE TEMPORARY TABLE edit_char_vns (LIKE chars_vns INCLUDING DEFAULTS INCLUDING CONSTRAINTS);
    ALTER TABLE edit_char_vns DROP COLUMN cid;
  EXCEPTION WHEN duplicate_table THEN
    TRUNCATE edit_char, edit_char_traits, edit_char_vns;
  END;
  PERFORM edit_revtable('c', hid);
  -- new char
  IF hid IS NULL THEN
    INSERT INTO edit_char DEFAULT VALUES;
  -- load revision
  ELSE
    INSERT INTO edit_char SELECT name, original, alias, image, "desc", gender, s_bust, s_waist, s_hip, b_month, b_day, height, weight, bloodt, main, main_spoil FROM chars_rev WHERE id = hid;
    INSERT INTO edit_char_traits SELECT tid, spoil FROM chars_traits WHERE cid = hid;
    INSERT INTO edit_char_vns SELECT vid, rid, spoil, role FROM chars_vns WHERE cid = hid;
  END IF;
END;
$$ LANGUAGE plpgsql;



CREATE OR REPLACE FUNCTION edit_char_commit() RETURNS edit_rettype AS $$
DECLARE
  r edit_rettype;
BEGIN
  IF (SELECT COUNT(*) FROM edit_char) <> 1 THEN
    RAISE 'edit_char must have exactly one row!';
  END IF;
  SELECT INTO r * FROM edit_commit();
  INSERT INTO chars_rev SELECT r.cid, r.iid, name, original, alias, image, "desc", gender, s_bust, s_waist, s_hip, b_month, b_day, height, weight, bloodt, main, main_spoil FROM edit_char;
  INSERT INTO chars_traits SELECT r.cid, tid, spoil FROM edit_char_traits;
  INSERT INTO chars_vns SELECT r.cid, vid, rid, spoil, role FROM edit_char_vns;
  UPDATE chars SET latest = r.cid WHERE id = r.iid;
  RETURN r;
END;
$$ LANGUAGE plpgsql;



CREATE OR REPLACE FUNCTION edit_staff_init(cid integer) RETURNS void AS $$
BEGIN
  BEGIN
    CREATE TEMPORARY TABLE edit_staff (LIKE staff_rev INCLUDING DEFAULTS INCLUDING CONSTRAINTS);
    ALTER TABLE edit_staff DROP COLUMN id;
    ALTER TABLE edit_staff DROP COLUMN sid;
    CREATE TEMPORARY TABLE edit_staff_aliases (LIKE staff_alias INCLUDING DEFAULTS INCLUDING CONSTRAINTS);
    ALTER TABLE edit_staff_aliases DROP COLUMN rid;
  EXCEPTION WHEN duplicate_table THEN
    TRUNCATE edit_staff, edit_staff_aliases;
  END;
  PERFORM edit_revtable('s', cid);
  -- new staff member
  IF cid IS NULL THEN
    INSERT INTO edit_staff (aid) VALUES (0);
  -- load revision
  ELSE
    INSERT INTO edit_staff SELECT aid, gender, lang, "desc", l_wp, l_site, l_twitter, l_anidb FROM staff_rev WHERE id = cid;
    INSERT INTO edit_staff_aliases SELECT id, name, original FROM staff_alias WHERE rid = cid;
  END IF;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION edit_staff_commit() RETURNS edit_rettype AS $$
DECLARE
  r edit_rettype;
BEGIN
  IF (SELECT COUNT(*) FROM edit_staff) <> 1 THEN
    RAISE 'edit_staff must have exactly one row!';
  END IF;
  SELECT INTO r * FROM edit_commit();
  INSERT INTO staff_alias (id, rid, name, original)
    SELECT id, r.cid, name, original FROM edit_staff_aliases;
  INSERT INTO staff_rev (id, sid, aid, gender, lang, "desc", l_wp, l_site, l_twitter, l_anidb)
    SELECT r.cid, r.iid, aid, gender, lang, "desc", l_wp, l_site, l_twitter, l_anidb FROM edit_staff;
  UPDATE staff SET latest = r.cid WHERE id = r.iid;
  RETURN r;
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
    DELETE FROM rlists WHERE uid = OLD.uid AND rid IN(SELECT r.id
      -- fetch all related rows in rlists
      FROM releases_vn rv
      JOIN releases r ON r.latest = rv.rid
      JOIN rlists rl ON rl.rid = r.id
     WHERE rv.vid = OLD.vid AND rl.uid = OLD.uid
       -- and test for a corresponding row in vnlists
       AND NOT EXISTS(
        SELECT 1
          FROM releases_vn rvi
          JOIN vnlists vl ON vl.vid = rvi.vid AND uid = OLD.uid
         WHERE rvi.rid = r.latest
       ));

  -- 2.
  ELSE
   INSERT INTO vnlists (uid, vid) SELECT NEW.uid, rv.vid
     -- all VNs linked to the release
      FROM releases_vn rv
      JOIN releases r ON rv.rid = r.latest
     WHERE r.id = NEW.rid
       -- but only if there are no corresponding rows in vnlists yet
       AND NOT EXISTS(
        SELECT 1
          FROM releases_vn rvi
          JOIN releases ri ON rvi.rid = ri.latest
          JOIN vnlists vl ON vl.vid = rvi.vid
         WHERE ri.id = NEW.rid AND vl.uid = NEW.uid
       );
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;



-- Send a notify whenever anime info should be fetched
CREATE OR REPLACE FUNCTION anime_fetch_notify() RETURNS trigger AS $$
  BEGIN NOTIFY anime; RETURN NULL; END;
$$ LANGUAGE plpgsql;



-- Update vn.rgraph column and send notify when a relation graph needs to be regenerated
-- 1. NOTIFY is sent on VN edit or insert or change in vn.rgraph, when rgraph = NULL and entries in vn_relations
-- vn.rgraph is set to NULL when:
-- 2. UPDATE on vn where c_released or c_languages has changed
-- 3. VN edit of which the title differs from previous revision
-- 4. VN edit with items in vn_relations that differ from previous
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
        OR EXISTS(SELECT vid2, relation, official FROM vn_relations WHERE vid1 = OLD.latest EXCEPT SELECT vid2, relation, official FROM vn_relations WHERE vid1 = NEW.latest)
        OR (SELECT COUNT(*) FROM vn_relations WHERE vid1 = OLD.latest) <> (SELECT COUNT(*) FROM vn_relations WHERE vid1 = NEW.latest)
      )
    THEN
      UPDATE vn SET rgraph = NULL WHERE id = NEW.id;
    END IF;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;



-- Same as above for producers, with slight differences in the steps:
-- There is no 2, and
-- 3 = Producer edit of which the name, language or type differs from the previous revision
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



-- call update_vncache() when a release is added, edited, hidden or unhidden
CREATE OR REPLACE FUNCTION release_vncache_update() RETURNS trigger AS $$
BEGIN
  PERFORM update_vncache(vid) FROM (
    SELECT DISTINCT vid FROM releases_vn WHERE rid = OLD.latest OR rid = NEW.latest
  ) AS v(vid);
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;



-- update (vn|release|producer|char).(hidden|locked) on a new revision
-- NOTE: this is a /before/ trigger, it modifies NEW
CREATE OR REPLACE FUNCTION update_hidlock() RETURNS trigger AS $$
DECLARE
  r record;
BEGIN
  SELECT INTO r ihid, ilock FROM changes WHERE id = NEW.latest;
  NEW.hidden := r.ihid;
  NEW.locked := r.ilock;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;



-- Check for updates to vn.c_search
-- 1. NOTIFY is sent when vn.c_search goes from non-NULL to NULL
-- vn.c_search is set to NULL when:
-- 2. VN add/edit of which the title/original/alias fields differ from previous revision
-- 3. Release gets hidden or unhidden
-- 4. Release add/edit of which the title/original/vn fields differ from the previous revision
CREATE OR REPLACE FUNCTION vn_vnsearch_notify() RETURNS trigger AS $$
BEGIN
  IF TG_TABLE_NAME = 'vn' THEN
    -- 1.
    IF NEW.c_search IS NULL THEN
      NOTIFY vnsearch;
    -- 2.
    ELSIF NEW.latest IS DISTINCT FROM OLD.latest THEN
      IF EXISTS(SELECT 1 FROM vn_rev v1, vn_rev v2
        WHERE v1.id = OLD.latest AND v2.id = NEW.latest
          AND (v1.title IS DISTINCT FROM v2.title OR v1.original IS DISTINCT FROM v2.original OR v1.alias IS DISTINCT FROM v2.alias)
      ) THEN
        UPDATE vn SET c_search = NULL WHERE id = NEW.id;
      END IF;
    END IF;
  ELSIF TG_TABLE_NAME = 'releases' THEN
    -- 3. & 4.
    IF NEW.hidden IS DISTINCT FROM OLD.hidden OR (
       NEW.latest IS DISTINCT FROM OLD.latest AND (
         EXISTS(
          SELECT 1 FROM releases_rev r1, releases_rev r2
           WHERE r1.id = OLD.latest AND r2.id = NEW.latest
             AND (r1.title IS DISTINCT FROM r2.title OR r1.original IS DISTINCT FROM r2.original)
         )
         OR EXISTS(SELECT vid FROM releases_vn WHERE rid = OLD.latest EXCEPT SELECT vid FROM releases_vn WHERE rid = NEW.latest)
         OR (SELECT COUNT(*) FROM releases_vn WHERE rid = OLD.latest) <> (SELECT COUNT(*) FROM releases_vn WHERE rid = NEW.latest)
    )) THEN
      UPDATE vn SET c_search = NULL WHERE id IN(SELECT vid FROM releases_vn WHERE rid = OLD.latest OR rid = NEW.latest);
    END IF;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;





----------------------------------------------------------
--                notification functions                --
--          (these are, in fact, also triggers)         --
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


-- called on UPDATE vn / producers / releases / chars when (NOT OLD.hidden AND NEW.hidden)
CREATE OR REPLACE FUNCTION notify_dbdel() RETURNS trigger AS $$
BEGIN
  INSERT INTO notifications (ntype, ltype, uid, iid, subid, c_title, c_byuser)
    SELECT DISTINCT 'dbdel'::notification_ntype,
           (CASE TG_TABLE_NAME WHEN 'vn' THEN 'v' WHEN 'releases' THEN 'r' WHEN 'producers' THEN 'p' ELSE 'c' END)::notification_ltype,
           h.requester, NEW.id, h2.rev, x.title, h2.requester
      -- look for changes of the deleted entry
      -- this method may look a bit unintuitive, but it's way faster than doing LEFT JOINs
      FROM changes h
      JOIN (  SELECT vr.id, vr2.title FROM vn_rev vr
                JOIN vn v ON v.id = vr.vid JOIN vn_rev vr2 ON vr2.id = v.latest
               WHERE TG_TABLE_NAME = 'vn' AND vr.vid = NEW.id
        UNION SELECT rr.id, rr2.title FROM releases_rev rr
                JOIN releases r ON r.id = rr.rid JOIN releases_rev rr2 ON rr2.id = r.latest
               WHERE TG_TABLE_NAME = 'releases'  AND rr.rid = NEW.id
        UNION SELECT pr.id, pr2.name FROM producers_rev pr
                JOIN producers p ON p.id = pr.pid JOIN producers_rev pr2 ON pr2.id = p.latest
               WHERE TG_TABLE_NAME = 'producers' AND pr.pid = NEW.id
        UNION SELECT cr.id, cr2.name FROM chars_rev cr
                JOIN chars c ON c.id = cr.cid JOIN chars_rev cr2 ON cr2.id = c.latest
               WHERE TG_TABLE_NAME = 'chars' AND cr.cid = NEW.id
      ) x(id, title) ON h.id = x.id
      -- join info about the deletion itself
      JOIN changes h2 ON h2.id = NEW.latest
     WHERE h.requester <> 1 -- exclude Multi
       -- exclude the user who deleted the entry
       AND h.requester <> h2.requester;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;


-- called on UPDATE vn / releases when (NOT OLD.hidden AND NEW.hidden)
CREATE OR REPLACE FUNCTION notify_listdel() RETURNS trigger AS $$
BEGIN
  INSERT INTO notifications (ntype, ltype, uid, iid, subid, c_title, c_byuser)
    SELECT DISTINCT 'listdel'::notification_ntype,
           (CASE TG_TABLE_NAME WHEN 'vn' THEN 'v' ELSE 'r' END)::notification_ltype,
           u.uid, NEW.id, c.rev, x.title, c.requester
      -- look for users who should get this notify
      FROM (
        -- voted on the VN
              SELECT uid FROM votes   WHERE TG_TABLE_NAME = 'vn' AND vid = NEW.id
        -- VN in vnlist
        UNION SELECT uid FROM vnlists WHERE TG_TABLE_NAME = 'vn' AND vid = NEW.id
        -- VN in wishlist
        UNION SELECT uid FROM wlists  WHERE TG_TABLE_NAME = 'vn' AND vid = NEW.id
        -- release in release list
        UNION SELECT uid FROM rlists  WHERE TG_TABLE_NAME = 'releases' AND rid = NEW.id
      ) u
      -- fetch info about this edit
      JOIN changes c ON c.id = NEW.latest
      JOIN (
              SELECT id, title FROM vn_rev       WHERE TG_TABLE_NAME = 'vn' AND vid = NEW.id
        UNION SELECT id, title FROM releases_rev WHERE TG_TABLE_NAME = 'releases' AND rid = NEW.id
      ) x ON c.id = x.id
     WHERE c.requester <> u.uid;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;


-- called on UPDATE vn / producers / releases / chars when (OLD.latest IS DISTINCT FROM NEW.latest AND NOT NEW.hidden)
-- this trigger is very similar to notify_dbdel()
CREATE OR REPLACE FUNCTION notify_dbedit() RETURNS trigger AS $$
BEGIN
  INSERT INTO notifications (ntype, ltype, uid, iid, subid, c_title, c_byuser)
    SELECT DISTINCT 'dbedit'::notification_ntype,
           (CASE TG_TABLE_NAME WHEN 'vn' THEN 'v' WHEN 'releases' THEN 'r' WHEN 'producers' THEN 'p' ELSE 'c' END)::notification_ltype,
           h.requester, NEW.id, h2.rev, x.title, h2.requester
      -- look for changes of the edited entry
      FROM changes h
      JOIN (  SELECT vr.id, vr2.title FROM vn_rev vr
                JOIN vn v ON v.id = vr.vid JOIN vn_rev vr2 ON vr2.id = v.latest
               WHERE TG_TABLE_NAME = 'vn' AND vr.vid = NEW.id
        UNION SELECT rr.id, rr2.title FROM releases_rev rr
                JOIN releases r ON r.id = rr.rid JOIN releases_rev rr2 ON rr2.id = r.latest
               WHERE TG_TABLE_NAME = 'releases'  AND rr.rid = NEW.id
        UNION SELECT pr.id, pr2.name FROM producers_rev pr
                JOIN producers p ON p.id = pr.pid JOIN producers_rev pr2 ON pr2.id = p.latest
               WHERE TG_TABLE_NAME = 'producers' AND pr.pid = NEW.id
        UNION SELECT cr.id, cr2.name FROM chars_rev cr
                JOIN chars c ON c.id = cr.cid JOIN chars_rev cr2 ON cr2.id = c.latest
               WHERE TG_TABLE_NAME = 'chars' AND cr.cid = NEW.id
      ) x(id, title) ON h.id = x.id
      -- join info about the deletion itself
      JOIN changes h2 ON h2.id = NEW.latest
      -- exclude the user who edited the entry
     WHERE h.requester <> h2.requester
       -- exclude users who don't want this notify
       AND NOT EXISTS(SELECT 1 FROM users_prefs up WHERE uid = h.requester AND key = 'notify_nodbedit');
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;


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


