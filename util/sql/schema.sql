

-- anime
CREATE TABLE anime (
  id integer NOT NULL PRIMARY KEY,
  year smallint,
  ann_id integer,
  nfo_id varchar(200),
  type anime_type,
  title_romaji,
  title_kanji,
  lastfetch timestamptz
);

-- changes
CREATE TABLE changes (
  id SERIAL NOT NULL PRIMARY KEY,
  type dbentry_type NOT NULL,
  rev integer NOT NULL DEFAULT 1,
  added timestamptz NOT NULL DEFAULT NOW(),
  requester integer NOT NULL DEFAULT 0,
  ip inet NOT NULL DEFAULT '0.0.0.0',
  comments text NOT NULL DEFAULT '',
  ihid boolean NOT NULL DEFAULT FALSE,
  ilock boolean NOT NULL DEFAULT FALSE
);

-- notifications
CREATE TABLE notifications (
  id serial PRIMARY KEY NOT NULL,
  uid integer NOT NULL,
  date timestamptz NOT NULL DEFAULT NOW(),
  read timestamptz,
  ntype notification_ntype NOT NULL,
  ltype notification_ltype NOT NULL,
  iid integer NOT NULL,
  subid integer,
  c_title text NOT NULL,
  c_byuser integer NOT NULL DEFAULT 0
);

-- producers
CREATE TABLE producers (
  id SERIAL NOT NULL PRIMARY KEY,
  latest integer NOT NULL DEFAULT 0,
  locked boolean NOT NULL DEFAULT FALSE,
  hidden boolean NOT NULL DEFAULT FALSE,
  rgraph integer
);

-- producers_relations
CREATE TABLE producers_relations (
  pid1 integer NOT NULL,
  pid2 integer NOT NULL,
  relation producer_relation NOT NULL,
  PRIMARY KEY(pid1, pid2)
);

-- producers_rev
CREATE TABLE producers_rev (
  id integer NOT NULL PRIMARY KEY,
  pid integer NOT NULL DEFAULT 0,
  type character(2) NOT NULL DEFAULT 'co',
  name varchar(200) NOT NULL DEFAULT '',
  original varchar(200) NOT NULL DEFAULT '',
  website varchar(250) NOT NULL DEFAULT '',
  lang language NOT NULL DEFAULT 'ja',
  "desc" text NOT NULL DEFAULT '',
  alias varchar(500) NOT NULL DEFAULT '',
  l_wp varchar(150)
);

-- quotes
CREATE TABLE quotes (
  vid integer NOT NULL,
  quote varchar(250) NOT NULL,
  PRIMARY KEY(vid, quote)
);

-- releases
CREATE TABLE releases (
  id SERIAL NOT NULL PRIMARY KEY,
  latest integer NOT NULL DEFAULT 0,
  locked boolean NOT NULL DEFAULT FALSE,
  hidden boolean NOT NULL DEFAULT FALSE
);

-- releases_lang
CREATE TABLE releases_lang (
  rid integer NOT NULL,
  lang language NOT NULL,
  PRIMARY KEY(rid, lang)
);

-- releases_media
CREATE TABLE releases_media (
  rid integer NOT NULL DEFAULT 0,
  medium medium NOT NULL,
  qty smallint NOT NULL DEFAULT 1,
  PRIMARY KEY(rid, medium, qty)
);

-- releases_platforms
CREATE TABLE releases_platforms (
  rid integer NOT NULL DEFAULT 0,
  platform character(3) NOT NULL DEFAULT 0,
  PRIMARY KEY(rid, platform)
);

-- releases_producers
CREATE TABLE releases_producers (
  rid integer NOT NULL,
  pid integer NOT NULL,
  developer boolean NOT NULL DEFAULT FALSE,
  publisher boolean NOT NULL DEFAULT TRUE,
  CHECK(developer OR publisher),
  PRIMARY KEY(pid, rid)
);

