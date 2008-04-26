
#
#  Multi::Core  -  handles logging and the main command queue
#

package Multi::Core;

use strict;
use warnings;
use POE 'Component::Cron';
use Storable 'freeze', 'thaw';
use IPC::ShareLite ':lock';
use Time::HiRes 'time', 'gettimeofday', 'tv_interval'; # overload time()
use DateTime::Event::Cron; # bug in PoCo::Cron


sub spawn {
  my $p = shift;
  POE::Session->create(
    package_states => [
      $p => [qw| _start register addcron fetch queue execute finish log cmd_exit |],
    ],
    heap => { cron => [], queue => [], cmds => [], running => 0, starttime => 0 },
  );
}


sub _start {
  $_[KERNEL]->alias_set('core');
  $_[KERNEL]->call(core => register => qr/^(exit|reload)$/, 'cmd_exit');
  $_[KERNEL]->yield(queue => $_) for (grep !/^-/, @ARGV);
  $_[KERNEL]->yield(fetch => time) if $Multi::DAEMONIZE != 1;
}


sub register { # regex, state
  push @{$_[HEAP]{cmds}}, [ $_[ARG0], $_[SENDER], $_[ARG1] ];
  (my $p = $_[SENDER][2]{$_[CALLER_STATE]}[0]) =~ s/^Multi:://; # NOT PORTABLE
  $_[KERNEL]->call(core => log => 3, "Command '%s' handled by %s::%s", $_[ARG0], $p, $_[ARG1]);
}


sub addcron { # cronline, cmd
  return if $Multi::DAEMONIZE; # no cronjobs when we aren't a daemon!
  push @{$_[HEAP]{cron}}, POE::Component::Cron->from_cron($_[ARG0], $_[SESSION], queue => $_[ARG1]);
  $_[KERNEL]->call(core => log => 3, "Added cron: %s %s", $_[ARG0], $_[ARG1]);
}


sub fetch { # lastfetch
  my $s = IPC::ShareLite->new(-key => $VNDB::SHMKEY,-create => 1, -destroy => 0);
  $s->lock(LOCK_SH);
  my $l = $s->fetch();
  if($l) {
    my $cmds = thaw($l);
    $_[KERNEL]->yield(queue => $_) for(@$cmds);
    $s->lock(LOCK_EX);
    $s->store('');
  }
  $s->unlock;
  undef $s;

  $_[KERNEL]->call(core => log => 1, 'Heartbeat took %.2fs, possible block', time-$_[ARG0])
    if time > $_[ARG0]+3;
  $_[KERNEL]->delay(fetch => 1, time) if $Multi::DAEMONIZE == 0;
}


sub queue { # cmd
  push @{$_[HEAP]{queue}}, $_[ARG0];
  $_[KERNEL]->call(core => log => 3, "Queuing '%s'. Queue size: %d", $_[ARG0], scalar @{$_[HEAP]{queue}});
  if(!$_[HEAP]{running}) {
    $_[KERNEL]->yield(execute => $_[ARG0]);
    $_[HEAP]{running} = 1;
  }
}


sub execute { # cmd 
  $_[HEAP]{starttime} = [ gettimeofday ];
  my $cmd = (grep { $_[ARG0] =~ /$_->[0]/ } @{$_[HEAP]{cmds}})[0];
  if(!$cmd) {
    $_[KERNEL]->call(core => log => 1, 'Unknown cmd: %s', $_[ARG0]);
    $_[KERNEL]->yield(finish => $_[ARG0]);
    return;
  }
  $_[KERNEL]->call(core => log => 2, 'Executing cmd: %s', $_[ARG0]);
  $_[ARG0] =~ /$cmd->[0]/;  # determine arguments (see perlvar for the magic)
  my @arg = $#- ? map { substr $_[ARG0], $-[$_], $+[$_]-$-[$_] } 1..$#- : ();
  $_[KERNEL]->post($cmd->[1] => $cmd->[2], $_[ARG0], @arg);
}


sub finish { # cmd [, stop ]
  $_[HEAP]{running} = 0;
  $_[HEAP]{queue} = [ grep { $_ ne $_[ARG0] } @{$_[HEAP]{queue}} ];
  $_[KERNEL]->call(core => log => 2, "Unqueuing '%s' after %.2fs. Queue size: %d",
    $_[ARG0], tv_interval($_[HEAP]{starttime}), scalar @{$_[HEAP]{queue}});
  if(@{$_[HEAP]{queue}} && !$_[ARG1]) {
    $_[KERNEL]->yield(execute => $_[HEAP]{queue}[0]);
    $_[HEAP]{running} = 1;
  }
}


sub log { # level, msg
  return if $_[ARG0] > $Multi::LOGLVL; 

  (my $p = $_[SENDER][2]{$_[CALLER_STATE]}[0]) =~ s/^Multi:://; # NOT PORTABLE
  my $msg = sprintf '(%s) %s::%s: %s',
    (qw|WRN ACT DBG|)[$_[ARG0]-1], $p, $_[CALLER_STATE],
    $_[ARG2] ? sprintf($_[ARG1], @_[ARG2..$#_]) : $_[ARG1];
    
  open(my $F, '>>', $Multi::LOGDIR.'/multi.log');
  printf $F "[%s] %s\n", scalar localtime, $msg;
  close $F;

 # (debug) log to stdout as well...
 #printf "[%s] %s\n", scalar localtime, $msg;
}


sub cmd_exit {
  $Multi::RESTART = 1 if $_[ARG0] eq 'reload';
  $_[KERNEL]->call(core => finish => $_[ARG0], 1);
  $_[KERNEL]->call(core => log => 2, 'Exiting...');

  
  my $s = IPC::ShareLite->new(-key => 'VNDB',-create => 1, -destroy => 0);
  $s->lock(LOCK_EX);
  $s->store(freeze($_[HEAP]->{queue}));
  $s->unlock();
  undef $s;

  $_[KERNEL]->delay('fetch'); # stop fetching
  $_->delete() for (@{$_[HEAP]{cron}}); # stop scheduling cron jobs
  $_[KERNEL]->signal($_[KERNEL], 'shutdown'); # Broadcast to other sessions
}


1;


