
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
  version         => 'beta',
  url             => 'http://vndb.org',
  url_static      => 'http://s.vndb.org',
  cookie_domain   => '.vndb.org',
  cookie_key      => 'any-private-string-here',
  user_ranks      => [
       # rankname   allowed actions                                   # DB number
    [qw| visitor    hist                                          |], # 0
    [qw| loser      hist                                          |], # 1
    [qw| user       hist board edit                               |], # 2
    [qw| mod        hist board boardmod edit mod lock del         |], # 3
    [qw| admin      hist board boardmod edit mod lock del usermod |], # 4
  ],
);


# allow the settings to be overwritten in config.pl
require $ROOT.'/data/config.pl' if -f $ROOT.'/data/config.pl';

1;
