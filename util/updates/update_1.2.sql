CREATE TABLE vnlists (
  uid integer NOT NULL DEFAULT 0,
  vid integer NOT NULL DEFAULT 0,
  status smallint NOT NULL DEFAULT 0,
  added bigint NOT NULL DEFAULT 0,
  PRIMARY KEY(uid, vid)
) WITHOUT OIDS;

ALTER TABlE users ADD COLUMN plist smallint NOT NULL DEFAULT 1;