-- releases_rev
CREATE TABLE releases_rev (
  id integer NOT NULL PRIMARY KEY,
  rid integer NOT NULL DEFAULT 0,
  title varchar(250) NOT NULL DEFAULT '',
  original varchar(250) NOT NULL DEFAULT '',
  type release_type NOT NULL DEFAULT 'complete',
  website varchar(250) NOT NULL DEFAULT '',
  released integer NOT NULL DEFAULT 0,
  notes text NOT NULL DEFAULT '',
  minage smallint,
  gtin bigint NOT NULL DEFAULT 0,
  patch boolean NOT NULL DEFAULT FALSE,
  catalog varchar(50) NOT NULL DEFAULT '',
  resolution smallint NOT NULL DEFAULT 0,
  voiced smallint NOT NULL DEFAULT 0,
  freeware boolean NOT NULL DEFAULT FALSE,
  doujin boolean NOT NULL DEFAULT FALSE,
  ani_story smallint NOT NULL DEFAULT 0,
  ani_ero smallint NOT NULL DEFAULT 0
);

-- releases_vn
CREATE TABLE releases_vn (
  rid integer NOT NULL DEFAULT 0,
  vid integer NOT NULL DEFAULT 0,
  PRIMARY KEY(rid, vid)
);

-- relgraphs
CREATE TABLE relgraphs (
  id SERIAL PRIMARY KEY,
  svg xml NOT NULL
);

-- rlists
CREATE TABLE rlists (
  uid integer NOT NULL DEFAULT 0,
  rid integer NOT NULL DEFAULT 0,
  vstat smallint NOT NULL DEFAULT 0,
  rstat smallint NOT NULL DEFAULT 0,
  added timestamptz NOT NULL DEFAULT NOW(),
  PRIMARY KEY(uid, rid)
);

-- screenshots
CREATE TABLE screenshots (
  id SERIAL NOT NULL PRIMARY KEY,
  processed boolean NOT NULL DEFAULT FALSE,
  width smallint NOT NULL DEFAULT 0,
  height smallint NOT NULL DEFAULT 0
);

-- sessions
CREATE TABLE sessions (
  uid integer NOT NULL,
  token bytea NOT NULL,
  added timestamptz NOT NULL DEFAULT NOW(),
  lastused timestamptz NOT NULL DEFAULT NOW(),
  PRIMARY KEY (uid, token)
);

-- stats_cache
CREATE TABLE stats_cache (
  section varchar(25) NOT NULL PRIMARY KEY,
  count integer NOT NULL DEFAULT 0
);

-- tags
CREATE TABLE tags (
  id SERIAL NOT NULL PRIMARY KEY,
  name varchar(250) NOT NULL UNIQUE,
  description text NOT NULL DEFAULT '',
  meta boolean NOT NULL DEFAULT FALSE,
  added timestamptz NOT NULL DEFAULT NOW(),
  state smallint NOT NULL DEFAULT 0,
  c_vns integer NOT NULL DEFAULT 0,
  addedby integer NOT NULL DEFAULT 0
);

-- tags_aliases
CREATE TABLE tags_aliases (
  alias varchar(250) NOT NULL PRIMARY KEY,
  tag integer NOT NULL,
);

-- tags_parents
CREATE TABLE tags_parents (
  tag integer NOT NULL,
  parent integer NOT NULL,
  PRIMARY KEY(tag, parent)
);

-- tags_vn
CREATE TABLE tags_vn (
  tag integer NOT NULL,
  vid integer NOT NULL,
  uid integer NOT NULL,
  vote smallint NOT NULL DEFAULT 3 CHECK (vote >= -3 AND vote <= 3 AND vote <> 0),
  spoiler smallint CHECK(spoiler >= 0 AND spoiler <= 2),
  date timestamptz NOT NULL DEFAULT NOW(),
  PRIMARY KEY(tag, vid, uid)
);

