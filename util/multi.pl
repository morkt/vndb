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

# NOTE: in case of errors, clearing the shared memory might work:
#  $ ipcrm -S 0x42444e56 -M 0x42444e56

package Multi;

use strict;
use warnings;
no warnings 'once';
use Tie::ShareLite ':lock';
use Time::HiRes;
use POE;
use DBI;
use Cwd 'abs_path';


# loading & initialization

our $ROOT;
BEGIN { ($ROOT = abs_path $0) =~ s{/util/multi\.pl$}{}; *VNDB::ROOT = \$ROOT }
use lib $VNDB::ROOT.'/lib';

use Multi::Core;
require $VNDB::ROOT.'/data/global.pl';

our $STOP = 0;
our $DAEMONIZE = (grep /^-c$/, @ARGV) ? 1 : (grep /^-s$/, @ARGV) ? 2 : 0;



# only add commands with the -a argument

if(grep /^-a$/, @ARGV) {
  my $s = tie my %s, 'Tie::ShareLite', -key => $VNDB::S{sharedmem_key}, -create => 'yes', -destroy => 'no', -mode => 0666;
  $s->lock(LOCK_EX);
  my @q = ( ($s{queue} ? @{$s{queue}} : ()), (grep !/^-/, @ARGV) );
  $s{queue} = \@q;
  $s->unlock();
  exit;
}

# one shared pgsql connection for all sessions
our $SQL = DBI->connect(@{$VNDB::O{db_login}},
  { PrintError => 1, RaiseError => 0, AutoCommit => 1, pg_enable_utf8 => 1 });


Multi::Core->spawn();

# dynamically load and spawn modules
for (keys %{$VNDB::M{modules}}) {
  my($mod, $args) = ($_, $VNDB::M{modules}{$_});
  next if !$args || ref($args) ne 'HASH';
  require "Multi/$mod.pm";
  # I'm surprised the strict pagma isn't complaining about this
  "Multi::$mod"->spawn(%$args);
}

$SIG{__WARN__} = sub {(local$_=shift)=~s/\r?\n//;$poe_kernel->call(core=>log=>1,'__WARN__: '.$_)};

$poe_kernel->run();
exec $0, grep /^-/, @ARGV if $STOP == 2;



