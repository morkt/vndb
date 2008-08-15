
-- screenshots
CREATE TABLE screenshots (
  id SERIAL NOT NULL PRIMARY KEY,
  status smallint NOT NULL DEFAULT 0, -- 0:unprocessed, 1:processed, <0:error (unimplemented)
  width smallint NOT NULL DEFAULT 0,
  height smallint NOT NULL DEFAULT 0
) WITHOUT OIDS;

CREATE TABLE vn_screenshots (
  vid integer NOT NULL DEFAULT 0 REFERENCES vn_rev      (id) DEFERRABLE INITIALLY DEFERRED,
  scr integer NOT NULL DEFAULT 0 REFERENCES screenshots (id) DEFERRABLE INITIALLY DEFERRED,
  nsfw smallint NOT NULL DEFAULT 0,
  PRIMARY KEY(vid, scr)
) WITHOUT OIDS;



-- PostgreSQL has a boolean type since 8.1, let's convert our smallints...
-- psql -> perl:
--   No changes required, DBD::Pg automatically converts the boolean type to 1 or 0
-- perl -> psql:
--   psql doesn't accept the integers 1 and 0 as boolean,
--   so I added a !b conversion for VNDB::Util::DB::sqlprint()

ALTER TABLE producers ALTER COLUMN locked DROP DEFAULT;
ALTER TABLE producers ALTER COLUMN locked TYPE boolean USING locked::text::boolean;
ALTER TABLE producers ALTER COLUMN locked SET DEFAULT FALSE;
ALTER TABLE producers ALTER COLUMN hidden DROP DEFAULT;
ALTER TABLE producers ALTER COLUMN hidden TYPE boolean USING hidden::text::boolean;
ALTER TABLE producers ALTER COLUMN hidden SET DEFAULT FALSE;

ALTER TABLE releases ALTER COLUMN locked DROP DEFAULT;
ALTER TABLE releases ALTER COLUMN locked TYPE boolean USING locked::text::boolean;
ALTER TABLE releases ALTER COLUMN locked SET DEFAULT FALSE;
ALTER TABLE releases ALTER COLUMN hidden DROP DEFAULT;
ALTER TABLE releases ALTER COLUMN hidden TYPE boolean USING hidden::text::boolean;
ALTER TABLE releases ALTER COLUMN hidden SET DEFAULT FALSE;

ALTER TABLE threads ALTER COLUMN locked DROP DEFAULT;
ALTER TABLE threads ALTER COLUMN locked TYPE boolean USING locked::text::boolean;
ALTER TABLE threads ALTER COLUMN locked SET DEFAULT FALSE;
ALTER TABLE threads ALTER COLUMN hidden DROP DEFAULT;
ALTER TABLE threads ALTER COLUMN hidden TYPE boolean USING hidden::text::boolean;
ALTER TABLE threads ALTER COLUMN hidden SET DEFAULT FALSE;

ALTER TABLE threads_posts ALTER COLUMN hidden DROP DEFAULT;
ALTER TABLE threads_posts ALTER COLUMN hidden TYPE boolean USING hidden::text::boolean;
ALTER TABLE threads_posts ALTER COLUMN hidden SET DEFAULT FALSE;

ALTER TABLE vn ALTER COLUMN locked DROP DEFAULT;
ALTER TABLE vn ALTER COLUMN locked TYPE boolean USING locked::text::boolean;
ALTER TABLE vn ALTER COLUMN locked SET DEFAULT FALSE;
ALTER TABLE vn ALTER COLUMN hidden DROP DEFAULT;
ALTER TABLE vn ALTER COLUMN hidden TYPE boolean USING hidden::text::boolean;
ALTER TABLE vn ALTER COLUMN hidden SET DEFAULT FALSE;

ALTER TABLE vn_rev ALTER COLUMN img_nsfw DROP DEFAULT;
ALTER TABLE vn_rev ALTER COLUMN img_nsfw TYPE boolean USING img_nsfw::text::boolean;
ALTER TABLE vn_rev ALTER COLUMN img_nsfw SET DEFAULT FALSE;

ALTER TABLE vn_screenshots ALTER COLUMN nsfw DROP DEFAULT;
ALTER TABLE vn_screenshots ALTER COLUMN nsfw TYPE boolean USING nsfw::text::boolean;
ALTER TABLE vn_screenshots ALTER COLUMN nsfw SET DEFAULT FALSE;


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
      AND r1.hidden = FALSE
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
      AND r2.hidden = FALSE
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
      AND r3.hidden = FALSE
      GROUP BY rp3.platform
      ORDER BY rp3.platform
    ), ''/''), '''')
  '||w;
END;
$$ LANGUAGE plpgsql;
