
\i util/sql/func.sql

-- redefine the triggers to use the new conditional triggers in PostgreSQL 9.0

DROP TRIGGER hidlock_update ON vn;
DROP TRIGGER hidlock_update ON producers;
DROP TRIGGER hidlock_update ON releases;
CREATE TRIGGER hidlock_update             BEFORE UPDATE           ON vn            FOR EACH ROW WHEN (OLD.latest IS DISTINCT FROM NEW.latest) EXECUTE PROCEDURE update_hidlock();
CREATE TRIGGER hidlock_update             BEFORE UPDATE           ON producers     FOR EACH ROW WHEN (OLD.latest IS DISTINCT FROM NEW.latest) EXECUTE PROCEDURE update_hidlock();
CREATE TRIGGER hidlock_update             BEFORE UPDATE           ON releases      FOR EACH ROW WHEN (OLD.latest IS DISTINCT FROM NEW.latest) EXECUTE PROCEDURE update_hidlock();


DROP TRIGGER vn_stats_update            ON vn;
DROP TRIGGER producers_stats_update     ON producers;
DROP TRIGGER releases_stats_update      ON releases;
DROP TRIGGER threads_stats_update       ON threads;
DROP TRIGGER threads_posts_stats_update ON threads_posts;
DROP TRIGGER users_stats_update         ON users;
CREATE TRIGGER stats_cache_new            AFTER  INSERT           ON vn            FOR EACH ROW WHEN (NEW.hidden = FALSE) EXECUTE PROCEDURE update_stats_cache();
CREATE TRIGGER stats_cache_edit           AFTER  UPDATE           ON vn            FOR EACH ROW WHEN (OLD.hidden IS DISTINCT FROM NEW.hidden) EXECUTE PROCEDURE update_stats_cache();
CREATE TRIGGER stats_cache_new            AFTER  INSERT           ON producers     FOR EACH ROW WHEN (NEW.hidden = FALSE) EXECUTE PROCEDURE update_stats_cache();
CREATE TRIGGER stats_cache_edit           AFTER  UPDATE           ON producers     FOR EACH ROW WHEN (OLD.hidden IS DISTINCT FROM NEW.hidden) EXECUTE PROCEDURE update_stats_cache();
CREATE TRIGGER stats_cache_new            AFTER  INSERT           ON releases      FOR EACH ROW WHEN (NEW.hidden = FALSE) EXECUTE PROCEDURE update_stats_cache();
CREATE TRIGGER stats_cache_edit           AFTER  UPDATE           ON releases      FOR EACH ROW WHEN (OLD.hidden IS DISTINCT FROM NEW.hidden) EXECUTE PROCEDURE update_stats_cache();
CREATE TRIGGER stats_cache_new            AFTER  INSERT           ON threads       FOR EACH ROW WHEN (NEW.hidden = FALSE) EXECUTE PROCEDURE update_stats_cache();
CREATE TRIGGER stats_cache_edit           AFTER  UPDATE           ON threads       FOR EACH ROW WHEN (OLD.hidden IS DISTINCT FROM NEW.hidden) EXECUTE PROCEDURE update_stats_cache();
CREATE TRIGGER stats_cache_new            AFTER  INSERT           ON threads_posts FOR EACH ROW WHEN (NEW.hidden = FALSE) EXECUTE PROCEDURE update_stats_cache();
CREATE TRIGGER stats_cache_edit           AFTER  UPDATE           ON threads_posts FOR EACH ROW WHEN (OLD.hidden IS DISTINCT FROM NEW.hidden) EXECUTE PROCEDURE update_stats_cache();
CREATE TRIGGER stats_cache                AFTER  INSERT OR DELETE ON users         FOR EACH ROW EXECUTE PROCEDURE update_stats_cache();

DROP TRIGGER vn_anime_aid ON vn_anime;
CREATE TRIGGER vn_anime_aid_new           BEFORE INSERT           ON vn_anime      FOR EACH ROW EXECUTE PROCEDURE vn_anime_aid();
CREATE TRIGGER vn_anime_aid_edit          BEFORE UPDATE           ON vn_anime      FOR EACH ROW WHEN (OLD.aid IS DISTINCT FROM NEW.aid) EXECUTE PROCEDURE vn_anime_aid();

