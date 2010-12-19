
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
  PRIMARY KEY(uid, vid)
);


-- load new function(s)
\i util/sql/func.sql


-- convert from rlists.vstat
INSERT INTO vnlists SELECT
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

