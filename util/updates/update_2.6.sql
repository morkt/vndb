

-- Create table for session data storage
CREATE TABLE sessions (
  uid integer NOT NULL REFERENCES users(id),
  token bytea NOT NULL,
  expiration timestamptz NOT NULL DEFAULT (NOW() + '1 year'::interval),
  PRIMARY KEY (uid, token)
);

-- Add column to users for salt storage
ALTER TABLE users ADD COLUMN salt character(9) NOT NULL DEFAULT ''::bpchar;



-- The anime table:
--  - use timestamp data type for anime.lastfetch
--  - allow NULL for all columns except id
ALTER TABLE anime ALTER COLUMN lastfetch DROP NOT NULL;
ALTER TABLE anime ALTER COLUMN lastfetch DROP DEFAULT;
UPDATE anime SET lastfetch = NULL WHERE lastfetch <= 0;
ALTER TABLE anime ALTER COLUMN lastfetch TYPE timestamptz USING to_timestamp(lastfetch);

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


-- rlists.added -> timestamptz
ALTER TABLE rlists ALTER COLUMN added DROP DEFAULT;
ALTER TABLE rlists ALTER COLUMN added TYPE timestamptz USING to_timestamp(added);
ALTER TABLE rlists ALTER COLUMN added SET DEFAULT NOW();


-- wlists.added -> timestamptz
ALTER TABLE wlists ALTER COLUMN added DROP DEFAULT;
ALTER TABLE wlists ALTER COLUMN added TYPE timestamptz USING to_timestamp(added);
ALTER TABLE wlists ALTER COLUMN added SET DEFAULT NOW();


-- threads_posts.date -> timestamptz
ALTER TABLE threads_posts ALTER COLUMN date DROP DEFAULT;
ALTER TABLE threads_posts ALTER COLUMN date TYPE timestamptz USING to_timestamp(date);
ALTER TABLE threads_posts ALTER COLUMN date SET DEFAULT NOW();

-- threads_posts.edited -> timestamptz + allow NULL
ALTER TABLE threads_posts ALTER COLUMN edited DROP NOT NULL;
ALTER TABLE threads_posts ALTER COLUMN edited DROP DEFAULT;
ALTER TABLE threads_posts ALTER COLUMN edited TYPE timestamptz USING CASE WHEN edited = 0 THEN NULL ELSE to_timestamp(edited) END;


-- votes.date -> timestamptz
ALTER TABLE votes ALTER COLUMN date DROP DEFAULT;
ALTER TABLE votes ALTER COLUMN date TYPE timestamptz USING to_timestamp(date);
ALTER TABLE votes ALTER COLUMN date SET DEFAULT NOW();


-- users.registered -> timestamptz
ALTER TABLE users ALTER COLUMN registered DROP DEFAULT;
ALTER TABLE users ALTER COLUMN registered TYPE timestamptz USING to_timestamp(registered);
ALTER TABLE users ALTER COLUMN registered SET DEFAULT NOW();


-- tags.added -> timestamptz
ALTER TABLE tags ALTER COLUMN added DROP DEFAULT;
ALTER TABLE tags ALTER COLUMN added TYPE timestamptz USING to_timestamp(added);
ALTER TABLE tags ALTER COLUMN added SET DEFAULT NOW();


-- screenshots.status (smallint) -> screenshots.processed (boolean)
ALTER TABLE screenshots RENAME COLUMN status TO processed;
ALTER TABLE screenshots ALTER COLUMN processed DROP DEFAULT;
ALTER TABLE screenshots ALTER COLUMN processed TYPE boolean USING processed::int::boolean;
ALTER TABLE screenshots ALTER COLUMN processed SET DEFAULT FALSE;



-- two new resolutions have been added, array indexes have changed
UPDATE releases_rev SET resolution = resolution + 1 WHERE resolution >= 5;
UPDATE releases_rev SET resolution = resolution + 1 WHERE resolution >= 7;