DROP TRIGGER anime_fetch_notify ON anime;
CREATE TRIGGER anime_fetch_notify         AFTER  INSERT OR UPDATE ON anime         FOR EACH ROW WHEN (NEW.lastfetch IS NULL) EXECUTE PROCEDURE anime_fetch_notify();

DROP TRIGGER vn_rev_image_notify ON vn_rev;
CREATE TRIGGER vn_rev_image_notify        AFTER  INSERT OR UPDATE ON vn_rev        FOR EACH ROW WHEN (NEW.image < 0) EXECUTE PROCEDURE vn_rev_image_notify();

DROP TRIGGER screenshot_process_notify ON screenshots;
CREATE TRIGGER screenshot_process_notify  AFTER  INSERT OR UPDATE ON screenshots   FOR EACH ROW WHEN (NEW.processed = FALSE) EXECUTE PROCEDURE screenshot_process_notify();

DROP TRIGGER vn_relgraph_notify ON vn;
CREATE TRIGGER vn_relgraph_notify AFTER UPDATE ON vn FOR EACH ROW
  WHEN (OLD.rgraph      IS DISTINCT FROM NEW.rgraph
     OR OLD.latest      IS DISTINCT FROM NEW.latest
     OR OLD.c_released  IS DISTINCT FROM NEW.c_released
     OR OLD.c_languages IS DISTINCT FROM NEW.c_languages
  ) EXECUTE PROCEDURE vn_relgraph_notify();

DROP TRIGGER producer_relgraph_notify ON producers;
CREATE TRIGGER producer_relgraph_notify AFTER UPDATE ON producers FOR EACH ROW
  WHEN (OLD.rgraph IS DISTINCT FROM NEW.rgraph
     OR OLD.latest IS DISTINCT FROM NEW.latest
  ) EXECUTE PROCEDURE producer_relgraph_notify();

DROP TRIGGER release_vncache_update ON releases;
CREATE TRIGGER release_vncache_update AFTER UPDATE ON releases FOR EACH ROW
  WHEN (OLD.latest IS DISTINCT FROM NEW.latest OR OLD.hidden IS DISTINCT FROM NEW.hidden)
  EXECUTE PROCEDURE release_vncache_update();

DROP TRIGGER notify_dbdel ON vn;
DROP TRIGGER notify_dbdel ON producers;
DROP TRIGGER notify_dbdel ON releases;
CREATE TRIGGER notify_dbdel               AFTER  UPDATE           ON vn            FOR EACH ROW WHEN (NOT OLD.hidden AND NEW.hidden) EXECUTE PROCEDURE notify_dbdel();
CREATE TRIGGER notify_dbdel               AFTER  UPDATE           ON producers     FOR EACH ROW WHEN (NOT OLD.hidden AND NEW.hidden) EXECUTE PROCEDURE notify_dbdel();
CREATE TRIGGER notify_dbdel               AFTER  UPDATE           ON releases      FOR EACH ROW WHEN (NOT OLD.hidden AND NEW.hidden) EXECUTE PROCEDURE notify_dbdel();

DROP TRIGGER notify_listdel ON vn;
DROP TRIGGER notify_listdel ON releases;
CREATE TRIGGER notify_listdel             AFTER  UPDATE           ON vn            FOR EACH ROW WHEN (NOT OLD.hidden AND NEW.hidden) EXECUTE PROCEDURE notify_listdel();
CREATE TRIGGER notify_listdel             AFTER  UPDATE           ON releases      FOR EACH ROW WHEN (NOT OLD.hidden AND NEW.hidden) EXECUTE PROCEDURE notify_listdel();

DROP TRIGGER notify_dbedit ON vn;
DROP TRIGGER notify_dbedit ON producers;
DROP TRIGGER notify_dbedit ON releases;
CREATE TRIGGER notify_dbedit              AFTER  UPDATE           ON vn            FOR EACH ROW WHEN (OLD.latest IS DISTINCT FROM NEW.latest AND NOT NEW.hidden) EXECUTE PROCEDURE notify_dbedit();
CREATE TRIGGER notify_dbedit              AFTER  UPDATE           ON producers     FOR EACH ROW WHEN (OLD.latest IS DISTINCT FROM NEW.latest AND NOT NEW.hidden) EXECUTE PROCEDURE notify_dbedit();
CREATE TRIGGER notify_dbedit              AFTER  UPDATE           ON releases      FOR EACH ROW WHEN (OLD.latest IS DISTINCT FROM NEW.latest AND NOT NEW.hidden) EXECUTE PROCEDURE notify_dbedit();

