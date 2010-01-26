

CREATE TYPE notification_ntype AS ENUM ('pm');
CREATE TYPE notification_ltype AS ENUM ('t');

CREATE TABLE notifications (
  id serial PRIMARY KEY NOT NULL,
  uid integer NOT NULL REFERENCES users (id),
  date timestamptz NOT NULL DEFAULT NOW(),
  read timestamptz,
  ntype notification_ntype NOT NULL,
  ltype notification_ltype NOT NULL,
  iid integer NOT NULL,
  subid integer
);

-- convert the "unread messages" count into notifications
INSERT INTO notifications (uid, date, ntype, ltype, iid, subid)
  SELECT tb.iid, tp.date, 'pm', 't', t.id, tp.num
    FROM threads_boards tb
    JOIN threads t ON t.id = tb.tid
    JOIN threads_posts tp ON tp.tid = t.id AND tp.num = COALESCE(tb.lastread, 1)
    WHERE tb.type = 'u' AND NOT t.hidden AND (tb.lastread IS NULL OR t.count <> tb.lastread);

-- ...and drop the now unused lastread column
ALTER TABLE threads_boards DROP COLUMN lastread;




ALTER TABLE changes ADD COLUMN ihid boolean NOT NULL DEFAULT FALSE;
ALTER TABLE changes ADD COLUMN ilock boolean NOT NULL DEFAULT FALSE;

\i util/sql/func.sql

CREATE TRIGGER vn_hidlock_update          BEFORE UPDATE           ON vn            FOR EACH ROW EXECUTE PROCEDURE update_hidlock();
CREATE TRIGGER producers_hidlock_update   BEFORE UPDATE           ON producers     FOR EACH ROW EXECUTE PROCEDURE update_hidlock();
CREATE TRIGGER releases_hidlock_update    BEFORE UPDATE           ON releases      FOR EACH ROW EXECUTE PROCEDURE update_hidlock();

CREATE TRIGGER notify_pm                  AFTER  INSERT           ON threads_posts FOR EACH ROW EXECUTE PROCEDURE notify_pm();


CREATE OR REPLACE FUNCTION tmp_edit_hidlock(t text, iid integer) RETURNS void AS $$
BEGIN
  IF t = 'v' THEN
    PERFORM edit_vn_init(latest) FROM vn WHERE id = iid;
    IF EXISTS(SELECT 1 FROM vn WHERE id = iid AND hidden) THEN
      UPDATE edit_revision SET ihid = true, ip = '0.0.0.0', requester = 1,
        comments = 'This visual novel was deleted before the update to VNDB 2.11, no reason specified.';
    ELSE
      UPDATE edit_revision SET ilock = true, ip = '0.0.0.0', requester = 1,
        comments = 'This visual novel was locked before the update to VNDB 2.11, no reason specified.';
    END IF;
    PERFORM edit_vn_commit();
  ELSIF t = 'r' THEN
    PERFORM edit_release_init(latest) FROM releases WHERE id = iid;
    IF EXISTS(SELECT 1 FROM releases WHERE id = iid AND hidden) THEN
      UPDATE edit_revision SET ihid = true, ip = '0.0.0.0', requester = 1,
        comments = 'This release was deleted before the update to VNDB 2.11, no reason specified.';
    ELSE
      UPDATE edit_revision SET ilock = true, ip = '0.0.0.0', requester = 1,
        comments = 'This release was locked before the update to VNDB 2.11, no reason specified.';
    END IF;
    PERFORM edit_release_commit();
  ELSE
    PERFORM edit_producer_init(latest) FROM producers WHERE id = iid;
    IF EXISTS(SELECT 1 FROM producers WHERE id = iid AND hidden) THEN
      UPDATE edit_revision SET ihid = true, ip = '0.0.0.0', requester = 1,
        comments = 'This producer was deleted before the update to VNDB 2.11, no reason specified.';
    ELSE
      UPDATE edit_revision SET ilock = true, ip = '0.0.0.0', requester = 1,
        comments = 'This producer was locked before the update to VNDB 2.11, no reason specified.';
    END IF;
    PERFORM edit_producer_commit();
  END IF;
END;
$$ LANGUAGE plpgsql;

      SELECT 'v', COUNT(*) FROM (SELECT tmp_edit_hidlock('v', id) FROM vn WHERE (hidden OR locked)) x
UNION SELECT 'r', COUNT(*) FROM (SELECT tmp_edit_hidlock('r', id) FROM releases WHERE hidden OR locked) x
UNION SELECT 'p', COUNT(*) FROM (SELECT tmp_edit_hidlock('p', id) FROM producers WHERE hidden OR locked) x;
DROP FUNCTION tmp_edit_hidlock(text, integer);


-- keep track of when a session is last used
ALTER TABLE sessions ADD COLUMN lastused timestamptz NOT NULL DEFAULT NOW();