-- remove the DEFERRED attribute on all foreign key checks on which it isn't necessary
-- (note: these queries all assume the foreign keys have their default names, as given
--  by PostgreSQL. This shouldn't be a problem, provided if you haven't touched them.)
ALTER TABLE changes            DROP CONSTRAINT changes_requester_fkey;
ALTER TABLE changes            DROP CONSTRAINT changes_causedby_fkey;
ALTER TABLE producers_rev      DROP CONSTRAINT producers_rev_id_fkey;
ALTER TABLE producers_rev      DROP CONSTRAINT producers_rev_pid_fkey;
ALTER TABLE quotes             DROP CONSTRAINT quotes_vid_fkey;
ALTER TABLE releases_lang      DROP CONSTRAINT releases_lang_rid_fkey;
ALTER TABLE releases_media     DROP CONSTRAINT releases_media_rid_fkey;
ALTER TABLE releases_platforms DROP CONSTRAINT releases_platforms_rid_fkey;
ALTER TABLE releases_producers DROP CONSTRAINT releases_producers_rid_fkey;
ALTER TABLE releases_producers DROP CONSTRAINT releases_producers_pid_fkey;
ALTER TABLE releases_rev       DROP CONSTRAINT releases_rev_id_fkey;
ALTER TABLE releases_rev       DROP CONSTRAINT releases_rev_rid_fkey;
ALTER TABLE releases_vn        DROP CONSTRAINT releases_vn_rid_fkey;
ALTER TABLE releases_vn        DROP CONSTRAINT releases_vn_vid_fkey;
ALTER TABLE rlists             DROP CONSTRAINT rlists_uid_fkey;
ALTER TABLE rlists             DROP CONSTRAINT rlists_rid_fkey;
ALTER TABLE tags               DROP CONSTRAINT tags_addedby_fkey;
ALTER TABLE tags_aliases       DROP CONSTRAINT tags_aliases_tag_fkey;
ALTER TABLE tags_parents       DROP CONSTRAINT tags_parents_tag_fkey;
ALTER TABLE tags_parents       DROP CONSTRAINT tags_parents_parent_fkey;
ALTER TABLE tags_vn            DROP CONSTRAINT tags_vn_tag_fkey;
ALTER TABLE tags_vn            DROP CONSTRAINT tags_vn_vid_fkey;
ALTER TABLE tags_vn            DROP CONSTRAINT tags_vn_uid_fkey;
ALTER TABLE threads_posts      DROP CONSTRAINT threads_posts_tid_fkey;
ALTER TABLE threads_posts      DROP CONSTRAINT threads_posts_uid_fkey;
ALTER TABLE threads_boards     DROP CONSTRAINT threads_tags_tid_fkey; -- threads_boards used to be called threads_tags
ALTER TABLE vn                 DROP CONSTRAINT vn_rgraph_fkey;
ALTER TABLE vn_anime           DROP CONSTRAINT vn_anime_aid_fkey;
ALTER TABLE vn_anime           DROP CONSTRAINT vn_anime_vid_fkey;
ALTER TABLE vn_relations       DROP CONSTRAINT vn_relations_vid1_fkey;
ALTER TABLE vn_relations       DROP CONSTRAINT vn_relations_vid2_fkey;
ALTER TABLE vn_rev             DROP CONSTRAINT vn_rev_id_fkey;
ALTER TABLE vn_rev             DROP CONSTRAINT vn_rev_vid_fkey;
ALTER TABLE vn_screenshots     DROP CONSTRAINT vn_screenshots_vid_fkey;
ALTER TABLE vn_screenshots     DROP CONSTRAINT vn_screenshots_scr_fkey;
ALTER TABLE vn_screenshots     DROP CONSTRAINT vn_screenshots_rid_fkey;
ALTER TABLE votes              DROP CONSTRAINT votes_uid_fkey;
ALTER TABLE votes              DROP CONSTRAINT votes_vid_fkey;
ALTER TABLE wlists             DROP CONSTRAINT wlists_uid_fkey;
ALTER TABLE wlists             DROP CONSTRAINT wlists_vid_fkey;

