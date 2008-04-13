
-- seperate releases_vn table
CREATE TABLE releases_vn (
  rid integer DEFAULT 0 NOT NULL,
  vid integer DEFAULT 0 NOT NULL,
  PRIMARY KEY(rid, vid)
) WITHOUT OIDS;

INSERT INTO releases_vn
  SELECT rr.id AS rid, r.vid AS vid
  FROM releases_rev rr
  JOIN releases r ON rr.rid = r.id;

ALTER TABLE releases DROP COLUMN vid;


ALTER TABLE releases_rev ALTER COLUMN notes TYPE text;
UPDATE producers_rev SET "desc" = '' WHERE "desc" = '0';




-- Update rating calculation
ALTER TABLE vn ALTER COLUMN c_votes TYPE character(10);
ALTER TABLE vn ALTER COLUMN c_votes SET DEFAULT '00.00|0000';

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
       TO_CHAR(CASE WHEN COUNT(uid) < 2 THEN 0 ELSE
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


-- fix update_vncache
DROP FUNCTION update_vncache(integer, integer);
CREATE OR REPLACE FUNCTION update_vncache(id integer) RETURNS void AS $$
DECLARE
  w text := '';
BEGIN
  IF id > 0 THEN
    w := ' WHERE id = '||id;
  END IF;
  EXECUTE 'UPDATE vn SET 
    c_released = COALESCE((SELECT
      SUBSTRING(COALESCE(MIN(rr1.released), ''0000-00'') from 1 for 7)
      FROM releases_rev rr1
      JOIN releases r1 ON rr1.id = r1.latest
      JOIN releases_vn rv1 ON rr1.id = rv1.rid
      WHERE rv1.vid = vn.id
        AND rr1.type <> 2
      GROUP BY rv1.vid
    ), ''0000-00''),
    c_languages = COALESCE(ARRAY_TO_STRING(ARRAY(
      SELECT language
      FROM releases_rev rr2
      JOIN releases r2 ON rr2.id = r2.latest
      JOIN releases_vn rv2 ON rr2.id = rv2.rid
      WHERE rv2.vid = vn.id
        AND rr2.type <> 2
        AND rr2.released <= ''today''::date
      GROUP BY rr2.language
      ORDER BY rr2.language
    ), ''/''), '''')
  '||w;
END;
$$ LANGUAGE plpgsql;
SELECT update_vncache(0);



-- Add comments field to vnlists
ALTER TABLE vnlists ADD COLUMN comments character varying(500) NOT NULL DEFAULT '';

