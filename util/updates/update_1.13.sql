


-- why did we still have this column?
ALTER TABLE releases_rev DROP COLUMN relation;




-- fix update_prev
CREATE OR REPLACE FUNCTION update_prev(tbl text, ids text) RETURNS void AS $$
DECLARE
  r RECORD;
  r2 RECORD;
  i integer;
  t text;
  e text;
BEGIN
  SELECT INTO t SUBSTRING(tbl, 1, 1);
  e := '';
  IF ids <> '' THEN
    e := ' WHERE id IN('||ids||')';
  END IF;
  FOR r IN EXECUTE 'SELECT id FROM '||tbl||e LOOP
    i := 0;
    FOR r2 IN EXECUTE 'SELECT id FROM '||tbl||'_rev WHERE '||t||'id = '||r.id||' ORDER BY id ASC' LOOP
      UPDATE changes SET prev = i WHERE id = r2.id;
      i := r2.id;
    END LOOP;
  END LOOP;
END;
$$ LANGUAGE plpgsql;
SELECT update_prev('vn',''), update_prev('releases',''), update_prev('producers','');




-- change votes treshold to 3
CREATE OR REPLACE FUNCTION calculate_rating() RETURNS void AS $$
DECLARE
  av RECORD;
BEGIN
  SELECT INTO av
     COUNT(vote)::real / COUNT(DISTINCT vid)::real AS num_votes,
     AVG(vote)::real AS rating
    FROM votes;
  
  UPDATE vn
    SET c_votes = COALESCE((SELECT
       TO_CHAR(CASE WHEN COUNT(uid) < 3 THEN 0 ELSE
        ( (av.num_votes * av.rating) + SUM(vote)::real ) / (av.num_votes + COUNT(uid)::real ) END,
        'FM00D00'
       )||'|'||TO_CHAR(
        COUNT(votes.vote), 'FM0000'
       )
      FROM votes
      WHERE votes.vid = vn.id
      GROUP BY votes.vid
    ), '00.00|0000');
END
$$ LANGUAGE plpgsql;
SELECT calculate_rating();




-- store release dates as integers
ALTER TABLE releases_rev ALTER COLUMN released TYPE integer USING REPLACE(released, '-', '')::integer;
UPDATE releases_rev SET released = 0 WHERE released IS NULL;
ALTER TABLE releases_rev ALTER COLUMN released SET NOT NULL;

ALTER TABLE vn ALTER COLUMN c_released SET DEFAULT 0;
ALTER TABLE vn ALTER COLUMN c_released TYPE integer USING 0;
CREATE OR REPLACE FUNCTION update_vncache(id integer) RETURNS void AS $$
DECLARE
  w text := '';
