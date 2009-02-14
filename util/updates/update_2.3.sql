
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
  aliases     text         NOT NULL DEFAULT '',
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
  vote    smallint NOT NULL DEFAULT 3,     -- -3..3 (0 isn't actually used...)
  spoiler boolean  NOT NULL DEFAULT FALSE,
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


