-- Q: Why recreate all the tables rather than modify existing ones?
-- A: Because the production tables have been modified many times, and columns
--    weren't always in the same order as in scheme.sql. Recreating everything
--    also has the advantage of ensuring that all references and indices are
--    handled and documented here. In hindsight, it also seems like the easier
--    approach.

ALTER TABLE changes             RENAME TO changes_old;
ALTER TABLE chars               RENAME TO chars_old;
ALTER TABLE chars_rev           RENAME TO chars_rev_old;
ALTER TABLE chars_traits        RENAME TO chars_traits_old;
ALTER TABLE chars_vns           RENAME TO chars_vns_old;
ALTER TABLE producers           RENAME TO producers_old;
ALTER TABLE producers_rev       RENAME TO producers_rev_old;
ALTER TABLE producers_relations RENAME TO producers_relations_old;
ALTER TABLE releases            RENAME TO releases_old;
ALTER TABLE releases_rev        RENAME TO releases_rev_old;
ALTER TABLE releases_lang       RENAME TO releases_lang_old;
ALTER TABLE releases_media      RENAME TO releases_media_old;
ALTER TABLE releases_platforms  RENAME TO releases_platforms_old;
ALTER TABLE releases_producers  RENAME TO releases_producers_old;
ALTER TABLE releases_vn         RENAME TO releases_vn_old;
ALTER TABLE staff               RENAME TO staff_old;
ALTER TABLE staff_rev           RENAME TO staff_rev_old;
ALTER TABLE staff_alias         RENAME TO staff_alias_old;
ALTER TABLE vn                  RENAME TO vn_old;
ALTER TABLE vn_rev              RENAME TO vn_rev_old;
ALTER TABLE vn_anime            RENAME TO vn_anime_old;
ALTER TABLE vn_relations        RENAME TO vn_relations_old;
ALTER TABLE vn_screenshots      RENAME TO vn_screenshots_old;
ALTER TABLE vn_seiyuu           RENAME TO vn_seiyuu_old;
ALTER TABLE vn_staff            RENAME TO vn_staff_old;

-- XXX: The names of these sequences depend on how the corresponding tables
-- were generated. The names below are the ones in the production database.
ALTER SEQUENCE changes_id_seq     RENAME TO changes_id_seq_old;
ALTER SEQUENCE chars_id_seq       RENAME TO chars_id_seq_old;
ALTER SEQUENCE producers_id_seq   RENAME TO producers_id_seq_old;
ALTER SEQUENCE releases_id_seq    RENAME TO releases_id_seq_old;
ALTER SEQUENCE staff_alias_id_seq RENAME TO staff_alias_id_seq_old;
ALTER SEQUENCE staff_id_seq       RENAME TO staff_id_seq_old;
ALTER SEQUENCE vn_id_seq          RENAME TO vn_id_seq_old;

\i util/sql/schema.sql


