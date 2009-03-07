
-- some random VN quotes
CREATE TABLE quotes (
  vid integer NOT NULL REFERENCES vn (id),
  quote varchar(250) NOT NULL,
  PRIMARY KEY(vid, quote)
) WITHOUT OIDS;


-- catalog numbers for releases
ALTER TABLE releases_rev ADD COLUMN catalog varchar(50) NOT NULL DEFAULT '';




-- tagging system

CREATE TABLE tags (
  id          SERIAL       NOT NULL PRIMARY KEY,
  name        varchar(250) NOT NULL UNIQUE,
  alias       text         NOT NULL DEFAULT '',
  description text         NOT NULL DEFAULT '',
  meta        boolean      NOT NULL DEFAULT FALSE
) WITHOUT OIDS;

CREATE TABLE tags_parents (
  tag    integer NOT NULL REFERENCES tags (id) DEFERRABLE INITIALLY DEFERRED,
  parent integer NOT NULL REFERENCES tags (id) DEFERRABLE INITIALLY DEFERRED,
  PRIMARY KEY(tag, parent)
) WITHOUT OIDS;

CREATE TABLE tags_vn (
  tag     integer  NOT NULL REFERENCES tags  (id) DEFERRABLE INITIALLY DEFERRED,
  vid     integer  NOT NULL REFERENCES vn    (id) DEFERRABLE INITIALLY DEFERRED,
  uid     integer  NOT NULL REFERENCES users (id) DEFERRABLE INITIALLY DEFERRED,
  vote    smallint NOT NULL DEFAULT 3 CHECK (vote >= -3 AND vote <= 3 AND vote <> 0),
  spoiler smallint CHECK(spoiler >= 0 AND spoiler <= 2),
  PRIMARY KEY(tag, vid, uid)
) WITHOUT OIDS;


CREATE TYPE tag_tree_item AS (lvl smallint, tag integer, name text);

-- tag: tag to start with,
-- lvl: recursion level
-- dir: direction, true = parent->child, false = child->parent
CREATE OR REPLACE FUNCTION tag_tree(tag integer, lvl integer, dir boolean) RETURNS SETOF tag_tree_item AS $$
DECLARE
  r tag_tree_item%rowtype;
  r2 tag_tree_item%rowtype;
BEGIN
  IF dir AND tag = 0 THEN
    FOR r IN
      SELECT lvl, t.id, t.name
        FROM tags t
        WHERE NOT EXISTS(SELECT 1 FROM tags_parents tp WHERE tp.tag = t.id)
        ORDER BY t.name
    LOOP
      RETURN NEXT r;
      IF lvl-1 <> 0 THEN
        FOR r2 IN SELECT * FROM tag_tree(r.tag, lvl-1, dir) LOOP
          RETURN NEXT r2;
        END LOOP;
      END IF;
    END LOOP;
  ELSIF dir THEN
    FOR r IN
      SELECT lvl, tp.tag, t.name
        FROM tags_parents tp
        JOIN tags t ON t.id = tp.tag
        WHERE tp.parent = tag
        ORDER BY t.name
    LOOP
      RETURN NEXT r;
      IF lvl-1 <> 0 THEN
        FOR r2 IN SELECT * FROM tag_tree(r.tag, lvl-1, dir) LOOP
          RETURN NEXT r2;
        END LOOP;
      END IF;
    END LOOP;
  ELSE
    FOR r IN
      SELECT lvl, tp.parent, t.name
        FROM tags_parents tp
        JOIN tags t ON t.id = tp.parent
        WHERE tp.tag = tag
        ORDER BY t.name
    LOOP
      RETURN NEXT r;
      IF lvl-1 <> 0 THEN
        FOR r2 IN SELECT * FROM tag_tree(r.tag, lvl-1, dir) LOOP
          RETURN NEXT r2;
        END LOOP;
      END IF;
    END LOOP;
  END IF;
END;
$$ LANGUAGE plpgsql;

-- returns all votes inherited by childs
-- UNION this with tags_vn and you have all votes for all tags
CREATE OR REPLACE FUNCTION tag_vn_childs() RETURNS SETOF tags_vn AS $$
DECLARE
  r tags_vn%rowtype;
  i RECORD;
  l RECORD;
BEGIN
  FOR l IN SElECT id FROM tags WHERE meta = FALSE AND EXISTS(SELECT 1 FROM tags_parents WHERE parent = id) LOOP
    FOR i IN SELECT tag FROM tag_tree(l.id, 0, true) LOOP
      FOR r IN SELECT l.id, vid, uid, vote, spoiler FROM tags_vn WHERE tag = i.tag LOOP
        RETURN NEXT r;
      END LOOP;
    END LOOP;
  END LOOP;
END;
$$ LANGUAGE plpgsql;

-- all votes for all tags
CREATE OR REPLACE VIEW tags_vn_all AS
    SELECT *
      FROM tags_vn
  UNION
    SELECT *
      FROM tag_vn_childs();

-- grouped by (tag, vid, uid), so only one user votes on one parent tag per VN entry
CREATE OR REPLACE VIEW tags_vn_grouped AS
    SELECT tag, vid, uid, AVG(vote)::real AS vote, COALESCE(AVG(spoiler), 0)::real AS spoiler
      FROM tags_vn_all
  GROUP BY tag, vid, uid;

-- grouped by (tag, vid), so we now finally have a list of VN entries for a tag (including inherited tags)
CREATE OR REPLACE VIEW tags_vn_inherited AS
    SELECT tag, vid, COUNT(uid)::real AS users, AVG(vote)::real AS rating, AVG(spoiler)::real AS spoiler
      FROM tags_vn_grouped
  GROUP BY tag, vid;

-- bayesian average on the above view, to provide better rankings as to how much a tag applies to a VN
-- details of the calculation @ http://www.thebroth.com/blog/118/bayesian-rating
CREATE OR REPLACE VIEW tags_vn_bayesian AS
  SELECT tag, vid, users,
      ( (SELECT AVG(users)::real * AVG(rating)::real FROM tags_vn_inherited WHERE tag = tvi.tag) + users*rating )
      / ( (SELECT AVG(users)::real FROM tags_vn_inherited WHERE tag = tvi.tag) + users )::real AS rating,
      (CASE WHEN spoiler < 0.7 THEN 0 WHEN spoiler > 1.3 THEN 2 ELSE 1 END)::smallint AS spoiler
    FROM tags_vn_inherited tvi;


-- creates/updates a table eqvuivalent to tags_vn_bayesian
CREATE OR REPLACE FUNCTION tag_vn_calc() RETURNS void AS $$
BEGIN
  DROP TABLE IF EXISTS tags_vn_stored;
  CREATE TABLE tags_vn_stored AS SELECT * FROM tags_vn_inherited;
  CREATE INDEX tags_vn_stored_tag ON tags_vn_stored (tag);
  -- The following method may be faster on larger DBs, because tag_vn_childs() only has to be called once
  --UPDATE tags_vn_stored tvs SET rating =
  --    ((SELECT AVG(users)::real * AVG(rating)::real FROM tags_vn_stored WHERE tag = tvs.tag) + users*rating)
  --  / ((SELECT AVG(users)::real FROM tags_vn_inherited WHERE tag = tvs.tag) + users)::real;
  RETURN;
END;
$$ LANGUAGE plpgsql;
SELECT tag_vn_calc();


