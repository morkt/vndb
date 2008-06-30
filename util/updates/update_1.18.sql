
-- prev -> rev
ALTER TABLE changes ADD COLUMN rev integer NOT NULL DEFAULT 1;
ALTER TABLE changes DROP COLUMN prev;

DROP FUNCTION update_prev(text, text);

CREATE OR REPLACE FUNCTION update_rev(tbl text, ids text) RETURNS void AS $$
DECLARE
  r RECORD;
  r2 RECORD;
  i integer;
  t text;
  e text;
BEGIN
  SELECT INTO t SUBSTRING(tbl, 1, 1);
  e := '';
  IF ids <> '' THEN
    e := ' WHERE id IN('||ids||')';
  END IF;
  FOR r IN EXECUTE 'SELECT id FROM '||tbl||e LOOP
    i := 1;
    FOR r2 IN EXECUTE 'SELECT id FROM '||tbl||'_rev WHERE '||t||'id = '||r.id||' ORDER BY id ASC' LOOP
      UPDATE changes SET rev = i WHERE id = r2.id;
      i := i+1;
    END LOOP;
  END LOOP;
END;
$$ LANGUAGE plpgsql;
SELECT update_rev('vn', ''), update_rev('releases', ''), update_rev('producers', '');

