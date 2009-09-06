
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
  global_salt     => 'any-private-string-here',
  source_url      => 'http://git.blicky.net/vndb.git/?h=master',
  admin_email     => 'contact@vndb.org',
  user_ranks      => [
       # allowed actions                                              # DB number
    [qw| hist                                                     |], # 0
    [qw| hist                                                     |], # 1
    [qw| hist board                                               |], # 2
    [qw| hist board edit tag                                      |], # 3
    [qw| hist board boardmod edit tag mod lock del tagmod         |], # 4
    [qw| hist board boardmod edit tag mod lock del tagmod usermod |], # 5
  ],
  languages       => [qw|cs da de en es fi fr it ja ko nl no pl pt ru sv tr vi zh|],
  producer_types  => [qw|co in ng|],
  discussion_boards => [qw|an db v p u|],
  vn_lengths      => [
    [ 'Unknown',    '',              '' ],
    [ 'Very short', '< 2 hours',     'OMGWTFOTL, A Dream of Summer' ],
    [ 'Short',      '2 - 10 hours',  'Narcissu, Planetarian' ],
    [ 'Medium',     '10 - 30 hours', 'Kana: Little Sister' ],
    [ 'Long',       '30 - 50 hours', 'Tsukihime' ],
    [ 'Very long',  '> 50 hours',    'Clannad' ],
  ],
  anime_types     => [
    # AniDB anime type starts counting at 1, 0 = unknown
    #   we start counting at 0, with NULL being unknown
    'TV Series',
    'OVA',
    'Movie',
    'Other',
    'Web',
    'TV Special',
    'Music Video',
  ],
  vn_relations    => [
    # Name,           Reverse--
    [ 'Sequel',              0 ],
    [ 'Prequel',             1 ],
    [ 'Same setting',        0 ],
    [ 'Alternative version', 0 ],
    [ 'Shares characters',   0 ],
    [ 'Side story',          0 ],
    [ 'Parent story',        1 ],
    [ 'Same series',         0 ],
    [ 'Fandisc',             0 ],
    [ 'Original game',       1 ],
  ],
  age_ratings     => {
    -1 => [ 'Unknown' ],
    0  => [ 'All ages' ,'CERO A' ],
    6  => [ '6+' ],
    7  => [ '7+' ],
    8  => [ '8+' ],
    9  => [ '9+' ],
    10 => [ '10+' ],
    11 => [ '11+' ],
    12 => [ '12+', 'CERO B' ],
    13 => [ '13+' ],
    14 => [ '14+' ],
    15 => [ '15+', 'CERO C' ],
    16 => [ '16+' ],
    17 => [ '17+', 'CERO D' ],
    18 => [ '18+', 'CERO Z' ],
  },
  release_types   => [0..2],
  platforms       => [qw|win lin mac dvd gba msx nds nes psp ps1 ps2 ps3 drc sfc wii xb3 oth|],
  media           => {
   #DB       display            qty
    cd  => [ 'CD',                1 ],
    dvd => [ 'DVD',               1 ],
    gdr => [ 'GD',                1 ],
    blr => [ 'Blu-ray',           1 ],
    flp => [ 'Floppy',            1 ],
    mrt => [ 'Cartridge',         1 ],
    mem => [ 'Memory card',       1 ],
    umd => [ 'UMD',               1 ],
    nod => [ 'Nintendo Optical Disk', 1 ],
    in  => [ 'Internet download', 0 ],
    otc => [ 'Other',             0 ],
  },
  resolutions     => [
    [ 'Unknown / console / handheld', '' ],
    [ 'Custom',            '' ],
    [ '640x480 (480p)',    '4:3' ],
    [ '800x600',           '4:3' ],
    [ '1024x768',          '4:3' ],
    [ '1600x1200',         '4:3' ],
    [ '640x400',           'widescreen' ],
    [ '1024x600',          'widescreen' ],
    [ '1024x640',          'widescreen' ],
    [ '1280x720 (720p)',   'widescreen' ],
    [ '1920x1080 (1080p)', 'widescreen' ],
  ],
  voiced          => [ 0..4 ],
  animated        => [ 0..4 ],
  wishlist_status => [
    'high',
    'medium',
    'low',
    'blacklist',
  ],
  # note: keep these synchronised in script.js
  vn_rstat        => [
    'Unknown',
    'Pending',
    'Obtained', # hardcoded
    'On loan',
    'Deleted',
  ],
  vn_vstat        => [
    'Unknown',
    'Playing',
    'Finished', # hardcoded
    'Stalled',
    'Dropped',
  ],
);


# Multi-specific options (Multi also uses some options in %S and %O)
our %M = (
  log_dir   => $ROOT.'/data/log',
  modules   => {
    RG          => {},
    Image       => {},
    Sitemap     => {},
    #Anime       => {},  # disabled by default, requires AniDB username/pass
    Maintenance => {},
    #IRC         => {},  # disabled by default, no need to run an IRC bot when debugging
  },
);


# allow the settings to be overwritten in config.pl
require $ROOT.'/data/config.pl' if -f $ROOT.'/data/config.pl';

1;