-- XXX: This query uses a window function to generate changes.rev instead of
-- copying the value from the old table. This is done because, in the old
-- database schema, there was no uniqueness constraint on (type, itemid, rev),
-- and due to a race condition it was possible for duplicates to appear. This
-- is a pretty rare occurence, and easy to correct by renumbering the changes.
-- (Changes the URL of a few revision pages, but there's no way to avoid that)
INSERT INTO changes SELECT c.id, c.type, COALESCE(vr.vid, pr.pid, rr.rid, cr.cid, sr.sid),
    row_number() OVER (PARTITION BY c.type, COALESCE(vr.vid, pr.pid, rr.rid, cr.cid, sr.sid) ORDER BY c.id ASC),
    c.added, c.requester, c.ip, c.comments, c.ihid, c.ilock
  FROM changes_old c
  LEFT JOIN vn_rev_old vr ON vr.id = c.id
  LEFT JOIN producers_rev_old pr ON pr.id = c.id
  LEFT JOIN releases_rev_old rr ON rr.id = c.id
  LEFT JOIN chars_rev_old cr ON cr.id = c.id
  LEFT JOIN staff_rev_old sr ON sr.id = c.id;

INSERT INTO chars SELECT c.id, c.locked, c.hidden,
    cr.name, cr.original, cr.alias, cr.image, cr.desc, cr.gender, cr.s_bust, cr.s_waist, cr.s_hip,
    cr.b_month, cr.b_day, cr.height, cr.weight, cr.bloodt, cr.main, cr.main_spoil
  FROM chars_old c JOIN chars_rev_old cr ON cr.id = c.latest;

INSERT INTO chars_hist SELECT cr.id,
    cr.name, cr.original, cr.alias, cr.image, cr.desc, cr.gender, cr.s_bust, cr.s_waist, cr.s_hip,
    cr.b_month, cr.b_day, cr.height, cr.weight, cr.bloodt, cr.main, cr.main_spoil
  FROM chars_rev_old cr;

INSERT INTO chars_traits SELECT c.id, ct.tid, ct.spoil
  FROM chars_old c
  JOIN chars_traits_old ct ON ct.cid = c.latest;

INSERT INTO chars_traits_hist SELECT cid, tid, spoil
  FROM chars_traits_old;

INSERT INTO chars_vns SELECT c.id, cv.vid, cv.rid, cv.spoil, cv.role
  FROM chars_old c
  JOIN chars_vns_old cv ON cv.cid = c.latest;

INSERT INTO chars_vns_hist SELECT cid, vid, rid, spoil, role
  FROM chars_vns_old;

INSERT INTO producers SELECT p.id, p.locked, p.hidden,
    pr.type, pr.name, pr.original, pr.website, pr.lang, pr.desc, pr.alias, pr.l_wp, p.rgraph
  FROM producers_old p JOIN producers_rev_old pr ON pr.id = p.latest;

INSERT INTO producers_hist SELECT id, type, name, original, website, lang, "desc", alias, l_wp
  FROM producers_rev_old;

INSERT INTO producers_relations SELECT p.id, pr.pid2, pr.relation
  FROM producers_old p
  JOIN producers_relations_old pr ON p.latest = pr.pid1;

INSERT INTO producers_relations_hist SELECT pid1, pid2, relation
  FROM producers_relations_old;

INSERT INTO releases SELECT r.id, r.locked, r.hidden,
    rr.title, rr.original, rr.type, rr.website, rr.catalog, rr.gtin, rr.released, rr.notes, rr.minage, rr.patch,
    rr.freeware, rr.doujin, rr.resolution, rr.voiced, rr.ani_story, rr.ani_ero
  FROM releases_old r JOIN releases_rev_old rr ON rr.id = r.latest;

INSERT INTO releases_hist SELECT rr.id,
    rr.title, rr.original, rr.type, rr.website, rr.catalog, rr.gtin, rr.released, rr.notes, rr.minage, rr.patch,
    rr.freeware, rr.doujin, rr.resolution, rr.voiced, rr.ani_story, rr.ani_ero
  FROM releases_rev_old rr;

INSERT INTO releases_lang SELECT r.id, rl.lang
  FROM releases_old r JOIN releases_lang_old rl ON rl.rid = r.latest;

INSERT INTO releases_lang_hist SELECT rl.rid, rl.lang
  FROM releases_lang_old rl;

INSERT INTO releases_media SELECT r.id, rm.medium, rm.qty
  FROM releases_old r JOIN releases_media_old rm ON rm.rid = r.latest;

INSERT INTO releases_media_hist SELECT rm.rid, rm.medium, rm.qty
  FROM releases_media_old rm;

INSERT INTO releases_platforms SELECT r.id, rp.platform
  FROM releases_old r JOIN releases_platforms_old rp ON rp.rid = r.latest;

INSERT INTO releases_platforms_hist SELECT rp.rid, rp.platform
  FROM releases_platforms_old rp;

INSERT INTO releases_producers SELECT r.id, rp.pid, rp.developer, rp.publisher
  FROM releases_old r JOIN releases_producers_old rp ON rp.rid = r.latest;

INSERT INTO releases_producers_hist SELECT rp.rid, rp.pid, rp.developer, rp.publisher
  FROM releases_producers_old rp;

INSERT INTO releases_vn SELECT r.id, rv.vid
  FROM releases_old r JOIN releases_vn_old rv ON rv.rid = r.latest;

INSERT INTO releases_vn_hist SELECT rv.rid, rv.vid
  FROM releases_vn_old rv;

INSERT INTO staff SELECT s.id, s.locked, s.hidden,
    sr.aid, sr.gender, sr.lang, sr.desc, sr.l_wp, sr.l_site, sr.l_twitter, sr.l_anidb
  FROM staff_old s JOIN staff_rev_old sr ON sr.id = s.latest;

INSERT INTO staff_hist SELECT sr.id,
    sr.aid, sr.gender, sr.lang, sr.desc, sr.l_wp, sr.l_site, sr.l_twitter, sr.l_anidb
  FROM staff_rev_old sr;

INSERT INTO staff_alias SELECT s.id, sa.id, sa.name, sa.original
  FROM staff_old s JOIN staff_alias_old sa ON sa.rid = s.latest;

INSERT INTO staff_alias_hist SELECT rid, id, name, original
  FROM staff_alias_old;

INSERT INTO vn SELECT v.id, v.locked, v.hidden,
    vr.title, vr.original, vr.alias, vr.length, vr.img_nsfw, vr.image, vr.desc, vr.l_wp, vr.l_encubed, vr.l_renai,
    v.rgraph, v.c_released, v.c_languages, v.c_olang, v.c_platforms, v.c_popularity, v.c_rating, v.c_votecount, v.c_search
  FROM vn_old v JOIN vn_rev_old vr ON vr.id = v.latest;

INSERT INTO vn_hist SELECT vr.id,
    vr.title, vr.original, vr.alias, vr.length, vr.img_nsfw, vr.image, vr.desc, vr.l_wp, vr.l_encubed, vr.l_renai
  FROM vn_rev_old vr;

INSERT INTO vn_anime SELECT v.id, va.aid
  FROM vn_old v JOIN vn_anime_old va ON va.vid = v.latest;

INSERT INTO vn_anime_hist SELECT vid, aid
  FROM vn_anime_old;

INSERT INTO vn_relations SELECT v.id, vr.vid2, vr.relation, vr.official
  FROM vn_old v JOIN vn_relations_old vr ON vr.vid1 = v.latest;

INSERT INTO vn_relations_hist SELECT vid1, vid2, relation, official
  FROM vn_relations_old;

INSERT INTO vn_screenshots SELECT v.id, vs.scr, vs.rid, vs.nsfw
  FROM vn_old v JOIN vn_screenshots_old vs ON vs.vid = v.latest;

INSERT INTO vn_screenshots_hist SELECT vid, scr, rid, nsfw
  FROM vn_screenshots_old;

INSERT INTO vn_seiyuu SELECT v.id, vs.aid, vs.cid, vs.note
  FROM vn_old v JOIN vn_seiyuu_old vs ON vs.vid = v.latest;

INSERT INTO vn_seiyuu_hist SELECT vid, aid, cid, note
  FROM vn_seiyuu_old;

INSERT INTO vn_staff SELECT v.id, vs.aid, vs.role, vs.note
  FROM vn_old v JOIN vn_staff_old vs ON vs.vid = v.latest;

INSERT INTO vn_staff_hist SELECT vid, aid, role, note
  FROM vn_staff_old;


SELECT setval('changes_id_seq',      nextval('changes_id_seq_old'));
SELECT setval('chars_id_seq',        nextval('chars_id_seq_old'));
SELECT setval('producers_id_seq',    nextval('producers_id_seq_old'));
SELECT setval('releases_id_seq',     nextval('releases_id_seq_old'));
SELECT setval('staff_alias_aid_seq', nextval('staff_alias_id_seq_old')); -- note the change from id to aid
SELECT setval('staff_id_seq',        nextval('staff_id_seq_old'));
SELECT setval('vn_id_seq',           nextval('vn_id_seq_old'));


-- Dropping all tables with CASCADE causes all foreign key references to and
-- from the tables to be dropped as well. This is exactly what we want, so we
-- can re-add the constraints on the newly created tables.
DROP TABLE changes_old CASCADE;
DROP TABLE chars_old CASCADE;
DROP TABLE chars_rev_old CASCADE;
DROP TABLE chars_traits_old CASCADE;
DROP TABLE chars_vns_old CASCADE;
DROP TABLE producers_old CASCADE;
DROP TABLE producers_rev_old CASCADE;
DROP TABLE producers_relations_old CASCADE;
DROP TABLE releases_old CASCADE;
DROP TABLE releases_rev_old CASCADE;
DROP TABLE releases_lang_old CASCADE;
DROP TABLE releases_media_old CASCADE;
DROP TABLE releases_platforms_old CASCADE;
DROP TABLE releases_producers_old CASCADE;
DROP TABLE releases_vn_old CASCADE;
DROP TABLE staff_old CASCADE;
DROP TABLE staff_rev_old CASCADE;
DROP TABLE staff_alias_old CASCADE;
DROP TABLE vn_old CASCADE;
DROP TABLE vn_rev_old CASCADE;
DROP TABLE vn_anime_old CASCADE;
DROP TABLE vn_relations_old CASCADE;
DROP TABLE vn_screenshots_old CASCADE;
DROP TABLE vn_seiyuu_old CASCADE;
DROP TABLE vn_staff_old CASCADE;

DROP INDEX threads_posts_ts;

DROP FUNCTION edit_revtable(dbentry_type, integer);
DROP FUNCTION edit_vn_init(integer);
DROP FUNCTION edit_vn_commit();
DROP FUNCTION edit_release_init(integer);
DROP FUNCTION edit_release_commit();
DROP FUNCTION edit_producer_init(integer);
DROP FUNCTION edit_producer_commit();
DROP FUNCTION edit_char_init(integer);
DROP FUNCTION edit_char_commit();
DROP FUNCTION edit_staff_init(integer);
DROP FUNCTION edit_staff_commit();
DROP FUNCTION release_vncache_update();
DROP FUNCTION notify_dbdel();
DROP FUNCTION notify_dbedit();
DROP FUNCTION notify_listdel();
DROP FUNCTION update_hidlock();

DROP TYPE edit_rettype CASCADE;
CREATE TYPE edit_rettype      AS (itemid integer, chid integer, rev integer);

\i util/sql/func.sql
\i util/sql/editfunc.sql
\i util/sql/tableattrs.sql
\i util/sql/triggers.sql
