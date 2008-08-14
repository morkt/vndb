
-- screenshots
--CREATE SEQUENCE screenshots_seq;

CREATE TABLE vn_screenshots (
  vid integer NOT NULL DEFAULT 0 REFERENCES vn_rev (id) DEFERRABLE INITIALLY DEFERRED,
  scr integer NOT NULL DEFAULT 0,
  nsfw smallint NOT NULL DEFAULT 0,
  PRIMARY KEY(vid, scr)
) WITHOUT OIDS;


