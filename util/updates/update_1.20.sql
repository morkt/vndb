
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


-- wishlist
CREATE TABLE wlists (
  uid integer NOT NULL DEFAULT 0 REFERENCES users (id) DEFERRABLE INITIALLY DEFERRED,
  vid integer NOT NULL DEFAULT 0 REFERENCES vn    (id) DEFERRABLE INITIALLY DEFERRED,
  wstat smallint NOT NULL DEFAULT 0,
  added bigint NOT NULL DEFAULT DATE_PART('epoch', NOW()),
  PRIMARY KEY(uid, vid)
) WITHOUT OIDS;


-- move 'Wishlist' and 'Blacklist' statuses of the old VNList to the new wishlist
INSERT INTO wlists (uid, vid, wstat, added)
  (SELECT uid, vid, CASE WHEN status = 0 THEN 1 ELSE 3 END, date
   FROM vnlists
   WHERE status < 2);

DELETE FROM vnlists WHERE status < 2 AND comments = '';