ALTER TABLE changes            ADD FOREIGN KEY (requester) REFERENCES users         (id);
ALTER TABLE changes            ADD FOREIGN KEY (causedby)  REFERENCES changes       (id);
ALTER TABLE producers_rev      ADD FOREIGN KEY (id)        REFERENCES changes       (id);
ALTER TABLE producers_rev      ADD FOREIGN KEY (pid)       REFERENCES producers     (id);
ALTER TABLE quotes             ADD FOREIGN KEY (vid)       REFERENCES vn            (id);
ALTER TABLE releases_lang      ADD FOREIGN KEY (rid)       REFERENCES releases_rev  (id);
ALTER TABLE releases_media     ADD FOREIGN KEY (rid)       REFERENCES releases_rev  (id);
ALTER TABLE releases_platforms ADD FOREIGN KEY (rid)       REFERENCES releases_rev  (id);
ALTER TABLE releases_producers ADD FOREIGN KEY (rid)       REFERENCES releases_rev  (id);
ALTER TABLE releases_producers ADD FOREIGN KEY (pid)       REFERENCES producers     (id);
ALTER TABLE releases_rev       ADD FOREIGN KEY (id)        REFERENCES changes       (id);
ALTER TABLE releases_rev       ADD FOREIGN KEY (rid)       REFERENCES releases      (id);
ALTER TABLE releases_vn        ADD FOREIGN KEY (rid)       REFERENCES releases_rev  (id);
ALTER TABLE releases_vn        ADD FOREIGN KEY (vid)       REFERENCES vn            (id);
ALTER TABLE rlists             ADD FOREIGN KEY (uid)       REFERENCES users         (id);
ALTER TABLE rlists             ADD FOREIGN KEY (rid)       REFERENCES releases      (id);
ALTER TABLE tags               ADD FOREIGN KEY (addedby)   REFERENCES users         (id);
ALTER TABLE tags_aliases       ADD FOREIGN KEY (tag)       REFERENCES tags          (id);
ALTER TABLE tags_parents       ADD FOREIGN KEY (tag)       REFERENCES tags          (id);
ALTER TABLE tags_parents       ADD FOREIGN KEY (parent)    REFERENCES tags          (id);
ALTER TABLE tags_vn            ADD FOREIGN KEY (tag)       REFERENCES tags          (id);
ALTER TABLE tags_vn            ADD FOREIGN KEY (vid)       REFERENCES vn            (id);
ALTER TABLE tags_vn            ADD FOREIGN KEY (uid)       REFERENCES users         (id);
ALTER TABLE threads_posts      ADD FOREIGN KEY (tid)       REFERENCES threads       (id);
ALTER TABLE threads_posts      ADD FOREIGN KEY (uid)       REFERENCES users         (id);
ALTER TABLE threads_boards     ADD FOREIGN KEY (tid)       REFERENCES threads       (id);
ALTER TABLE vn                 ADD FOREIGN KEY (rgraph)    REFERENCES relgraph      (id);
ALTER TABLE vn_anime           ADD FOREIGN KEY (aid)       REFERENCES anime         (id);
ALTER TABLE vn_anime           ADD FOREIGN KEY (vid)       REFERENCES vn_rev        (id);
ALTER TABLE vn_relations       ADD FOREIGN KEY (vid1)      REFERENCES vn_rev        (id);
ALTER TABLE vn_relations       ADD FOREIGN KEY (vid2)      REFERENCES vn            (id);
ALTER TABLE vn_rev             ADD FOREIGN KEY (id)        REFERENCES changes       (id);
ALTER TABLE vn_rev             ADD FOREIGN KEY (vid)       REFERENCES vn            (id);
ALTER TABLE vn_screenshots     ADD FOREIGN KEY (vid)       REFERENCES vn_rev        (id);
ALTER TABLE vn_screenshots     ADD FOREIGN KEY (scr)       REFERENCES screenshots   (id);
ALTER TABLE vn_screenshots     ADD FOREIGN KEY (rid)       REFERENCES releases      (id);
ALTER TABLE votes              ADD FOREIGN KEY (uid)       REFERENCES users         (id);
ALTER TABLE votes              ADD FOREIGN KEY (vid)       REFERENCES vn            (id);
ALTER TABLE wlists             ADD FOREIGN KEY (uid)       REFERENCES users         (id);
ALTER TABLE wlists             ADD FOREIGN KEY (vid)       REFERENCES vn            (id);



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