-- tags_vn_inherit
CREATE TABLE tags_vn_inherit (
  tag integer NOT NULL,
  vid integer NOT NULL,
  users integer NOT NULL,
  rating real NOT NULL,
  spoiler smallint NOT NULL
);

-- threads
CREATE TABLE threads (
  id SERIAL NOT NULL PRIMARY KEY,
  title varchar(50) NOT NULL DEFAULT '',
  locked boolean NOT NULL DEFAULT FALSE,
  hidden boolean NOT NULL DEFAULT FALSE,
  count smallint NOT NULL DEFAULT 0
);

-- threads_posts
CREATE TABLE threads_posts (
  tid integer NOT NULL DEFAULT 0,
  num smallint NOT NULL DEFAULT 0,
  uid integer NOT NULL DEFAULT 0,
  date timestamptz NOT NULL DEFAULT NOW(),
  edited timestamptz,
  msg text NOT NULL DEFAULT '',
  hidden boolean NOT NULL DEFAULT FALSE,
  PRIMARY KEY(tid, num)
);

-- threads_boards
CREATE TABLE threads_boards (
  tid integer NOT NULL DEFAULT 0,
  type character(2) NOT NULL DEFAULT 0,
  iid integer NOT NULL DEFAULT 0,
  PRIMARY KEY(tid, type, iid)
);

-- users
CREATE TABLE users (
  id SERIAL NOT NULL PRIMARY KEY,
  username varchar(20) NOT NULL UNIQUE,
  mail varchar(100) NOT NULL,
  rank smallint NOT NULL DEFAULT 3,
  passwd bytea NOT NULL DEFAULT '',
  registered timestamptz NOT NULL DEFAULT NOW(),
  show_nsfw boolean NOT NULL DEFAULT FALSE,
  show_list boolean NOT NULL DEFAULT TRUE,
  c_votes integer NOT NULL DEFAULT 0,
  c_changes integer NOT NULL DEFAULT 0,
  skin varchar(128) NOT NULL DEFAULT '',
  customcss text NOT NULL DEFAULT '',
  ip inet NOT NULL DEFAULT '0.0.0.0',
  c_tags integer NOT NULL DEFAULT 0,
  salt character(9) NOT NULL DEFAULT '',
  ign_votes boolean NOT NULL DEFAULT FALSE,
  notify_dbedit boolean NOT NULL DEFAULT TRUE,
  notify_announce boolean NOT NULL DEFAULT FALSE
);

-- vn
CREATE TABLE vn (
  id SERIAL NOT NULL PRIMARY KEY,
  latest integer NOT NULL DEFAULT 0,
  locked boolean NOT NULL DEFAULT FALSE,
  hidden boolean NOT NULL DEFAULT FALSE,
  rgraph integer,
  c_released integer NOT NULL DEFAULT 0,
  c_languages language[] NOT NULL DEFAULT '{}',
  c_platforms varchar(32) NOT NULL DEFAULT '',
  c_popularity real,
  c_rating real,
  c_votecount integer NOT NULL DEFAULT 0,
  c_search text,
  c_olang language[] NOT NULL DEFAULT '{}'
);

-- vn_anime
CREATE TABLE vn_anime (
  vid integer NOT NULL,
  aid integer NOT NULL,
  PRIMARY KEY(vid, aid)
);

-- vn_relations
CREATE TABLE vn_relations (
  vid1 integer NOT NULL DEFAULT 0,
  vid2 integer NOT NULL DEFAULT 0,
  relation vn_relation NOT NULL,
  official boolean NOT NULL DEFAULT TRUE,
  PRIMARY KEY(vid1, vid2)
);

