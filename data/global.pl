
package VNDB;

our(%O, %S, $ROOT);


# options for YAWF
our %O = (
  db_login  => [ 'dbi:Pg:dbname=vndb', 'vndb', 'passwd' ],
  debug     => 1,
  logfile   => $ROOT.'/data/log/vndb.log',
);


# VNDB-specific options (object_data)
our %S = (
  version         => 'git-'.substr(`cd $VNDB::ROOT; git rev-parse HEAD`, 0, 12),
  url             => 'http://vndb.org',
  url_static      => 'http://s.vndb.org',
  site_title      => 'Yet another VNDB clone',
  cookie_domain   => '.vndb.org',
  cookie_key      => 'any-private-string-here',
  sharedmem_key   => 'VNDB',
  user_ranks      => [
       # rankname   allowed actions                                   # DB number
    [qw| visitor    hist                                          |], # 0
    [qw| loser      hist                                          |], # 1
    [qw| user       hist board edit                               |], # 2
    [qw| mod        hist board boardmod edit mod lock del         |], # 3
    [qw| admin      hist board boardmod edit mod lock del usermod |], # 4
  ],
  languages       => {
    cs  => q|Czech|,
    da  => q|Danish|,
    de  => q|German|,
    en  => q|English|,
    es  => q|Spanish|,
    fi  => q|Finnish|,
    fr  => q|French|,
    it  => q|Italian|,
    ja  => q|Japanese|,
    ko  => q|Korean|,
    nl  => q|Dutch|,
    no  => q|Norwegian|,
    pl  => q|Polish|,
    pt  => q|Portuguese|,
    ru  => q|Russian|,
    sv  => q|Swedish|,
    tr  => q|Turkish|,
    zh  => q|Chinese|,
  },
  producer_types  => {
    co => 'Company',
    in => 'Individual',
    ng => 'Amateur group',
  },
  discussion_tags => {
    an => 'Announcements',    # 0   - usage restricted to boardmods
    db => 'VNDB Discussions', # 0
    v  => 'Visual novels',    # vid
    p  => 'Producers',        # pid
    u  => 'Users',            # uid
  },
  vn_lengths      => [
    [ 'Unkown',     '',              '' ],
    [ 'Very short', '< 2 hours',     'OMGWTFOTL, A Dream of Summer' ],
    [ 'Short',      '2 - 10 hours',  'Narcissu, Planetarian' ],
    [ 'Medium',     '10 - 30 hours', 'Kana: Little Sister' ],
    [ 'Long',       '30 - 50 hours', 'Tsukihime' ],
    [ 'Very long',  '> 50 hours',    'Clannad' ],
  ],
  categories      => {
    g => [ 'Gameplay', {
      aa => 'NVL',     # 0..1
      ab => 'ADV',     # 0..1
      ac => "Act\x{200B}ion",      # Ugliest. Hack. Ever.
      rp => 'RPG',
      st => 'Strategy',
      si => 'Simulation',
    }, 2 ],
    p => [ 'Plot', {        # 0..1
      li => 'Linear',
      br => 'Branching',
    }, 3 ],
    e => [ 'Elements', {
      ac => 'Action',
      co => 'Comedy',
      dr => 'Drama',
      fa => 'Fantasy',
      ho => 'Horror',
      my => 'Mystery',
      ro => 'Romance',
      sc => 'School Life',
      sf => 'SciFi', 
      sj => 'Shoujo Ai',
      sn => 'Shounen Ai',
    }, 1 ],
    t => [ 'Time', {        # 0..1
      fu => 'Future',
      pa => 'Past', 
      pr => 'Present',
    }, 4 ],
    l => [ 'Place', {       # 0..1
      ea => 'Earth', 
      fa => "Fant\x{200B}asy world",
      sp => 'Space',
    }, 5 ],
    h => [ 'Protagonist', { # 0..1
      fa => 'Male',
      fe => "Fem\x{200B}ale",
    }, 6 ],
    s => [ 'Sexual content', {
      aa => 'Sexual content',
      be => 'Bestiality',
      in => 'Incest',
      lo => 'Lolicon',
      sh => 'Shotacon',
      ya => 'Yaoi',
      yu => 'Yuri',
      ra => 'Rape',
    }, 7 ],
  },
  anime_types     => [
    # VNDB          AniDB
    [ 'unknown',    'unknown',    ],
    [ 'TV',         'TV Series'   ],
    [ 'OVA',        'OVA'         ],
    [ 'Movie',      'Movie'       ],
    [ 'unknown',    'Other'       ],
    [ 'unknown',    'Web'         ],
    [ 'TV Special', 'TV Special'  ],
    [ 'unknown',    'Music Video' ],
  ],
  vn_relations    => [
    # Name,           Reverse--
    [ 'Sequel',              0 ],
    [ 'Prequel',             1 ],
    [ 'Same setting',        0 ],
    [ 'Alternative setting', 0 ],
    [ 'Alternative version', 0 ],
    [ 'Same characters',     0 ],
    [ 'Side story',          0 ],
    [ 'Parent story',        1 ],
    [ 'Summary',             0 ],
    [ 'Full story',          1 ],
    [ 'Other',               0 ],
  ],
  age_ratings     => {
    -1 => 'Unknown',
    0  => 'All ages',
    map { $_ => $_.'+' } 6..18
  },
  release_types   => [
    'Complete',
    'Partial',
    'Trial'
  ],
  platforms       => {
    win => 'Windows',
    lin => 'Linux',
    mac => 'Mac OS',
    dvd => 'DVD Player',
    gba => 'Game Boy Advance',
    msx => 'MSX',
    nds => 'Nintendo DS',
    nes => 'Famicom',
    psp => 'Playstation Portable',
    ps1 => 'Playstation 1',
    ps2 => 'Playstation 2',
    ps3 => 'Playstation 3',
    drc => 'Dreamcast',
    sfc => 'Super Nintendo',
    wii => 'Nintendo Wii',
    xb3 => 'Xbox 360',
    oth => 'Other'
  },
  media           => {
   #DB       display            qty
    cd  => [ 'CD',                1 ],
    dvd => [ 'DVD',               1 ],
    gdr => [ 'GD-ROM',            1 ],
    blr => [ 'Blu-Ray disk',      1 ],
    in  => [ 'Internet download', 0 ],
    pa  => [ 'Patch',             0 ],
    otc => [ 'Other (console)',   0 ],
  },
);


# Multi-specific options (Multi also uses some options in %S and %O)
our %M = (
  log_dir   => $ROOT.'/data/log',
  log_level => 3,        # 3: dbg, 2: wrn, 1: err
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


