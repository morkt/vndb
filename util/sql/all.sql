-- NOTE: Make sure you're cd'ed in the vndb root directory before running this script


-- data types

CREATE TYPE anime_type        AS ENUM ('tv', 'ova', 'mov', 'oth', 'web', 'spe', 'mv');
CREATE TYPE blood_type        AS ENUM ('unknown', 'a', 'b', 'ab', 'o');
CREATE TYPE board_type        AS ENUM ('an', 'db', 'ge', 'v', 'p', 'u');
CREATE TYPE char_role         AS ENUM ('main', 'primary', 'side', 'appears');
CREATE TYPE credit_type       AS ENUM ('scenario', 'chardesign', 'art', 'music', 'songs', 'director', 'staff');
CREATE TYPE dbentry_type      AS ENUM ('v', 'r', 'p', 'c', 's');
CREATE TYPE edit_rettype      AS (iid integer, cid integer, rev integer);
CREATE TYPE gender            AS ENUM ('unknown', 'm', 'f', 'b');
CREATE TYPE language          AS ENUM ('ar', 'ca', 'cs', 'da', 'de', 'en', 'es', 'fi', 'fr', 'he', 'hu', 'id', 'it', 'ja', 'ko', 'nl', 'no', 'pl', 'pt-pt', 'pt-br', 'ro', 'ru', 'sk', 'sv', 'tr', 'uk', 'vi', 'zh');
CREATE TYPE medium            AS ENUM ('cd', 'dvd', 'gdr', 'blr', 'flp', 'mrt', 'mem', 'umd', 'nod', 'in', 'otc');
CREATE TYPE notification_ntype AS ENUM ('pm', 'dbdel', 'listdel', 'dbedit', 'announce');
CREATE TYPE notification_ltype AS ENUM ('v', 'r', 'p', 'c', 't', 's');
CREATE TYPE platform          AS ENUM ('win', 'dos', 'lin', 'mac', 'ios', 'and', 'dvd', 'bdp', 'fmt', 'gba', 'gbc', 'msx', 'nds', 'nes', 'p88', 'p98', 'pce', 'pcf', 'psp', 'ps1', 'ps2', 'ps3', 'ps4', 'psv', 'drc', 'sat', 'sfc', 'wii', 'n3d', 'x68', 'xb1', 'xb3', 'xbo', 'web', 'oth');
CREATE TYPE prefs_key         AS ENUM ('l10n', 'skin', 'customcss', 'filter_vn', 'filter_release', 'show_nsfw', 'hide_list', 'notify_nodbedit', 'notify_announce', 'vn_list_own', 'vn_list_wish', 'tags_all', 'tags_cat', 'spoilers', 'traits_sexual');
CREATE TYPE producer_relation AS ENUM ('old', 'new', 'sub', 'par', 'imp', 'ipa', 'spa', 'ori');
CREATE TYPE release_type      AS ENUM ('complete', 'partial', 'trial');
CREATE TYPE tag_category      AS ENUM('cont', 'ero', 'tech');
CREATE TYPE vn_relation       AS ENUM ('seq', 'preq', 'set', 'alt', 'char', 'side', 'par', 'ser', 'fan', 'orig');


-- schema

\i util/sql/schema.sql


-- functions

\i util/sql/func.sql


-- triggers

CREATE TRIGGER hidlock_update             BEFORE UPDATE           ON vn            FOR EACH ROW WHEN (OLD.latest IS DISTINCT FROM NEW.latest) EXECUTE PROCEDURE update_hidlock();
CREATE TRIGGER hidlock_update             BEFORE UPDATE           ON producers     FOR EACH ROW WHEN (OLD.latest IS DISTINCT FROM NEW.latest) EXECUTE PROCEDURE update_hidlock();
CREATE TRIGGER hidlock_update             BEFORE UPDATE           ON releases      FOR EACH ROW WHEN (OLD.latest IS DISTINCT FROM NEW.latest) EXECUTE PROCEDURE update_hidlock();
CREATE TRIGGER hidlock_update             BEFORE UPDATE           ON chars         FOR EACH ROW WHEN (OLD.latest IS DISTINCT FROM NEW.latest) EXECUTE PROCEDURE update_hidlock();
CREATE TRIGGER hidlock_update             BEFORE UPDATE           ON staff         FOR EACH ROW WHEN (OLD.latest IS DISTINCT FROM NEW.latest) EXECUTE PROCEDURE update_hidlock();

