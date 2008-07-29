
-- deleted user
INSERT INTO users (id, username, mail, rank)
  VALUES (0, 'deleted', 'del@vndb.org', 0);



-- release lists
CREATE TABLE rlists (
  uid integer NOT NULL DEFAULT 0 REFERENCES users    (id) DEFERRABLE INITIALLY DEFERRED,
  rid integer NOT NULL DEFAULT 0 REFERENCES releases (id) DEFERRABLE INITIALLY DEFERRED,
  vstat smallint NOT NULL DEFAULT 0,
  rstat smallint NOT NULL DEFAULT 0,
  added bigint NOT NULL DEFAULT DATE_PART('epoch', NOW()),
  PRIMARY KEY(uid, rid)
) WITHOUT OIDS;

