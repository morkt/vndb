CREATE TABLE vn_relations (
  vid1 integer NOT NULL,
  vid2 integer NOT NULL,
  relation smallint NOT NULL,
  lastmod bigint NOT NULL,
  PRIMARY KEY(vid1, vid2)
);

ALTER TABLE vn ADD COLUMN img_nsfw smallint NOT NULL DEFAULT 0;
ALTER TABLE users ADD COLUMN pign_nsfw smallint NOT NULL DEFAULT 0;