CREATE TRIGGER users_changes_update       AFTER  INSERT OR DELETE ON changes       FOR EACH ROW EXECUTE PROCEDURE update_users_cache();
CREATE TRIGGER users_votes_update         AFTER  INSERT OR DELETE ON votes         FOR EACH ROW EXECUTE PROCEDURE update_users_cache();
CREATE TRIGGER users_tags_update          AFTER  INSERT OR DELETE ON tags_vn       FOR EACH ROW EXECUTE PROCEDURE update_users_cache();

CREATE TRIGGER stats_cache_new            AFTER  INSERT           ON vn            FOR EACH ROW WHEN (NEW.hidden = FALSE) EXECUTE PROCEDURE update_stats_cache();
CREATE TRIGGER stats_cache_edit           AFTER  UPDATE           ON vn            FOR EACH ROW WHEN (OLD.hidden IS DISTINCT FROM NEW.hidden) EXECUTE PROCEDURE update_stats_cache();
CREATE TRIGGER stats_cache_new            AFTER  INSERT           ON producers     FOR EACH ROW WHEN (NEW.hidden = FALSE) EXECUTE PROCEDURE update_stats_cache();
CREATE TRIGGER stats_cache_edit           AFTER  UPDATE           ON producers     FOR EACH ROW WHEN (OLD.hidden IS DISTINCT FROM NEW.hidden) EXECUTE PROCEDURE update_stats_cache();
CREATE TRIGGER stats_cache_new            AFTER  INSERT           ON releases      FOR EACH ROW WHEN (NEW.hidden = FALSE) EXECUTE PROCEDURE update_stats_cache();
CREATE TRIGGER stats_cache_edit           AFTER  UPDATE           ON releases      FOR EACH ROW WHEN (OLD.hidden IS DISTINCT FROM NEW.hidden) EXECUTE PROCEDURE update_stats_cache();
CREATE TRIGGER stats_cache_new            AFTER  INSERT           ON chars         FOR EACH ROW WHEN (NEW.hidden = FALSE) EXECUTE PROCEDURE update_stats_cache();
CREATE TRIGGER stats_cache_edit           AFTER  UPDATE           ON chars         FOR EACH ROW WHEN (OLD.hidden IS DISTINCT FROM NEW.hidden) EXECUTE PROCEDURE update_stats_cache();
CREATE TRIGGER stats_cache_new            AFTER  INSERT           ON staff         FOR EACH ROW WHEN (NEW.hidden = FALSE) EXECUTE PROCEDURE update_stats_cache();
CREATE TRIGGER stats_cache_edit           AFTER  UPDATE           ON staff         FOR EACH ROW WHEN (OLD.hidden IS DISTINCT FROM NEW.hidden) EXECUTE PROCEDURE update_stats_cache();
CREATE TRIGGER stats_cache_new            AFTER  INSERT           ON tags          FOR EACH ROW WHEN (NEW.state = 2) EXECUTE PROCEDURE update_stats_cache();
CREATE TRIGGER stats_cache_edit           AFTER  UPDATE           ON tags          FOR EACH ROW WHEN (OLD.state IS DISTINCT FROM NEW.state) EXECUTE PROCEDURE update_stats_cache();
CREATE TRIGGER stats_cache_new            AFTER  INSERT           ON traits        FOR EACH ROW WHEN (NEW.state = 2) EXECUTE PROCEDURE update_stats_cache();
CREATE TRIGGER stats_cache_edit           AFTER  UPDATE           ON traits        FOR EACH ROW WHEN (OLD.state IS DISTINCT FROM NEW.state) EXECUTE PROCEDURE update_stats_cache();
CREATE TRIGGER stats_cache_new            AFTER  INSERT           ON threads       FOR EACH ROW WHEN (NEW.hidden = FALSE) EXECUTE PROCEDURE update_stats_cache();
CREATE TRIGGER stats_cache_edit           AFTER  UPDATE           ON threads       FOR EACH ROW WHEN (OLD.hidden IS DISTINCT FROM NEW.hidden) EXECUTE PROCEDURE update_stats_cache();
CREATE TRIGGER stats_cache_new            AFTER  INSERT           ON threads_posts FOR EACH ROW WHEN (NEW.hidden = FALSE) EXECUTE PROCEDURE update_stats_cache();
CREATE TRIGGER stats_cache_edit           AFTER  UPDATE           ON threads_posts FOR EACH ROW WHEN (OLD.hidden IS DISTINCT FROM NEW.hidden) EXECUTE PROCEDURE update_stats_cache();
CREATE TRIGGER stats_cache                AFTER  INSERT OR DELETE ON users         FOR EACH ROW EXECUTE PROCEDURE update_stats_cache();

