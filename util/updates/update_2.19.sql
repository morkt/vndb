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

