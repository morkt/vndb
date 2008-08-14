
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