-- vn_rev
CREATE TABLE vn_rev (
  id integer NOT NULL PRIMARY KEY,
  vid integer NOT NULL DEFAULT 0,
  title varchar(250) NOT NULL DEFAULT '',
  original varchar(250) NOT NULL DEFAULT '',
  alias varchar(500) NOT NULL DEFAULT '',
  img_nsfw boolean NOT NULL DEFAULT FALSE,
  length smallint NOT NULL DEFAULT 0,
  "desc" text NOT NULL DEFAULT '',
  l_wp varchar(150) NOT NULL DEFAULT '',
  l_vnn integer NOT NULL DEFAULT 0,
  image integer NOT NULL DEFAULT 0,
  l_encubed varchar(100) NOT NULL DEFAULT '',
  l_renai varchar(100) NOT NULL DEFAULT ''
);

-- vn_screenshots
CREATE TABLE vn_screenshots (
  vid integer NOT NULL DEFAULT 0,
  scr integer NOT NULL DEFAULT 0,
  nsfw boolean NOT NULL DEFAULT FALSE,
  rid integer DEFAULT NULL,
  PRIMARY KEY(vid, scr)
);


-- vnlists
CREATE TABLE vnlists (
  uid integer NOT NULL,
  vid integer NOT NULL,
  status smallint NOT NULL DEFAULT 0,
  added TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY(uid, vid)
);

-- votes
CREATE TABLE votes (
  vid integer NOT NULL DEFAULT 0,
  uid integer NOT NULL DEFAULT 0,
  vote integer NOT NULL DEFAULT 0,
  date timestamptz NOT NULL DEFAULT NOW(),
  PRIMARY KEY(vid, uid)
);

-- wlists
CREATE TABLE wlists (
  uid integer NOT NULL DEFAULT 0,
  vid integer NOT NULL DEFAULT 0,
  wstat smallint NOT NULL DEFAULT 0,
  added timestamptz NOT NULL DEFAULT NOW(),
  PRIMARY KEY(uid, vid)
);



