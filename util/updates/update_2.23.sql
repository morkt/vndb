-- Two extra indices for performance

CREATE INDEX releases_producers_rid ON releases_producers (rid);
CREATE INDEX tags_vn_vid ON tags_vn (vid);



-- Extra language for Arabic, Hebrew, Ukrainian and Indonesian

ALTER TYPE language RENAME TO language_old;
CREATE TYPE language AS ENUM ('ar', 'cs', 'da', 'de', 'en', 'es', 'fi', 'fr', 'he', 'hu', 'id', 'it', 'ja', 'ko', 'nl', 'no', 'pl', 'pt-pt', 'pt-br', 'ru', 'sk', 'sv', 'tr', 'uk', 'vi', 'zh');
ALTER TABLE producers_rev ALTER COLUMN lang DROP DEFAULT;
ALTER TABLE producers_rev ALTER COLUMN lang TYPE language USING lang::text::language;
ALTER TABLE producers_rev ALTER COLUMN lang SET DEFAULT 'ja';

ALTER TABLE releases_lang ALTER COLUMN lang TYPE language USING lang::text::language;

ALTER TABLE vn ALTER COLUMN c_languages DROP DEFAULT;
DROP TRIGGER vn_relgraph_notify ON vn;
ALTER TABLE vn ALTER COLUMN c_languages TYPE language[] USING c_languages::text[]::language[];
CREATE TRIGGER vn_relgraph_notify AFTER UPDATE ON vn FOR EACH ROW
  WHEN (OLD.rgraph      IS DISTINCT FROM NEW.rgraph
     OR OLD.latest      IS DISTINCT FROM NEW.latest
     OR OLD.c_released  IS DISTINCT FROM NEW.c_released
     OR OLD.c_languages IS DISTINCT FROM NEW.c_languages
  ) EXECUTE PROCEDURE vn_relgraph_notify();
ALTER TABLE vn ALTER COLUMN c_languages SET DEFAULT '{}';

ALTER TABLE vn ALTER COLUMN c_olang DROP DEFAULT;
ALTER TABLE vn ALTER COLUMN c_olang TYPE language[] USING c_olang::text[]::language[];
ALTER TABLE vn ALTER COLUMN c_olang SET DEFAULT '{}';

DROP TYPE language_old;



-- VN votes * 10
-- (The WHERE prevents another *10 if this query has already been executed)

UPDATE votes SET vote = vote * 10 WHERE NOT EXISTS(SELECT 1 FROM votes WHERE vote > 10);

-- recalculate c_rating
UPDATE vn SET c_rating = (SELECT (
    ((SELECT COUNT(vote)::real/COUNT(DISTINCT vid)::real FROM votes)
      *(SELECT AVG(a)::real FROM (SELECT AVG(vote) FROM votes GROUP BY vid) AS v(a)) + SUM(vote)::real) /
    ((SELECT COUNT(vote)::real/COUNT(DISTINCT vid)::real FROM votes) + COUNT(uid)::real)
  ) FROM votes WHERE vid = id AND uid NOT IN(SELECT id FROM users WHERE ign_votes)
);


-- New enum types for user list display in VN list

ALTER TYPE prefs_key ADD VALUE 'vn_list_own'  AFTER 'notify_announce';
ALTER TYPE prefs_key ADD VALUE 'vn_list_wish' AFTER 'vn_list_own';


-- Image processing doesn't happen via Multi anymore, so no more notifications

DROP TRIGGER vn_rev_image_notify ON vn_rev;
DROP FUNCTION vn_rev_image_notify();

DROP TRIGGER chars_rev_image_notify ON chars_rev;
DROP FUNCTION chars_rev_image_notify();

DROP TRIGGER screenshot_process_notify ON screenshots;
DROP FUNCTION screenshot_process_notify();

ALTER TABLE screenshots DROP COLUMN processed;


-- New resolution has been added at index 8
UPDATE releases_rev SET resolution = resolution + 1 WHERE resolution >= 8 AND NOT EXISTS(SELECT 1 FROM releases_rev WHERE resolution >= 14);

-- New language: Romanian
ALTER TYPE language ADD VALUE 'ro' AFTER 'pt-br';

-- Login attempt throttling
CREATE TABLE login_throttle (
  ip inet NOT NULL PRIMARY KEY,
  timeout bigint NOT NULL
);

-- timeout is a timestamp...
ALTER TABLE login_throttle ALTER COLUMN timeout TYPE timestamptz USING to_timestamp(timeout);


-- platform from varchar to enum
CREATE TYPE platform AS ENUM ('win', 'dos', 'lin', 'mac', 'ios', 'and', 'dvd', 'bdp', 'gba', 'gbc', 'msx', 'nds', 'nes', 'p88', 'p98', 'pcf', 'psp', 'ps1', 'ps2', 'ps3', 'ps4', 'psv', 'drc', 'sat', 'sfc', 'wii', 'n3d', 'xb1', 'xb3', 'xbo', 'web', 'oth');
ALTER TABLE releases_platforms ALTER COLUMN platform DROP DEFAULT;
ALTER TABLE releases_platforms ALTER COLUMN platform TYPE platform USING platform::platform;

ALTER TABLE vn ALTER COLUMN c_platforms DROP DEFAULT;
ALTER TABLE vn ALTER COLUMN c_platforms TYPE platform[] USING string_to_array(c_platforms, '/')::platform[];
ALTER TABLE vn ALTER COLUMN c_platforms SET DEFAULT '{}';


-- Merging passwd and salt
--SELECT length(passwd), count(*) from users group by length(passwd);
UPDATE users SET passwd = convert_to(salt, 'UTF-8') || passwd;
ALTER TABLE users DROP COLUMN salt;
