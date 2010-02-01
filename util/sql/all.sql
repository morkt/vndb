-- NOTE: Make sure you're cd'ed in the vndb root directory before running this script

-- plpgsql is required for our (trigger) functions
CREATE LANGUAGE plpgsql;


-- data types

CREATE TYPE anime_type        AS ENUM ('tv', 'ova', 'mov', 'oth', 'web', 'spe', 'mv');
CREATE TYPE dbentry_type      AS ENUM ('v', 'r', 'p');
CREATE TYPE edit_rettype      AS (iid integer, cid integer, rev integer);
CREATE TYPE medium            AS ENUM ('cd', 'dvd', 'gdr', 'blr', 'flp', 'mrt', 'mem', 'umd', 'nod', 'in', 'otc');
CREATE TYPE notification_ntype AS ENUM ('pm');
CREATE TYPE notification_ltype AS ENUM ('t');
CREATE TYPE producer_relation AS ENUM ('old', 'new', 'sub', 'par', 'imp', 'ipa', 'spa', 'ori');
CREATE TYPE release_type      AS ENUM ('complete', 'partial', 'trial');
CREATE TYPE vn_relation       AS ENUM ('seq', 'preq', 'set', 'alt', 'char', 'side', 'par', 'ser', 'fan', 'orig');


-- schema

\i util/sql/schema.sql


-- functions

\i util/sql/func.sql


-- triggers

CREATE TRIGGER hidlock_update             BEFORE UPDATE           ON vn            FOR EACH ROW EXECUTE PROCEDURE update_hidlock();
CREATE TRIGGER hidlock_update             BEFORE UPDATE           ON producers     FOR EACH ROW EXECUTE PROCEDURE update_hidlock();
CREATE TRIGGER hidlock_update             BEFORE UPDATE           ON releases      FOR EACH ROW EXECUTE PROCEDURE update_hidlock();

CREATE TRIGGER users_changes_update       AFTER  INSERT OR DELETE ON changes       FOR EACH ROW EXECUTE PROCEDURE update_users_cache();
CREATE TRIGGER users_votes_update         AFTER  INSERT OR DELETE ON votes         FOR EACH ROW EXECUTE PROCEDURE update_users_cache();
CREATE TRIGGER users_tags_update          AFTER  INSERT OR DELETE ON tags_vn       FOR EACH ROW EXECUTE PROCEDURE update_users_cache();

CREATE TRIGGER vn_stats_update            AFTER  INSERT OR UPDATE ON vn            FOR EACH ROW EXECUTE PROCEDURE update_stats_cache();
CREATE TRIGGER producers_stats_update     AFTER  INSERT OR UPDATE ON producers     FOR EACH ROW EXECUTE PROCEDURE update_stats_cache();
CREATE TRIGGER releases_stats_update      AFTER  INSERT OR UPDATE ON releases      FOR EACH ROW EXECUTE PROCEDURE update_stats_cache();
CREATE TRIGGER threads_stats_update       AFTER  INSERT OR UPDATE ON threads       FOR EACH ROW EXECUTE PROCEDURE update_stats_cache();
CREATE TRIGGER threads_posts_stats_update AFTER  INSERT OR UPDATE ON threads_posts FOR EACH ROW EXECUTE PROCEDURE update_stats_cache();
CREATE TRIGGER users_stats_update         AFTER  INSERT OR DELETE ON users         FOR EACH ROW EXECUTE PROCEDURE update_stats_cache();

CREATE TRIGGER vn_anime_aid               BEFORE INSERT OR UPDATE ON vn_anime      FOR EACH ROW EXECUTE PROCEDURE vn_anime_aid();

CREATE TRIGGER anime_fetch_notify         AFTER  INSERT OR UPDATE ON anime         FOR EACH ROW EXECUTE PROCEDURE anime_fetch_notify();

CREATE TRIGGER vn_rev_image_notify        AFTER  INSERT OR UPDATE ON vn_rev        FOR EACH ROW EXECUTE PROCEDURE vn_rev_image_notify();

CREATE TRIGGER screenshot_process_notify  AFTER  INSERT OR UPDATE ON screenshots   FOR EACH ROW EXECUTE PROCEDURE screenshot_process_notify();

CREATE TRIGGER vn_relgraph_notify         AFTER  UPDATE           ON vn            FOR EACH ROW EXECUTE PROCEDURE vn_relgraph_notify();

CREATE TRIGGER producer_relgraph_notify   AFTER  UPDATE           ON producers     FOR EACH ROW EXECUTE PROCEDURE producer_relgraph_notify();

CREATE TRIGGER insert_notify              AFTER  INSERT           ON changes       FOR EACH STATEMENT EXECUTE PROCEDURE insert_notify();
CREATE TRIGGER insert_notify              AFTER  INSERT           ON threads_posts FOR EACH STATEMENT EXECUTE PROCEDURE insert_notify();
CREATE TRIGGER insert_notify              AFTER  INSERT           ON tags          FOR EACH STATEMENT EXECUTE PROCEDURE insert_notify();

CREATE TRIGGER release_vncache_update     AFTER  UPDATE           ON releases      FOR EACH ROW EXECUTE PROCEDURE release_vncache_update();

CREATE TRIGGER notify_pm                  AFTER  INSERT           ON threads_posts FOR EACH ROW EXECUTE PROCEDURE notify_pm();


-- Sequences used for ID generation of items not in the DB
CREATE SEQUENCE covers_seq;


-- Rows that are assumed to be available
INSERT INTO users (id, username, mail, rank) VALUES (0, 'deleted', 'del@vndb.org', 0);
INSERT INTO users (username, mail, rank)     VALUES ('multi', 'multi@vndb.org', 0);

INSERT INTO stats_cache (section, count) VALUES
  ('users',         1),
  ('vn',            0),
  ('producers',     0),
  ('releases',      0),
  ('threads',       0),
  ('threads_posts', 0);

