#!/usr/bin/perl


# Usage:
#  ./multi.pl [-c] [-s] [-a] [cmd1] [cmd2] ..
#    -c  Do not daemonize, just execute the commands specified
#        on the command line and exit.
#    -s  Same as -c, but also execute commands in the shared
#        memory processing queue.
#    -a  Don't do anything, just add the commands specified on
#        the command line to the shared memory processing queue.

#
#  Multi  -  core namespace for initialisation and global variables
#

package Multi;

use strict;
use warnings;
use Tie::ShareLite ':lock';
use Time::HiRes;
use POE;
use DBI;

use lib '/www/vndb/lib';
use Multi::Core;
use Multi::RG;
use Multi::Image;
use Multi::Sitemap;
use Multi::Anime;
use Multi::Maintenance;
use Multi::IRC;

BEGIN { require 'global.pl' }


our $LOGDIR = '/www/vndb/data/log';
our $LOGLVL = 3; # 3:DEBUG, 2:ACTIONS, 1:WARN
our $STOP = 0;
our $DAEMONIZE = (grep /^-c$/, @ARGV) ? 1 : (grep /^-s$/, @ARGV) ? 2 : 0;


if(grep /^-a$/, @ARGV) {
  my $s = tie my %s, 'Tie::ShareLite', @VNDB::SHMOPTS;
  $s->lock(LOCK_EX);
  my @q = ( ($s{queue} ? @{$s{queue}} : ()), (grep !/^-/, @ARGV) );
  $s{queue} = \@q;
  $s->unlock();
  exit;
}


# one shared pgsql connection for all sessions
our $SQL = DBI->connect(@VNDB::DBLOGIN,
  { PrintError => 1, RaiseError => 0, AutoCommit => 1, pg_enable_utf8 => 1 });


Multi::Core->spawn();
Multi::RG->spawn();
Multi::Image->spawn();
Multi::Sitemap->spawn();
Multi::Anime->spawn() if !$VNDB::DEBUG; # no need to update anime from the beta
Multi::Maintenance->spawn();
Multi::IRC->spawn() if !$VNDB::DEBUG;


$SIG{__WARN__} = sub {(local$_=shift)=~s/\r?\n//;$poe_kernel->call(core=>log=>1,'__WARN__: '.$_)};

$poe_kernel->run();
exec $0, grep /^-/, @ARGV if $STOP == 2;