CREATE TRIGGER vn_anime_aid_new           BEFORE INSERT           ON vn_anime      FOR EACH ROW EXECUTE PROCEDURE vn_anime_aid();
CREATE TRIGGER vn_anime_aid_edit          BEFORE UPDATE           ON vn_anime      FOR EACH ROW WHEN (OLD.aid IS DISTINCT FROM NEW.aid) EXECUTE PROCEDURE vn_anime_aid();

CREATE TRIGGER anime_fetch_notify         AFTER  INSERT OR UPDATE ON anime         FOR EACH ROW WHEN (NEW.lastfetch IS NULL) EXECUTE PROCEDURE anime_fetch_notify();

CREATE TRIGGER vn_relgraph_notify AFTER UPDATE ON vn FOR EACH ROW
  WHEN (OLD.rgraph      IS DISTINCT FROM NEW.rgraph
     OR OLD.latest      IS DISTINCT FROM NEW.latest
     OR OLD.c_released  IS DISTINCT FROM NEW.c_released
     OR OLD.c_languages IS DISTINCT FROM NEW.c_languages
  ) EXECUTE PROCEDURE vn_relgraph_notify();

CREATE TRIGGER producer_relgraph_notify AFTER UPDATE ON producers FOR EACH ROW
  WHEN (OLD.rgraph IS DISTINCT FROM NEW.rgraph
     OR OLD.latest IS DISTINCT FROM NEW.latest
  ) EXECUTE PROCEDURE producer_relgraph_notify();

CREATE TRIGGER insert_notify              AFTER  INSERT           ON changes       FOR EACH STATEMENT EXECUTE PROCEDURE insert_notify();
CREATE TRIGGER insert_notify              AFTER  INSERT           ON threads_posts FOR EACH STATEMENT EXECUTE PROCEDURE insert_notify();
CREATE TRIGGER insert_notify              AFTER  INSERT           ON tags          FOR EACH STATEMENT EXECUTE PROCEDURE insert_notify();
CREATE TRIGGER insert_notify              AFTER  INSERT           ON traits        FOR EACH STATEMENT EXECUTE PROCEDURE insert_notify();

CREATE TRIGGER release_vncache_update AFTER UPDATE ON releases FOR EACH ROW
  WHEN (OLD.latest IS DISTINCT FROM NEW.latest OR OLD.hidden IS DISTINCT FROM NEW.hidden)
  EXECUTE PROCEDURE release_vncache_update();

