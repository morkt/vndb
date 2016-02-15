-- NOTE: Make sure you're cd'ed in the vndb root directory before running this script


-- data types

CREATE TYPE anime_type        AS ENUM ('tv', 'ova', 'mov', 'oth', 'web', 'spe', 'mv');
CREATE TYPE blood_type        AS ENUM ('unknown', 'a', 'b', 'ab', 'o');
CREATE TYPE board_type        AS ENUM ('an', 'db', 'ge', 'v', 'p', 'u');
CREATE TYPE char_role         AS ENUM ('main', 'primary', 'side', 'appears');
CREATE TYPE credit_type       AS ENUM ('scenario', 'chardesign', 'art', 'music', 'songs', 'director', 'staff');
CREATE TYPE dbentry_type      AS ENUM ('v', 'r', 'p', 'c', 's');
CREATE TYPE edit_rettype      AS (itemid integer, chid integer, rev integer);
CREATE TYPE gender            AS ENUM ('unknown', 'm', 'f', 'b');
CREATE TYPE language          AS ENUM ('ar', 'ca', 'cs', 'da', 'de', 'en', 'es', 'fi', 'fr', 'he', 'hu', 'id', 'it', 'ja', 'ko', 'nl', 'no', 'pl', 'pt-pt', 'pt-br', 'ro', 'ru', 'sk', 'sv', 'ta', 'tr', 'uk', 'vi', 'zh');
CREATE TYPE medium            AS ENUM ('cd', 'dvd', 'gdr', 'blr', 'flp', 'mrt', 'mem', 'umd', 'nod', 'in', 'otc');
CREATE TYPE notification_ntype AS ENUM ('pm', 'dbdel', 'listdel', 'dbedit', 'announce');
CREATE TYPE notification_ltype AS ENUM ('v', 'r', 'p', 'c', 't', 's');
CREATE TYPE platform          AS ENUM ('win', 'dos', 'lin', 'mac', 'ios', 'and', 'dvd', 'bdp', 'fmt', 'gba', 'gbc', 'msx', 'nds', 'nes', 'p88', 'p98', 'pce', 'pcf', 'psp', 'ps1', 'ps2', 'ps3', 'ps4', 'psv', 'drc', 'sat', 'sfc', 'wii', 'n3d', 'x68', 'xb1', 'xb3', 'xbo', 'web', 'oth');
CREATE TYPE prefs_key         AS ENUM ('l10n', 'skin', 'customcss', 'filter_vn', 'filter_release', 'show_nsfw', 'hide_list', 'notify_nodbedit', 'notify_announce', 'vn_list_own', 'vn_list_wish', 'tags_all', 'tags_cat', 'spoilers', 'traits_sexual');
CREATE TYPE producer_type     AS ENUM ('co', 'in', 'ng');
CREATE TYPE producer_relation AS ENUM ('old', 'new', 'sub', 'par', 'imp', 'ipa', 'spa', 'ori');
CREATE TYPE release_type      AS ENUM ('complete', 'partial', 'trial');
CREATE TYPE tag_category      AS ENUM('cont', 'ero', 'tech');
CREATE TYPE vn_relation       AS ENUM ('seq', 'preq', 'set', 'alt', 'char', 'side', 'par', 'ser', 'fan', 'orig');


-- schema

\i util/sql/schema.sql


-- functions

\i util/sql/func.sql

-- auto-generated editing functions

\i util/sql/editfunc.sql

-- constraints & indices

\i util/sql/tableattrs.sql

-- triggers

\i util/sql/triggers.sql

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

