
package VNDB;

our(%O, %S, $ROOT);


# options for YAWF
our %O = (
  db_login  => [ 'dbi:Pg:dbname=vndb', 'vndb', 'passwd' ],
  debug     => 1,
  logfile   => $ROOT.'/data/log/vndb.log',
);


# VNDB-specific options (object_data)
our %S = (%S,
  version         => `cd $VNDB::ROOT; git describe` =~ /^(.+)$/ && $1,
  url             => 'http://vndb.org',
  url_static      => 'http://s.vndb.org',
  skin_default    => 'angel',
  cookie_domain   => '.vndb.org',
  cookie_prefix   => 'vndb_',
  global_salt     => 'any-private-string-here',
  form_salt       => 'a-different-private-string-here',
  regen_static    => 0,
  source_url      => 'http://git.blicky.net/vndb.git/?h=master',
  admin_email     => 'contact@vndb.org',
  scr_size        => [ 136, 102 ], # w*h of screenshot thumbnails
  cv_size         => [ 256, 400 ], # max. w*h of cover images
  user_ranks      => [
       # allowed actions                                              # DB number
    [qw| hist                                                     |], # 0
    [qw| hist                                                     |], # 1
    [qw| hist board                                               |], # 2
    [qw| hist board edit tag                                      |], # 3
    [qw| hist board boardmod edit tag mod lock del tagmod         |], # 4
    [qw| hist board boardmod edit tag mod lock del tagmod usermod |], # 5
  ],
  languages       => [qw|cs da de en es fi fr hu it ja ko nl no pl pt-br pt-pt ru sk sv tr vi zh|],
  producer_types  => [qw|co in ng|],
  discussion_boards => [qw|an db ge v p u|], # <- note that some properties of these boards are hard-coded
  vn_lengths      => [ 0..5 ],
  anime_types     => [qw|tv ova mov oth web spe mv|],
  vn_relations    => {
  # id   => [ order, reverse ]
    seq  => [ 0, 'preq' ],
    preq => [ 1, 'seq'  ],
    set  => [ 2, 'set'  ],
    alt  => [ 3, 'alt'  ],
    char => [ 4, 'char' ],
    side => [ 5, 'par'  ],
    par  => [ 6, 'side' ],
    ser  => [ 7, 'ser'  ],
    fan  => [ 8, 'orig' ],
    orig => [ 9, 'fan'  ],
  },
  prod_relations  => {
    'old' => [ 0, 'new' ],
    'new' => [ 1, 'old' ],
    'spa' => [ 2, 'ori' ],
    'ori' => [ 3, 'spa' ],
    'sub' => [ 4, 'par' ],
    'par' => [ 5, 'sub' ],
    'imp' => [ 6, 'ipa' ],
    'ipa' => [ 7, 'imp' ],
  },
  age_ratings     => [-1, 0, 6..18],
  release_types   => [qw|complete partial trial|],
  platforms       => [qw|win dos lin mac ios dvd gba msx nds nes p98 psp ps1 ps2 ps3 drc sat sfc wii xb3 oth|],
  media           => {
   #DB     qty?
    cd  => 1,
    dvd => 1,
    gdr => 1,
    blr => 1,
    flp => 1,
    mrt => 1,
    mem => 1,
    umd => 1,
    nod => 1,
    in  => 0,
    otc => 0
  },
  resolutions     => [
    [ '_scrres_unknown', '' ],
    [ '_scrres_nonstandard', '' ],
    [ '640x480',      '4:3' ],
    [ '800x600',      '4:3' ],
    [ '1024x768',     '4:3' ],
    [ '1600x1200',    '4:3' ],
    [ '640x400',      '_scrres_ws' ],
    [ '1024x576',     '_scrres_ws' ],
    [ '1024x600',     '_scrres_ws' ],
    [ '1024x640',     '_scrres_ws' ],
    [ '1280x720',     '_scrres_ws' ],
    [ '1280x800',     '_scrres_ws' ],
    [ '1920x1080',    '_scrres_ws' ],
  ],
  voiced          => [ 0..4 ],
  animated        => [ 0..4 ],
  wishlist_status => [ 0..3 ],
  rlist_status    => [ 0..4 ], # 2 = hardcoded 'OK'
  vnlist_status   => [ 0..4 ],
  atom_feeds => { # num_entries, title, id
    announcements => [ 10, 'VNDB Site Announcements', '/t/an' ],
    changes       => [ 25, 'VNDB Recent Changes', '/hist' ],
    posts         => [ 25, 'VNDB Recent Posts', '/t' ],
  },
);


# Multi-specific options (Multi also uses some options in %S and %O)
our %M = (
  log_dir   => $ROOT.'/data/log',
  modules   => {
    #API         => {},  # disabled by default, not really needed
    Feed        => {},
    RG          => {},
    Image       => {},
    #Anime       => {},  # disabled by default, requires AniDB username/pass
    Maintenance => {},
    #IRC         => {},  # disabled by default, no need to run an IRC bot when debugging
  },
);


# allow the settings to be overwritten in config.pl
require $ROOT.'/data/config.pl' if -f $ROOT.'/data/config.pl';

1;


