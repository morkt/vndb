
-- empty nfo_id
UPDATE anime SET nfo_id = '' WHERE nfo_id = '0,';


-- future release dates
UPDATE releases_rev
   SET released = (SUBSTRING(released::text, 1, 4)||'9999')::integer
 WHERE SUBSTRING(released::text, 5, 4) = '0000';

UPDATE releases_rev
   SET released = (SUBSTRING(released::text, 1, 6)||'99')::integer
 WHERE SUBSTRING(released::text, 7, 4) = '00';



-- all platforms are three-letters now
UPDATE releases_platforms SET platform = 'ps1' WHERE platform = 'ps ';
UPDATE releases_platforms SET platform = 'drc' WHERE platform = 'dc ';



-- cache platforms
ALTER TABLE vn ADD COLUMN c_platforms varchar(32) NOT NULL DEFAULT '';

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
        AND r1.hidden = 0
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
        AND r2.hidden = 0
      GROUP BY rr2.language
      ORDER BY rr2.language
    ), ''/''), ''''),
    c_platforms = COALESCE(ARRAY_TO_STRING(ARRAY(
      SELECT rp3.platform
      FROM releases_platforms rp3
      JOIN releases_rev rr3 ON rp3.rid = rr3.id
      JOIN releases r3 ON rp3.rid = r3.latest
      JOIN releases_vn rv3 ON rp3.rid = rv3.rid
      WHERE rv3.vid = vn.id
        AND rr3.type <> 2
        AND rr3.released <= TO_CHAR(''today''::timestamp, ''YYYYMMDD'')::integer
        AND r3.hidden = 0
      GROUP BY rp3.platform
      ORDER BY rp3.platform
    ), ''/''), '''')
  '||w;
END;
$$ LANGUAGE plpgsql;

SELECT update_vncache(0);
