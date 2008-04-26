

-- drop get_new_id()
CREATE SEQUENCE vn_id_seq OWNED BY vn.id;
SELECT setval('vn_id_seq', get_new_id('vn')-1);
ALTER TABLE vn ALTER COLUMN id SET DEFAULT nextval('vn_id_seq');

CREATE SEQUENCE releases_id_seq OWNED BY releases.id;
SELECT setval('releases_id_seq', get_new_id('releases')-1);
ALTER TABLE releases ALTER COLUMN id SET DEFAULT nextval('releases_id_seq');

CREATE SEQUENCE producers_id_seq OWNED BY producers.id;
SELECT setval('producers_id_seq', get_new_id('producers')-1);
ALTER TABLE producers ALTER COLUMN id SET DEFAULT nextval('producers_id_seq');

DROP FUNCTION get_new_id(text);



-- remove users.p* columns (Why haven't I done so earlier?)
ALTER TABLE users DROP COLUMN pvotes;
ALTER TABLE users DROP COLUMN pfind;
ALTER TABLE users DROP COLUMN plist;
ALTER TABLE users DROP COLUMN pign_nsfw;



-- relation graphs get ID numbers
CREATE SEQUENCE relgraph_seq;
ALTER TABLE vn ALTER COLUMN rgraph DROP NOT NULL;
ALTER TABLE vn ALTER COLUMN rgraph DROP DEFAULT;
ALTER TABLE vn ALTER COLUMN rgraph TYPE integer USING 0;
ALTER TABLE vn ALTER COLUMN rgraph SET DEFAULT 0;
ALTER TABLE vn ALTER COLUMN rgraph SET NOT NULL;


-- cover images get ID numbers as well
-- (handled in update_1.14.pl)



-- 'hidden' flag to all items in the DB
ALTER TABLE vn ADD COLUMN hidden smallint NOT NULL DEFAULT 0;
ALTER TABLE producers ADD COLUMN hidden smallint NOT NULL DEFAULT 0;
ALTER TABLE releases ADD COLUMN hidden smallint NOT NULL DEFAULT 0;


-- update update_vncache to handle the hidden flag
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
    ), ''/''), '''')
  '||w;
END;
$$ LANGUAGE plpgsql;
SELECT update_vncache(0);