-- Send a notify when a screenshot needs to be processed
CREATE OR REPLACE FUNCTION screenshot_process_notify() RETURNS trigger AS $$
BEGIN
  IF NEW.processed = FALSE THEN
    NOTIFY screenshot;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER screenshot_process_notify AFTER INSERT OR UPDATE ON screenshots FOR EACH ROW EXECUTE PROCEDURE screenshot_process_notify();


-- Update vn.rgraph column and send notify when a relation graph needs to be regenerated
-- 1. NOTIFY is sent on an UPDATE or INSERT on vn with rgraph = NULL and with entries in vn_relations (deferred)
-- vn.rgraph is set to NULL when:
-- 2. UPDATE on vn where c_released or c_languages has changed (deferred, but doesn't have to be)
-- 3. New VN revision of which the title differs from previous revision (deferred)
-- 4. New VN revision with items in vn_relations that differ from previous revision (deferred)
CREATE OR REPLACE FUNCTION vn_relgraph_notify() RETURNS trigger AS $$
BEGIN
  -- 1.
  IF TG_TABLE_NAME = 'vn' THEN
    IF NEW.rgraph IS NULL AND EXISTS(SELECT 1 FROM vn_relations WHERE vid1 = NEW.latest) THEN
      NOTIFY relgraph;
    END IF;
  END IF;
  IF TG_TABLE_NAME = 'vn' AND TG_OP = 'UPDATE' THEN
    IF NEW.rgraph IS NOT NULL AND OLD.latest > 0 THEN
      -- 2.
      IF OLD.c_released <> NEW.c_released OR OLD.c_languages <> NEW.c_languages THEN
        UPDATE vn SET rgraph = NULL WHERE id = NEW.id;
      END IF;
      -- 3 & 4
      IF OLD.latest <> NEW.latest AND (
           EXISTS(SELECT 1 FROM vn_rev v1, vn_rev v2 WHERE v2.title <> v1.title AND v1.id = OLD.latest AND v2.id = NEW.latest)
        OR EXISTS(SELECT v1.vid2, v1.relation FROM vn_relations v1 WHERE v1.vid1 = OLD.latest EXCEPT SELECT v2.vid2, v2.relation FROM vn_relations v2 WHERE v2.vid1 = NEW.latest)
        OR EXISTS(SELECT v1.vid2, v1.relation FROM vn_relations v1 WHERE v1.vid1 = NEW.latest EXCEPT SELECT v2.vid2, v2.relation FROM vn_relations v2 WHERE v2.vid1 = OLD.latest)
      ) THEN
        UPDATE vn SET rgraph = NULL WHERE id = NEW.id;
      END IF;
    END IF;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE CONSTRAINT TRIGGER vn_relgraph_notify AFTER INSERT OR UPDATE ON vn DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE PROCEDURE vn_relgraph_notify();


-- NOTIFY on insert into changes/posts/tags
CREATE OR REPLACE FUNCTION insert_notify() RETURNS trigger AS $$
BEGIN
  IF TG_TABLE_NAME = 'changes' THEN
    NOTIFY newrevision;
  ELSIF TG_TABLE_NAME = 'threads_posts' THEN
    NOTIFY newpost;
  ELSIF TG_TABLE_NAME = 'tags' THEN
    NOTIFY newtag;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER insert_notify AFTER INSERT ON changes FOR EACH STATEMENT EXECUTE PROCEDURE insert_notify();
CREATE TRIGGER insert_notify AFTER INSERT ON threads_posts FOR EACH STATEMENT EXECUTE PROCEDURE insert_notify();
CREATE TRIGGER insert_notify AFTER INSERT ON tags FOR EACH STATEMENT EXECUTE PROCEDURE insert_notify();



-- convert the old categories to the related tags for VNs that didn't have tags already
INSERT INTO tags_vn (uid, spoiler, vid, vote, tag)
  SELECT 1, 0, v.id,
    CASE
      WHEN vc.cat IN('gaa', 'gab', 'pli', 'pbr', 'tfu', 'tpa', 'tpr', 'lea', 'lfa', 'lsp', 'hfa', 'hfe') THEN 2
      ELSE vc.lvl
    END,
    CASE
      WHEN vc.cat = 'gaa' THEN  43 -- NVL
      WHEN vc.cat = 'gab' THEN  32 -- ADV
      WHEN vc.cat = 'gac' THEN  31 -- Action game
      WHEN vc.cat = 'grp' THEN  35 -- RPG
      WHEN vc.cat = 'gst' THEN  33 -- Strategy game
      WHEN vc.cat = 'gsi' THEN  34 -- Simulation game
      WHEN vc.cat = 'pli' THEN 145 -- Linear plot
      WHEN vc.cat = 'pbr' THEN 606 -- Branching plot
      WHEN vc.cat = 'eac' THEN  12 -- Action
      WHEN vc.cat = 'eco' THEN 104 -- Comedy
      WHEN vc.cat = 'edr' THEN 147 -- Drama
      WHEN vc.cat = 'efa' THEN   2 -- Fantasy
      WHEN vc.cat = 'eho' THEN   7 -- Horror
      WHEN vc.cat = 'emy' THEN  19 -- Mystery
      WHEN vc.cat = 'ero' THEN  96 -- Romance
      WHEN vc.cat = 'esc' THEN  47 -- School life
      WHEN vc.cat = 'esf' THEN 105 -- Sci-Fi
      WHEN vc.cat = 'esj' THEN  97 -- Shoujo ai
      WHEN vc.cat = 'esn' THEN  98 -- Shounen ai
      WHEN vc.cat = 'tfu' THEN 140 -- Future
      WHEN vc.cat = 'tpa' THEN 141 -- Past
      WHEN vc.cat = 'tpr' THEN 143 -- Present
      WHEN vc.cat = 'lea' THEN  52 -- Earth
      WHEN vc.cat = 'lfa' THEN 259 -- Fantasy world
      WHEN vc.cat = 'lsp' THEN  53 -- Space
      WHEN vc.cat = 'hfa' THEN 133 -- Male protag
      WHEN vc.cat = 'hfe' THEN 134 -- Female protag
      WHEN vc.cat = 'saa' THEN  23 -- Sexual content
      WHEN vc.cat = 'sbe' THEN 183 -- Bestiality
      WHEN vc.cat = 'sin' THEN  86 -- Insect
      WHEN vc.cat = 'slo' THEN 156 -- Lolicon
      WHEN vc.cat = 'ssh' THEN 184 -- Shotacon
      WHEN vc.cat = 'sya' THEN  83 -- Yaoi
      WHEN vc.cat = 'syu' THEN  82 -- Yuri
      WHEN vc.cat = 'sra' THEN  84 -- Rape
      ELSE 11 -- the deleted 'Awesome' tag, this shouldn't happen
    END
  FROM vn v
  JOIN vn_categories vc ON vc.vid = v.latest
  WHERE NOT EXISTS(SELECT 1 FROM tags_vn tv WHERE tv.vid = v.id);
DROP TABLE vn_categories;

