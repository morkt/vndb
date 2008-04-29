

-- remove the old image hashes
ALTER TABLE vn_rev DROP COLUMN image_old;



-- Add anime relations
CREATE TABLE anime (
  id integer NOT NULL PRIMARY KEY, -- anidb id
  year smallint NOT NULL DEFAULT 0,
  ann_id integer NOT NULL DEFAULT 0,
  nfo_id varchar(200) NOT NULL DEFAULT '',
  type smallint NOT NULL DEFAULT 0, -- TV/OVA/etc (global.pl)
  title_romaji varchar(250) NOT NULL DEFAULT '',
  title_kanji varchar(250) NOT NULL DEFAULT '',
  lastfetch bigint NOT NULL DEFAULT 0 -- -1:not found, 0: not fetched, >0: timestamp
) WITHOUT oids;

CREATE TABLE vn_anime (
  vid integer NOT NULL REFERENCES vn_rev (id) DEFERRABLE INITIALLY DEFERRED,
  aid integer NOT NULL REFERENCES anime (id) DEFERRABLE INITIALLY DEFERRED,
  PRIMARY KEY(vid, aid)
) WITHOUT oids;


