ALTER TYPE credit_type ADD VALUE 'scenario' BEFORE 'script';


BEGIN;
-- There are no entries in the database where a single aid has both a script
-- and a staff role, and where a note has been associated with the script role.
-- So this conversion does not attempt to merge notes when merging roles.
UPDATE vn_staff vs SET role = 'staff', note = CASE WHEN note = '' THEN 'Scripting' ELSE note END
  WHERE role = 'script' AND NOT EXISTS(SELECT 1 FROM vn_staff v2 where v2.vid = vs.vid AND v2.aid = vs.aid AND role = 'staff');
UPDATE vn_staff vs SET note = CASE WHEN note = '' THEN 'Scripting' ELSE note || ', Scripting' END
  WHERE role = 'staff' AND EXISTS(SELECT 1 FROM vn_staff v2 where v2.vid = vs.vid AND v2.aid = vs.aid AND role = 'script');
DELETE FROM vn_staff WHERE role = 'script';
COMMIT;


-- Some new (or, well, old) platforms
ALTER TYPE platform ADD VALUE 'fmt' BEFORE 'gba';
ALTER TYPE platform ADD VALUE 'pce' BEFORE 'pcf';
ALTER TYPE platform ADD VALUE 'x68' BEFORE 'xb1';

-- New language
ALTER TYPE language ADD VALUE 'ca' BEFORE 'cs';


-- Reorder credit_type (and remove 'script')
ALTER TYPE credit_type RENAME TO credit_type2;
CREATE TYPE credit_type AS ENUM ('scenario', 'chardesign', 'art', 'music', 'songs', 'director', 'staff');
ALTER TABLE vn_staff ALTER role DROP DEFAULT;
ALTER TABLE vn_staff ALTER role TYPE credit_type USING role::text::credit_type;
ALTER TABLE vn_staff ALTER role SET DEFAULT 'staff';
DROP TYPE credit_type2;


-- Staff stat
INSERT INTO stats_cache (section, count) VALUES ('staff', 0);
CREATE TRIGGER stats_cache_new            AFTER  INSERT           ON staff         FOR EACH ROW WHEN (NEW.hidden = FALSE) EXECUTE PROCEDURE update_stats_cache();
CREATE TRIGGER stats_cache_edit           AFTER  UPDATE           ON staff         FOR EACH ROW WHEN (OLD.hidden IS DISTINCT FROM NEW.hidden) EXECUTE PROCEDURE update_stats_cache();
UPDATE stats_cache SET count = (SELECT COUNT(*) FROM staff     WHERE hidden = FALSE) WHERE section = 'staff'


-- New preferences
ALTER TYPE prefs_key ADD VALUE 'tags_all';
ALTER TYPE prefs_key ADD VALUE 'tags_cat';
ALTER TYPE prefs_key ADD VALUE 'spoilers';
ALTER TYPE prefs_key ADD VALUE 'traits_sexual';


-- Convert threads_boards.type to enum
CREATE TYPE board_type        AS ENUM ('an', 'db', 'ge', 'v', 'p', 'u');
ALTER TABLE threads_boards ALTER COLUMN type DROP DEFAULT;
ALTER TABLE threads_boards ALTER COLUMN type TYPE board_type USING trim(type)::board_type;


-- Full-text board search
CREATE OR REPLACE FUNCTION strip_bb_tags(t text) RETURNS text AS $$
  SELECT regexp_replace(t, '\[(?:url=[^\]]+|/?(?:spoiler|quote|raw|code|url))\]', ' ', 'gi');
$$ LANGUAGE sql IMMUTABLE;

CREATE INDEX threads_posts_ts ON threads_posts USING gin(to_tsvector('english', strip_bb_tags(msg)));

-- BUG: Since this isn't a full bbcode parser, [spoiler] tags inside [raw] or [code] are still considered spoilers.
CREATE OR REPLACE FUNCTION strip_spoilers(t text) RETURNS text AS $$
  -- The website doesn't require the [spoiler] tag to be closed, the outer replace catches that case.
  SELECT regexp_replace(regexp_replace(t, '\[spoiler\].*?\[/spoiler\]', ' ', 'ig'), '\[spoiler\].*', ' ', 'i');
$$ LANGUAGE sql IMMUTABLE;


-- Changes to search normalization
UPDATE vn SET c_search = NULL;


-- Convert producers_rev.type to enum
CREATE TYPE producer_type     AS ENUM ('co', 'in', 'ng');
ALTER TABLE producers_rev ALTER COLUMN type DROP DEFAULT;
ALTER TABLE producers_rev ALTER COLUMN type TYPE producer_type USING type::producer_type;
ALTER TABLE producers_rev ALTER COLUMN type SET DEFAULT 'co';


-- Extra index
CREATE INDEX notifications_uid ON notifications (uid);