DROP TRIGGER notify_announce ON threads_posts;
CREATE TRIGGER notify_announce            AFTER  INSERT           ON threads_posts FOR EACH ROW WHEN (NEW.num = 1) EXECUTE PROCEDURE notify_announce();

DROP TRIGGER vn_vnsearch_notify ON vn;
CREATE TRIGGER vn_vnsearch_notify AFTER UPDATE ON vn FOR EACH ROW
  WHEN (OLD.c_search IS NOT NULL AND NEW.c_search IS NULL AND NOT NEW.hidden
     OR NEW.hidden IS DISTINCT FROM OLD.hidden
     OR NEW.latest IS DISTINCT FROM OLD.latest
  ) EXECUTE PROCEDURE vn_vnsearch_notify();

DROP TRIGGER vn_vnsearch_notify ON releases;
CREATE TRIGGER vn_vnsearch_notify AFTER UPDATE ON releases FOR EACH ROW
  WHEN (NEW.hidden IS DISTINCT FROM OLD.hidden OR NEW.latest IS DISTINCT FROM OLD.latest)
  EXECUTE PROCEDURE vn_vnsearch_notify();



-- add ON DELETE clause to all foreign keys referencing users (id)
-- and change some defaults/constraints to make sure it'll actually work

ALTER TABLE changes DROP CONSTRAINT changes_requester_fkey;
ALTER TABLE changes             ADD FOREIGN KEY (requester) REFERENCES users         (id) ON DELETE SET DEFAULT;

UPDATE notifications SET c_byuser = 0 WHERE c_byuser IS NULL;
ALTER TABLE notifications ALTER COLUMN c_byuser SET DEFAULT 0;
ALTER TABLE notifications ALTER COLUMN c_byuser SET NOT NULL;
ALTER TABLE notifications DROP CONSTRAINT notifications_uid_fkey;
ALTER TABLE notifications DROP CONSTRAINT notifications_c_byuser_fkey;
ALTER TABLE notifications       ADD FOREIGN KEY (uid)       REFERENCES users         (id) ON DELETE CASCADE;
ALTER TABLE notifications       ADD FOREIGN KEY (c_byuser)  REFERENCES users         (id) ON DELETE SET DEFAULT;

ALTER TABLE rlists DROP CONSTRAINT rlists_uid_fkey;
ALTER TABLE rlists              ADD FOREIGN KEY (uid)       REFERENCES users         (id) ON DELETE CASCADE;

ALTER TABLE sessions DROP CONSTRAINT sessions_uid_fkey;
ALTER TABLE sessions            ADD FOREIGN KEY (uid)       REFERENCES users         (id) ON DELETE CASCADE;

ALTER TABLE tags ALTER COLUMN addedby SET DEFAULT 0;
ALTER TABLE tags DROP CONSTRAINT tags_addedby_fkey;
ALTER TABLE tags                ADD FOREIGN KEY (addedby)   REFERENCES users         (id) ON DELETE SET DEFAULT;

ALTER TABLE tags_vn DROP CONSTRAINT tags_vn_uid_fkey;
ALTER TABLE tags_vn             ADD FOREIGN KEY (uid)       REFERENCES users         (id) ON DELETE CASCADE;

ALTER TABLE threads_posts DROP CONSTRAINT threads_posts_uid_fkey;
ALTER TABLE threads_posts       ADD FOREIGN KEY (uid)       REFERENCES users         (id) ON DELETE SET DEFAULT;

ALTER TABLE votes DROP CONSTRAINT votes_uid_fkey;
ALTER TABLE votes               ADD FOREIGN KEY (uid)       REFERENCES users         (id) ON DELETE CASCADE;

ALTER TABLE wlists DROP CONSTRAINT wlists_uid_fkey;
ALTER TABLE wlists              ADD FOREIGN KEY (uid)       REFERENCES users         (id) ON DELETE CASCADE;

