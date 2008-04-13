UPDATE vn_categories SET category = 'aaa' WHERE category = 'ami';

--CREATE TABLE changes (
--  id SERIAL NOT NULL PRIMARY KEY,
--  "type" smallint DEFAULT 0 NOT NULL,
--  rel integer DEFAULT 0 NOT NULL,
--  vrel integer DEFAULT 0 NOT NULL,
--  uid integer DEFAULT 0 NOT NULL,
--  status smallint DEFAULT 0 NOT NULL,
--  added bigint DEFAULT 0 NOT NULL,
--  lastmod bigint DEFAULT 0 NOT NULL,
--  changes bytea DEFAULT ''::bytea NOT NULL,
--  comments text DEFAULT '' NOT NULL
--);


CREATE LANGUAGE plpgsql;
CREATE OR REPLACE FUNCTION get_new_id() RETURNS integer AS $$
DECLARE
  i integer := 1;
  r RECORD;
BEGIN
  FOR r IN SELECT id FROM vn ORDER BY id ASC LOOP
    IF i <> r.id THEN
      EXIT;
    END IF;
    i := i+1;
  END LOOP;
  RETURN i;
END;
$$ LANGUAGE plpgsql;

ALTER TABLE vn ALTER COLUMN id SET DEFAULT get_new_id();
DROP SEQUENCE vn_id_seq;


ALTER TABLE vnr ADD COLUMN notes varchar(250) DEFAULT '';
