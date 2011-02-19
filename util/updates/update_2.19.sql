-- These changes have not been synced with the /util/sql/ files yet.


-- character database -> traits

CREATE TABLE traits (
  id SERIAL PRIMARY KEY,
  name varchar(250) NOT NULL UNIQUE,
  description text NOT NULL DEFAULT '',
  meta boolean NOT NULL DEFAULT false,
  added timestamptz NOT NULL DEFAULT NOW(),
  state smallint NOT NULL DEFAULT 0,
  addedby integer NOT NULL DEFAULT 0 REFERENCES users (id)
);

CREATE TABLE traits_aliases (
  alias varchar(250) NOT NULL PRIMARY KEY,
  trait integer NOT NULL REFERENCES traits (id)
);

CREATE TABLE traits_parents (
  trait integer NOT NULL REFERENCES traits (id),
  parent integer NOT NULL REFERENCES traits (id),
  PRIMARY KEY(trait, parent)
);

CREATE TRIGGER insert_notify              AFTER  INSERT           ON traits        FOR EACH STATEMENT EXECUTE PROCEDURE insert_notify();



-- character database -> chars

CREATE TYPE char_role AS ENUM ('main', 'primary', 'side', 'appears');
CREATE TYPE blood_type AS ENUM ('unknown', 'a', 'b', 'ab', 'o', 'other');

CREATE TABLE chars (
  id SERIAL PRIMARY KEY,
  latest integer NOT NULL DEFAULT 0,
  locked boolean NOT NULL DEFAULT FALSE,
  hidden boolean NOT NULL DEFAULT FALSE
);

CREATE TABLE chars_rev (
  id         integer  NOT NULL PRIMARY KEY REFERENCES changes (id),
  cid        integer  NOT NULL REFERENCES chars (id),
  name       varchar(250) NOT NULL DEFAULT '',
  original   varchar(250) NOT NULL DEFAULT '',
  alias      varchar(500) NOT NULL DEFAULT '',
  image      integer  NOT NULL DEFAULT 0,
  "desc"     text     NOT NULL DEFAULT '',
  s_bust     smallint NOT NULL DEFAULT 0,
  s_waist    smallint NOT NULL DEFAULT 0,
  s_hip      smallint NOT NULL DEFAULT 0,
  b_month    smallint NOT NULL DEFAULT 0,
  b_day      smallint NOT NULL DEFAULT 0,
  height     smallint NOT NULL DEFAULT 0,
  weight     smallint NOT NULL DEFAULT 0,
  bloodt     blood_type NOT NULL DEFAULT 'unknown',
  main       integer  REFERENCES chars (id),
  main_spoil boolean  NOT NULL DEFAULT false
);
ALTER TABLE chars ADD FOREIGN KEY (latest) REFERENCES chars_rev (id) DEFERRABLE INITIALLY DEFERRED;

CREATE TABLE chars_traits (
  cid integer NOT NULL REFERENCES chars_rev (id),
  tid integer NOT NULL REFERENCES traits (id),
  spoil smallint NOT NULL DEFAULT 0,
  PRIMARY KEY(cid, tid)
);

CREATE TABLE chars_vns (
  cid integer NOT NULL REFERENCES chars_rev (id),
  vid integer NOT NULL REFERENCES vn (id),
  rid integer REFERENCES releases (id),
  spoil boolean NOT NULL DEFAULT false,
  role char_role NOT NULL DEFAULT 'main',
  PRIMARY KEY(cid, vid, rid)
);

CREATE SEQUENCE charimg_seq;



-- allow characters to be versioned using the changes table

CREATE TYPE dbentry_type_tmp AS ENUM ('v', 'r', 'p', 'c');
ALTER TABLE changes ALTER COLUMN "type" TYPE dbentry_type_tmp USING "type"::text::dbentry_type_tmp;
DROP FUNCTION edit_revtable(dbentry_type, integer);
DROP TYPE dbentry_type;
ALTER TYPE dbentry_type_tmp RENAME TO dbentry_type;


-- load the updated functions

\i util/sql/func.sql


CREATE TRIGGER hidlock_update             BEFORE UPDATE           ON chars         FOR EACH ROW WHEN (OLD.latest IS DISTINCT FROM NEW.latest) EXECUTE PROCEDURE update_hidlock();
CREATE TRIGGER chars_rev_image_notify     AFTER  INSERT OR UPDATE ON chars_rev     FOR EACH ROW WHEN (NEW.image < 0) EXECUTE PROCEDURE chars_rev_image_notify();


-- test
--SELECT edit_char_init(null);
--UPDATE edit_revision SET comments = 'New test entry', requester = 2, ip = '0.0.0.0';
--UPDATE edit_char SET name = 'Phorni', original = 'フォーニ', "desc" = 'Sprite of Music';
--SELECT edit_char_commit();

