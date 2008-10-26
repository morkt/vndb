
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
);


# allow the settings to be overwritten in config.pl
require $ROOT.'/data/config.pl' if -f $ROOT.'/data/config.pl';

1;
