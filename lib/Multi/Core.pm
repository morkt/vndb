
#
#  Multi::Core  -  handles logging and the main command queue
#

package Multi::Core;

use strict;
use warnings;
use POE 'Component::Cron';
use Tie::ShareLite ':lock';
use Time::HiRes 'time', 'gettimeofday', 'tv_interval'; # overload time()
use DateTime::Event::Cron; # bug in PoCo::Cron (rt #35422, fixed in 0.019)


sub spawn {
  my $p = shift;
  POE::Session->create(
    package_states => [
      $p => [qw| _start register addcron heartbeat queue prepare execute finish log cmd_exit |],
    ],
    heap => { cron => [], cmds => [], running => 0, starttime => 0 },
  );
}


sub _start {
  $_[KERNEL]->alias_set('core');
  $_[KERNEL]->call(core => register => qr/^(exit|reload)$/, 'cmd_exit');
  $_[KERNEL]->yield(queue => $_) for (grep !/^-/, @ARGV);
  $_[KERNEL]->yield(heartbeat => time) if $Multi::DAEMONIZE != 1;
  $_[KERNEL]->yield('prepare');
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


sub heartbeat { # last beat
  $_[KERNEL]->yield('prepare');
  $_[KERNEL]->call(core => log => 1, 'Heartbeat took %.2fs, possible block', time-$_[ARG0])
    if time > $_[ARG0]+3;
  $_[KERNEL]->delay(heartbeat => 1, time) if $Multi::DAEMONIZE == 0;
}


sub queue { # cmd
  my $s = tie my %s, 'Tie::ShareLite', @VNDB::SHMOPTS;
  $s->lock(LOCK_EX);
  my @q = ( ($s{queue} ? @{$s{queue}} : ()), $_[ARG0] );
  $s{queue} = \@q;
  $s->unlock();

  $_[KERNEL]->call(core => log => 3, "Queuing '%s'.", $_[ARG0]);
  $_[KERNEL]->yield('prepare');
}


sub prepare { # determines whether to execute a new cmd
  return if $Multi::STOP || $_[HEAP]{running};

  my $s = tie my %s, 'Tie::ShareLite', @VNDB::SHMOPTS;
  $s->lock(LOCK_SH);
  if($s{queue} && @{$s{queue}}) {
    $_[KERNEL]->yield(execute => $s{queue}[0]);
    $_[HEAP]{running} = 1;
  }
  $s->unlock();
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


sub finish { # cmd
  $_[HEAP]{running} = 0;
  $_[KERNEL]->call(core => log => 2, "Unqueuing '%s' after %.2fs.",
    $_[ARG0], tv_interval($_[HEAP]{starttime}));

  my $s = tie my %s, 'Tie::ShareLite', @VNDB::SHMOPTS;
  $s->lock(LOCK_EX);
  my @q = grep { $_ ne $_[ARG0] } $s{queue} ? @{$s{queue}} : ();
  $s{queue} = \@q;
  $s->unlock();

  $_[KERNEL]->yield('prepare');
}


sub log { # level, msg
  return if $_[ARG0] > $Multi::LOGLVL; 

  (my $p = eval { $_[SENDER][2]{$_[CALLER_STATE]}[0] } || '') =~ s/^Multi:://;
  my $msg = sprintf '(%s) %s::%s: %s',
    (qw|WRN ACT DBG|)[$_[ARG0]-1], $p, $_[CALLER_STATE],
    $_[ARG2] ? sprintf($_[ARG1], @_[ARG2..$#_]) : $_[ARG1];
    
  open(my $F, '>>', $Multi::LOGDIR.'/multi.log');
  printf $F "[%s] %s\n", scalar localtime, $msg;
  close $F;

 # (debug) log to stdout as well...
  $VNDB::DEBUG && printf "[%s] %s\n", scalar localtime, $msg;
}


sub cmd_exit {
  $Multi::STOP = $_[ARG0] eq 'reload' ? 2 : 1;
  $_[KERNEL]->call(core => finish => $_[ARG0]);
  $_[KERNEL]->call(core => log => 2, 'Exiting...');

  $_[KERNEL]->delay('heartbeat'); # stop the heartbeats
  $_->delete() for (@{$_[HEAP]{cron}}); # stop scheduling cron jobs
  $_[KERNEL]->signal($_[KERNEL], 'shutdown'); # Broadcast to other sessions
}


1;


