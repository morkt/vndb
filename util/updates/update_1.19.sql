

-- Messageboard
CREATE TABLE threads (
  id SERIAL NOT NULL PRIMARY KEY,
  title varchar(50) NOT NULL DEFAULT '',
  count smallint NOT NULL DEFAULT 0,
  locked smallint NOT NULL DEFAULT 0,
  hidden smallint NOT NULL DEFAULT 0
) WITHOUT OIDS;

CREATE TABLE threads_tags (
  tid integer NOT NULL DEFAULT 0 REFERENCES threads (id) DEFERRABLE INITIALLY DEFERRED,
  type char(2) NOT NULL DEFAULT 0,
  iid integer NOT NULL DEFAULT 0 -- references to (vn|releases|producers|users).id
) WITHOUT OIDS;

CREATE TABLE threads_posts (
  tid integer NOT NULL DEFAULT 0 REFERENCES threads (id) DEFERRABLE INITIALLY DEFERRED,
  num integer NOT NULL DEFAULT 0,
  uid integer NOT NULL DEFAULT 0 REFERENCES users (id) DEFERRABLE INITIALLY DEFERRED,
  date bigint NOT NULL DEFAULT DATE_PART('epoch', NOW()),
  edited bigint NOT NULL DEFAULT 0,
  hidden smallint NOT NULL DEFAULT 0,
  msg text NOT NULL DEFAULT '',
  PRIMARY KEY(tid, num)
) WITHOUT OIDS;

