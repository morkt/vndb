package VNDB;

# This file is used to override config options in global.pl.
# You can override anything you want.

%O = (
  %O,
  db_login      => [ 'dbi:Pg:dbname=<database>', '<user>', '<password>' ],
  logfile       => $ROOT.'/err.log',
  xml_pretty    => 0,
  log_queries   => 0,
  debug         => 1,
  cookie_defaults => { path => '/' },
);

%S = (
  %S,
  url          => 'http://your.site.root/',
  url_static   => 'http://your.static.site.root/',
  global_salt  => '<some long unique string>',
  form_salt    => '<another unique string>',
  scrypt_salt  => '<yet another unique string>',
);


# Uncomment to disable certain features of Multi

#$M{modules}{API} = {};
#$M{modules}{APIDump} = {};

#$M{modules}{IRC} = {
#  nick    => 'MyVNDBBot',
#  server  => 'irc.synirc.net',
#  channels => [ '#vndb' ],
#  pass    => '<nickserv-password>',
#  masters => [ 'yorhel!~Ayo@your.hell' ],
#};
