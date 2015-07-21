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