BEGIN
  IF id > 0 THEN
    w := ' WHERE id = '||id;
  END IF;
  EXECUTE 'UPDATE vn SET 
    c_released = COALESCE((SELECT
      MIN(rr1.released)
      FROM releases_rev rr1
      JOIN releases r1 ON rr1.id = r1.latest
      JOIN releases_vn rv1 ON rr1.id = rv1.rid
      WHERE rv1.vid = vn.id
        AND rr1.type <> 2
        AND rr1.released <> 0
      GROUP BY rv1.vid
    ), 0),
    c_languages = COALESCE(ARRAY_TO_STRING(ARRAY(
      SELECT language
      FROM releases_rev rr2
      JOIN releases r2 ON rr2.id = r2.latest
      JOIN releases_vn rv2 ON rr2.id = rv2.rid
      WHERE rv2.vid = vn.id
        AND rr2.type <> 2
        AND rr2.released <= TO_CHAR(''today''::timestamp, ''YYYYMMDD'')::integer
      GROUP BY rr2.language
      ORDER BY rr2.language
    ), ''/''), '''')
  '||w;
END;
$$ LANGUAGE plpgsql;
SELECT update_vncache(0);




-- Rewrite category system
CREATE TABLE vn_categories (
  vid integer NOT NULL DEFAULT 0,
  cat char(3) NOT NULL DEFAULT '',
  lvl smallint NOT NULL DEFAULT 3,
  PRIMARY KEY(vid, cat)
) WITHOUT OIDS;

INSERT INTO vn_categories (vid, cat, lvl) SELECT id, 'gaa', 1 FROM vn_rev WHERE (categories & (1<<0)) > 0;
INSERT INTO vn_categories (vid, cat, lvl) SELECT id, 'gab', 1 FROM vn_rev WHERE (categories & (1<<1)) > 0;
INSERT INTO vn_categories (vid, cat, lvl) SELECT id, 'gac', 3 FROM vn_rev WHERE (categories & (1<<2)) > 0;
INSERT INTO vn_categories (vid, cat, lvl) SELECT id, 'grp', 3 FROM vn_rev WHERE (categories & (1<<3)) > 0;
INSERT INTO vn_categories (vid, cat, lvl) SELECT id, 'gst', 3 FROM vn_rev WHERE (categories & (1<<4)) > 0;
INSERT INTO vn_categories (vid, cat, lvl) SELECT id, 'gsi', 3 FROM vn_rev WHERE (categories & (1<<5)) > 0;
INSERT INTO vn_categories (vid, cat, lvl) SELECT id, 'pli', 1 FROM vn_rev WHERE (categories & (1<<6)) > 0;
INSERT INTO vn_categories (vid, cat, lvl) SELECT id, 'pbr', 1 FROM vn_rev WHERE (categories & (1<<7)) > 0;
INSERT INTO vn_categories (vid, cat, lvl) SELECT id, 'eac', 3 FROM vn_rev WHERE (categories & (1<<8)) > 0;
INSERT INTO vn_categories (vid, cat, lvl) SELECT id, 'eco', 3 FROM vn_rev WHERE (categories & (1<<9)) > 0;
INSERT INTO vn_categories (vid, cat, lvl) SELECT id, 'edr', 3 FROM vn_rev WHERE (categories & (1<<10)) > 0;
INSERT INTO vn_categories (vid, cat, lvl) SELECT id, 'efa', 3 FROM vn_rev WHERE (categories & (1<<11)) > 0;
INSERT INTO vn_categories (vid, cat, lvl) SELECT id, 'eho', 3 FROM vn_rev WHERE (categories & (1<<12)) > 0;
INSERT INTO vn_categories (vid, cat, lvl) SELECT id, 'emy', 3 FROM vn_rev WHERE (categories & (1<<13)) > 0;
INSERT INTO vn_categories (vid, cat, lvl) SELECT id, 'ero', 3 FROM vn_rev WHERE (categories & (1<<14)) > 0;
INSERT INTO vn_categories (vid, cat, lvl) SELECT id, 'esf', 3 FROM vn_rev WHERE (categories & (1<<15)) > 0;
INSERT INTO vn_categories (vid, cat, lvl) SELECT id, 'esj', 3 FROM vn_rev WHERE (categories & (1<<16)) > 0;
INSERT INTO vn_categories (vid, cat, lvl) SELECT id, 'esn', 3 FROM vn_rev WHERE (categories & (1<<17)) > 0;
INSERT INTO vn_categories (vid, cat, lvl) SELECT id, 'tfu', 3 FROM vn_rev WHERE (categories & (1<<18)) > 0;
INSERT INTO vn_categories (vid, cat, lvl) SELECT id, 'tpa', 3 FROM vn_rev WHERE (categories & (1<<19)) > 0;
INSERT INTO vn_categories (vid, cat, lvl) SELECT id, 'tpr', 3 FROM vn_rev WHERE (categories & (1<<20)) > 0;
INSERT INTO vn_categories (vid, cat, lvl) SELECT id, 'lea', 3 FROM vn_rev WHERE (categories & (1<<21)) > 0;
INSERT INTO vn_categories (vid, cat, lvl) SELECT id, 'lfa', 3 FROM vn_rev WHERE (categories & (1<<22)) > 0;
INSERT INTO vn_categories (vid, cat, lvl) SELECT id, 'lsp', 3 FROM vn_rev WHERE (categories & (1<<23)) > 0;
INSERT INTO vn_categories (vid, cat, lvl) SELECT id, 'saa', 3 FROM vn_rev WHERE (categories & (1<<24)) > 0;
INSERT INTO vn_categories (vid, cat, lvl) SELECT id, 'sbe', 3 FROM vn_rev WHERE (categories & (1<<25)) > 0;
INSERT INTO vn_categories (vid, cat, lvl) SELECT id, 'sin', 3 FROM vn_rev WHERE (categories & (1<<26)) > 0;
INSERT INTO vn_categories (vid, cat, lvl) SELECT id, 'slo', 3 FROM vn_rev WHERE (categories & (1<<27)) > 0;
INSERT INTO vn_categories (vid, cat, lvl) SELECT id, 'ssh', 3 FROM vn_rev WHERE (categories & (1<<28)) > 0;
INSERT INTO vn_categories (vid, cat, lvl) SELECT id, 'sya', 3 FROM vn_rev WHERE (categories & (1<<29)) > 0;
INSERT INTO vn_categories (vid, cat, lvl) SELECT id, 'syu', 3 FROM vn_rev WHERE (categories & (1<<30)) > 0;
INSERT INTO vn_categories (vid, cat, lvl) SELECT id, 'sra', 3 FROM vn_rev WHERE (categories & (1<<31)) < 0; -- MSB, mind you!
ALTER TABLE vn_rev DROP COLUMN categories;



-- Remove all previously defined constraints
ALTER TABLE releases_rev       DROP CONSTRAINT releases_rev_id_fkey;
ALTER TABLE releases_rev       DROP CONSTRAINT releases_rev_rid_fkey;
ALTER TABLE releases           DROP CONSTRAINT releases_latest_fkey;
ALTER TABLE releases_vn        DROP CONSTRAINT releases_vn_rid_fkey;
ALTER TABLE releases_vn        DROP CONSTRAINT releases_vn_vid_fkey;
ALTER TABLE releases_platforms DROP CONSTRAINT releases_platforms_rid_fkey;
ALTER TABLE releases_media     DROP CONSTRAINT releases_media_rid_fkey;
ALTER TABLE releases_producers DROP CONSTRAINT releases_producers_rid_fkey;
ALTER TABLE releases_producers DROP CONSTRAINT releases_producers_pid_fkey;

ALTER TABLE vn_rev             DROP CONSTRAINT vn_rev_id_fkey;
ALTER TABLE vn_rev             DROP CONSTRAINT vn_rev_vid_fkey;
ALTER TABLE vn                 DROP CONSTRAINT vn_latest_fkey;
ALTER TABLE vn_relations       DROP CONSTRAINT vn_relations_vid1_fkey;
ALTER TABLE vn_relations       DROP CONSTRAINT vn_relations_vid2_fkey;

ALTER TABLE changes            DROP CONSTRAINT changes_requester_fkey;
ALTER TABLE votes              DROP CONSTRAINT votes_uid_fkey;
ALTER TABLE votes              DROP CONSTRAINT votes_vid_fkey;
ALTER TABLE vnlists            DROP CONSTRAINT vnlists_uid_fkey;
ALTER TABLE vnlists            DROP CONSTRAINT vnlists_vid_fkey;


-- And re-add them... LOLZ
ALTER TABLE releases_rev       ADD FOREIGN KEY (id)        REFERENCES changes       (id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE releases_rev       ADD FOREIGN KEY (rid)       REFERENCES releases      (id) DEFERRABLE INITIALLY DEFERRED;
--ALTER TABLE releases_rev       ADD FOREIGN KEY (id, NULL)  REFERENCES releases_vn (rid, vid) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE releases           ADD FOREIGN KEY (latest)    REFERENCES releases_rev  (id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE releases_vn        ADD FOREIGN KEY (rid)       REFERENCES releases_rev  (id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE releases_vn        ADD FOREIGN KEY (vid)       REFERENCES vn            (id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE releases_platforms ADD FOREIGN KEY (rid)       REFERENCES releases_rev  (id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE releases_media     ADD FOREIGN KEY (rid)       REFERENCES releases_rev  (id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE releases_producers ADD FOREIGN KEY (rid)       REFERENCES releases_rev  (id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE releases_producers ADD FOREIGN KEY (pid)       REFERENCES producers     (id) DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE vn_rev             ADD FOREIGN KEY (id)        REFERENCES changes       (id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE vn_rev             ADD FOREIGN KEY (vid)       REFERENCES vn            (id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE vn                 ADD FOREIGN KEY (latest)    REFERENCES vn_rev        (id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE vn_categories      ADD FOREIGN KEY (vid)       REFERENCES vn_rev        (id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE vn_relations       ADD FOREIGN KEY (vid1)      REFERENCES vn_rev        (id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE vn_relations       ADD FOREIGN KEY (vid2)      REFERENCES vn            (id) DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE producers_rev      ADD FOREIGN KEY (id)        REFERENCES changes       (id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE producers_rev      ADD FOREIGN KEY (pid)       REFERENCES producers     (id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE producers          ADD FOREIGN KEY (latest)    REFERENCES producers_rev (id) DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE changes            ADD FOREIGN KEY (requester) REFERENCES users         (id) DEFERRABLE INITIALLY DEFERRED;-- ON DELETE SET DEFAULT
ALTER TABLE votes              ADD FOREIGN KEY (uid)       REFERENCES users         (id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE votes              ADD FOREIGN KEY (vid)       REFERENCES vn            (id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE vnlists            ADD FOREIGN KEY (uid)       REFERENCES users         (id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE vnlists            ADD FOREIGN KEY (vid)       REFERENCES vn            (id) DEFERRABLE INITIALLY DEFERRED;


--ALTER TABLE releases_rev ADD COLUMN ref_vid_hack integer NULL DEFAULT NULL;
--ALTER TABLE releases_rev ADD FOREIGN KEY (id, ref_vid_hack) REFERENCES releases_vn (rid, vid) ON DELETE CASCADE;

-- TODO:
--  - make sure that changes.id should always refer to a row in *_rev
--  - make sure that there is always at least one row in releases_vn for every releases_rev

-- deletion of items in *_rev should trigger deletion in changes
--CREATE OR REPLACE FUNCTION changes_reference_del() RETURNS trigger AS $$
--BEGIN
--  DELETE FROM changes WHERE id = OLD.id;
--END
--$$ LANGUAGE PLPGSQL;

--CREATE TRIGGER vn_rev_cdel        AFTER DELETE ON vn_rev        FOR EACH ROW EXECUTE PROCEDURE changes_reference_del();
--CREATE TRIGGER releases_rev_cdel  AFTER DELETE ON releases_rev  FOR EACH ROW EXECUTE PROCEDURE changes_reference_del();
--CREATE TRIGGER producers_rev_cdel AFTER DELETE ON producers_rev FOR EACH ROW EXECUTE PROCEDURE changes_reference_del();