ALTER TABLE changes             ADD FOREIGN KEY (requester) REFERENCES users         (id) ON DELETE SET DEFAULT;
ALTER TABLE notifications       ADD FOREIGN KEY (uid)       REFERENCES users         (id) ON DELETE CASCADE;
ALTER TABLE notifications       ADD FOREIGN KEY (c_byuser)  REFERENCES users         (id) ON DELETE SET DEFAULT;
ALTER TABLE producers           ADD FOREIGN KEY (latest)    REFERENCES producers_rev (id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE producers           ADD FOREIGN KEY (rgraph)    REFERENCES relgraphs     (id);
ALTER TABLE producers_relations ADD FOREIGN KEY (pid1)      REFERENCES producers_rev (id);
ALTER TABLE producers_relations ADD FOREIGN KEY (pid2)      REFERENCES producers     (id);
ALTER TABLE producers_rev       ADD FOREIGN KEY (id)        REFERENCES changes       (id);
ALTER TABLE producers_rev       ADD FOREIGN KEY (pid)       REFERENCES producers     (id);
ALTER TABLE quotes              ADD FOREIGN KEY (vid)       REFERENCES vn            (id);
ALTER TABLE releases            ADD FOREIGN KEY (latest)    REFERENCES releases_rev  (id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE releases_lang       ADD FOREIGN KEY (rid)       REFERENCES releases_rev  (id);
ALTER TABLE releases_media      ADD FOREIGN KEY (rid)       REFERENCES releases_rev  (id);
ALTER TABLE releases_platforms  ADD FOREIGN KEY (rid)       REFERENCES releases_rev  (id);
ALTER TABLE releases_producers  ADD FOREIGN KEY (rid)       REFERENCES releases_rev  (id);
ALTER TABLE releases_producers  ADD FOREIGN KEY (pid)       REFERENCES producers     (id);
ALTER TABLE releases_rev        ADD FOREIGN KEY (id)        REFERENCES changes       (id);
ALTER TABLE releases_rev        ADD FOREIGN KEY (rid)       REFERENCES releases      (id);
ALTER TABLE releases_vn         ADD FOREIGN KEY (rid)       REFERENCES releases_rev  (id);
ALTER TABLE releases_vn         ADD FOREIGN KEY (vid)       REFERENCES vn            (id);
ALTER TABLE rlists              ADD FOREIGN KEY (uid)       REFERENCES users         (id) ON DELETE CASCADE;
ALTER TABLE rlists              ADD FOREIGN KEY (rid)       REFERENCES releases      (id);
ALTER TABLE sessions            ADD FOREIGN KEY (uid)       REFERENCES users         (id) ON DELETE CASCADE;
ALTER TABLE tags                ADD FOREIGN KEY (addedby)   REFERENCES users         (id) ON DELETE SET DEFAULT;
ALTER TABLE tags_aliases        ADD FOREIGN KEY (tag)       REFERENCES tags          (id);
ALTER TABLE tags_parents        ADD FOREIGN KEY (tag)       REFERENCES tags          (id);
ALTER TABLE tags_parents        ADD FOREIGN KEY (parent)    REFERENCES tags          (id);
ALTER TABLE tags_vn             ADD FOREIGN KEY (tag)       REFERENCES tags          (id);
ALTER TABLE tags_vn             ADD FOREIGN KEY (vid)       REFERENCES vn            (id);
ALTER TABLE tags_vn             ADD FOREIGN KEY (uid)       REFERENCES users         (id) ON DELETE CASCADE;
ALTER TABLE threads             ADD FOREIGN KEY (id, count) REFERENCES threads_posts (tid, num) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE threads_posts       ADD FOREIGN KEY (tid)       REFERENCES threads       (id);
ALTER TABLE threads_posts       ADD FOREIGN KEY (uid)       REFERENCES users         (id) ON DELETE SET DEFAULT;
ALTER TABLE threads_boards      ADD FOREIGN KEY (tid)       REFERENCES threads       (id);
ALTER TABLE vn                  ADD FOREIGN KEY (latest)    REFERENCES vn_rev        (id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE vn                  ADD FOREIGN KEY (rgraph)    REFERENCES relgraphs     (id);
ALTER TABLE vn_anime            ADD FOREIGN KEY (aid)       REFERENCES anime         (id);
ALTER TABLE vn_anime            ADD FOREIGN KEY (vid)       REFERENCES vn_rev        (id);
ALTER TABLE vn_relations        ADD FOREIGN KEY (vid1)      REFERENCES vn_rev        (id);
ALTER TABLE vn_relations        ADD FOREIGN KEY (vid2)      REFERENCES vn            (id);
ALTER TABLE vn_rev              ADD FOREIGN KEY (id)        REFERENCES changes       (id);
ALTER TABLE vn_rev              ADD FOREIGN KEY (vid)       REFERENCES vn            (id);
ALTER TABLE vn_screenshots      ADD FOREIGN KEY (vid)       REFERENCES vn_rev        (id);
ALTER TABLE vn_screenshots      ADD FOREIGN KEY (scr)       REFERENCES screenshots   (id);
ALTER TABLE vn_screenshots      ADD FOREIGN KEY (rid)       REFERENCES releases      (id);
ALTER TABLE vnlists             ADD FOREIGN KEY (uid)       REFERENCES users         (id) ON DELETE CASCADE;
ALTER TABLE vnlists             ADD FOREIGN KEY (vid)       REFERENCES vn            (id);
ALTER TABLE votes               ADD FOREIGN KEY (uid)       REFERENCES users         (id) ON DELETE CASCADE;
ALTER TABLE votes               ADD FOREIGN KEY (vid)       REFERENCES vn            (id);
ALTER TABLE wlists              ADD FOREIGN KEY (uid)       REFERENCES users         (id) ON DELETE CASCADE;
ALTER TABLE wlists              ADD FOREIGN KEY (vid)       REFERENCES vn            (id);

