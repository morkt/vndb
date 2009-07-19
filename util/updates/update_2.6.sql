

-- The anime table:
--  - use timestamp data type for anime.lastfetch
--  - allow NULL for all columns except id
ALTER TABLE anime ALTER COLUMN lastfetch DROP NOT NULL;
ALTER TABLE anime ALTER COLUMN lastfetch DROP DEFAULT;
UPDATE anime SET lastfetch = NULL WHERE lastfetch <= 0;
ALTER TABLE anime ALTER COLUMN lastfetch TYPE timestamp USING timestamp 'epoch' + lastfetch * interval '1 second';

ALTER TABLE anime ALTER COLUMN ann_id DROP NOT NULL;
ALTER TABLE anime ALTER COLUMN ann_id DROP DEFAULT;
UPDATE anime SET ann_id = NULL WHERE ann_id = 0;

ALTER TABLE anime ALTER COLUMN nfo_id DROP NOT NULL;
ALTER TABLE anime ALTER COLUMN nfo_id DROP DEFAULT;
UPDATE anime SET nfo_id = NULL WHERE nfo_id = '';

ALTER TABLE anime ALTER COLUMN title_kanji DROP NOT NULL;
ALTER TABLE anime ALTER COLUMN title_kanji DROP DEFAULT;
UPDATE anime SET title_kanji = NULL WHERE title_kanji = '';

ALTER TABLE anime ALTER COLUMN title_romaji DROP NOT NULL;
ALTER TABLE anime ALTER COLUMN title_romaji DROP DEFAULT;
UPDATE anime SET title_romaji = NULL WHERE title_romaji = '';

ALTER TABLE anime ALTER COLUMN type DROP NOT NULL;
ALTER TABLE anime ALTER COLUMN type DROP DEFAULT;
UPDATE anime SET type = NULL WHERE type = 0;
UPDATE anime SET type = type-1;

ALTER TABLE anime ALTER COLUMN year DROP NOT NULL;
ALTER TABLE anime ALTER COLUMN year DROP DEFAULT;
UPDATE anime SET year = NULL WHERE year = 0;



-- screenshots.status (smallint) -> screenshots.processed (boolean)
ALTER TABLE screenshots RENAME COLUMN status TO processed;
ALTER TABLE screenshots ALTER COLUMN processed DROP DEFAULT;
ALTER TABLE screenshots ALTER COLUMN processed TYPE boolean USING processed::int::boolean;
ALTER TABLE screenshots ALTER COLUMN processed SET DEFAULT FALSE;



-- automatically insert rows into the anime table for unknown aids
--  when inserted into vn_anime
CREATE OR REPLACE FUNCTION vn_anime_aid() RETURNS trigger AS $$
BEGIN
  IF NOT EXISTS(SELECT 1 FROM anime WHERE id = NEW.aid) THEN
    INSERT INTO anime (id) VALUES (NEW.aid);
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER vn_anime_aid BEFORE INSERT OR UPDATE ON vn_anime FOR EACH ROW EXECUTE PROCEDURE vn_anime_aid();


-- Send a notify whenever anime info should be fetched
CREATE OR REPLACE FUNCTION anime_fetch_notify() RETURNS trigger AS $$
BEGIN
  IF NEW.lastfetch IS NULL THEN
    NOTIFY anime;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER anime_fetch_notify AFTER INSERT OR UPDATE ON anime FOR EACH ROW EXECUTE PROCEDURE anime_fetch_notify();



-- Send a notify when a new cover image is uploaded
CREATE OR REPLACE FUNCTION vn_rev_image_notify() RETURNS trigger AS $$
BEGIN
  IF NEW.image < 0 THEN
    NOTIFY coverimage;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER vn_rev_image_notify AFTER INSERT OR UPDATE ON vn_rev FOR EACH ROW EXECUTE PROCEDURE vn_rev_image_notify();