CREATE TRIGGER notify_pm                  AFTER  INSERT           ON threads_posts FOR EACH ROW EXECUTE PROCEDURE notify_pm();
CREATE TRIGGER notify_dbdel               AFTER  UPDATE           ON vn            FOR EACH ROW WHEN (NOT OLD.hidden AND NEW.hidden) EXECUTE PROCEDURE notify_dbdel();
CREATE TRIGGER notify_dbdel               AFTER  UPDATE           ON producers     FOR EACH ROW WHEN (NOT OLD.hidden AND NEW.hidden) EXECUTE PROCEDURE notify_dbdel();
CREATE TRIGGER notify_dbdel               AFTER  UPDATE           ON releases      FOR EACH ROW WHEN (NOT OLD.hidden AND NEW.hidden) EXECUTE PROCEDURE notify_dbdel();
CREATE TRIGGER notify_dbdel               AFTER  UPDATE           ON chars         FOR EACH ROW WHEN (NOT OLD.hidden AND NEW.hidden) EXECUTE PROCEDURE notify_dbdel();
CREATE TRIGGER notify_dbdel               AFTER  UPDATE           ON staff         FOR EACH ROW WHEN (NOT OLD.hidden AND NEW.hidden) EXECUTE PROCEDURE notify_dbdel();
CREATE TRIGGER notify_listdel             AFTER  UPDATE           ON vn            FOR EACH ROW WHEN (NOT OLD.hidden AND NEW.hidden) EXECUTE PROCEDURE notify_listdel();
CREATE TRIGGER notify_listdel             AFTER  UPDATE           ON releases      FOR EACH ROW WHEN (NOT OLD.hidden AND NEW.hidden) EXECUTE PROCEDURE notify_listdel();
CREATE TRIGGER notify_dbedit              AFTER  UPDATE           ON vn            FOR EACH ROW WHEN (OLD.latest IS DISTINCT FROM NEW.latest AND NOT NEW.hidden) EXECUTE PROCEDURE notify_dbedit();
CREATE TRIGGER notify_dbedit              AFTER  UPDATE           ON producers     FOR EACH ROW WHEN (OLD.latest IS DISTINCT FROM NEW.latest AND NOT NEW.hidden) EXECUTE PROCEDURE notify_dbedit();
CREATE TRIGGER notify_dbedit              AFTER  UPDATE           ON releases      FOR EACH ROW WHEN (OLD.latest IS DISTINCT FROM NEW.latest AND NOT NEW.hidden) EXECUTE PROCEDURE notify_dbedit();
CREATE TRIGGER notify_dbedit              AFTER  UPDATE           ON chars         FOR EACH ROW WHEN (OLD.latest IS DISTINCT FROM NEW.latest AND NOT NEW.hidden) EXECUTE PROCEDURE notify_dbedit();
CREATE TRIGGER notify_dbedit              AFTER  UPDATE           ON staff         FOR EACH ROW WHEN (OLD.latest IS DISTINCT FROM NEW.latest AND NOT NEW.hidden) EXECUTE PROCEDURE notify_dbedit();
CREATE TRIGGER notify_announce            AFTER  INSERT           ON threads_posts FOR EACH ROW WHEN (NEW.num = 1) EXECUTE PROCEDURE notify_announce();

CREATE TRIGGER vn_vnsearch_notify AFTER UPDATE ON vn FOR EACH ROW
  WHEN (OLD.c_search IS NOT NULL AND NEW.c_search IS NULL
     OR NEW.latest IS DISTINCT FROM OLD.latest
  ) EXECUTE PROCEDURE vn_vnsearch_notify();
CREATE TRIGGER vn_vnsearch_notify AFTER UPDATE ON releases FOR EACH ROW
  WHEN (NEW.hidden IS DISTINCT FROM OLD.hidden OR NEW.latest IS DISTINCT FROM OLD.latest)
  EXECUTE PROCEDURE vn_vnsearch_notify();

CREATE CONSTRAINT TRIGGER update_vnlist_rlist AFTER DELETE ON vnlists DEFERRABLE FOR EACH ROW EXECUTE PROCEDURE update_vnlist_rlist();
CREATE CONSTRAINT TRIGGER update_vnlist_rlist AFTER INSERT ON rlists  DEFERRABLE FOR EACH ROW EXECUTE PROCEDURE update_vnlist_rlist();


-- Sequences used for ID generation of items not in the DB
CREATE SEQUENCE covers_seq;
CREATE SEQUENCE charimg_seq;


-- Rows that are assumed to be available
INSERT INTO users (id, username, mail, perm) VALUES (0, 'deleted', 'del@vndb.org', 0);
INSERT INTO users (username, mail, perm)     VALUES ('multi', 'multi@vndb.org', 0);
INSERT INTO users_prefs (uid, key, value)    VALUES (0, 'notify_nodbedit', '1');
INSERT INTO users_prefs (uid, key, value)    VALUES (1, 'notify_nodbedit', '1');

INSERT INTO stats_cache (section, count) VALUES
  ('users',         1),
  ('vn',            0),
  ('producers',     0),
  ('releases',      0),
  ('chars',         0),
  ('staff',         0),
  ('tags',          0),
  ('traits',        0),
  ('threads',       0),
  ('threads_posts', 0);

