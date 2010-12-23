
-- remove the NOT NULL from rr.minage and use -1 when unknown
UPDATE releases_rev SET minage = -1 WHERE minage IS NULL;
ALTER TABLE releases_rev ALTER COLUMN minage SET DEFAULT -1;
ALTER TABLE releases_rev ALTER COLUMN minage DROP NOT NULL;


-- speed up get-releases-by-vn queries
CREATE INDEX releases_vn_vid ON releases_vn (vid);


-- add vnlists table
CREATE TABLE vnlists (
  uid integer NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  vid integer NOT NULL REFERENCES vn (id),
  status smallint NOT NULL DEFAULT 0,
  added TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  notes varchar NOT NULL DEFAULT '',
  PRIMARY KEY(uid, vid)
);


-- load new function(s)
\i util/sql/func.sql


-- convert from rlists.vstat
INSERT INTO vnlists (uid, vid, status, added) SELECT
    i.uid, i.vid, COALESCE(MIN(CASE WHEN rl.vstat = 0 THEN NULL ELSE rl.vstat END), 0), MIN(rl.added)
  FROM (
    SELECT DISTINCT rl.uid, rv.vid
      FROM rlists rl
      JOIN releases r ON r.id = rl.rid
      JOIN releases_vn rv ON rv.rid = r.latest
  ) AS i(uid,vid)
  JOIN rlists rl ON rl.uid = i.uid
  JOIN releases r ON r.id = rl.rid
  JOIN releases_vn rv ON rv.rid = r.latest AND rv.vid = i.vid
  GROUP BY i.uid, i.vid;


-- add constraints triggers
CREATE CONSTRAINT TRIGGER update_vnlist_rlist AFTER DELETE ON vnlists DEFERRABLE FOR EACH ROW EXECUTE PROCEDURE update_vnlist_rlist();
CREATE CONSTRAINT TRIGGER update_vnlist_rlist AFTER INSERT ON rlists  DEFERRABLE FOR EACH ROW EXECUTE PROCEDURE update_vnlist_rlist();

-- remove rlists.vstat and rename rlists.rstat
ALTER TABLE rlists DROP COLUMN vstat;
ALTER TABLE rlists RENAME COLUMN rstat TO status;



-- add users_prefs table
CREATE TYPE prefs_key AS ENUM ('l10n', 'skin', 'customcss', 'show_nsfw', 'hide_list', 'notify_nodbedit', 'notify_announce');
CREATE TABLE users_prefs (
  uid integer NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  key prefs_key NOT NULL,
  value varchar NOT NULL,
  PRIMARY KEY(uid, key)
);

-- convert from users.* to users_prefs
INSERT INTO users_prefs (uid, key, value)
    SELECT id, 'skin'::prefs_key, skin FROM users WHERE skin <> ''
  UNION ALL
    SELECT id, 'customcss', customcss FROM users WHERE customcss <> ''
  UNION ALL
    SELECT id, 'show_nsfw', '1' FROM users WHERE show_nsfw
  UNION ALL
    SELECT id, 'hide_list', '1' FROM users WHERE NOT show_list
  UNION ALL
    SELECT id, 'notify_nodbedit', '1' FROM users WHERE NOT notify_dbedit
  UNION ALL
    SELECT id, 'notify_announce', '1' FROM users WHERE notify_announce;

-- remove unused columns from the user table
ALTER TABLE users DROP COLUMN skin;
ALTER TABLE users DROP COLUMN customcss;
ALTER TABLE users DROP COLUMN show_nsfw;
ALTER TABLE users DROP COLUMN show_list;
ALTER TABLE users DROP COLUMN notify_dbedit;
ALTER TABLE users DROP COLUMN notify_announce;


