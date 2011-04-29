
#
#  Multi::Core  -  handles spawning and logging
#

package Multi::Core;

use strict;
use warnings;
use POE;
use POE::Component::Pg;
use DBI;
use POSIX 'setsid', 'pause', 'SIGUSR1';


sub run {
  my $p = shift;

  die "PID file already exists\n" if -e "$VNDB::ROOT/data/multi.pid";

  # fork
  my $pid = fork();
  die "fork(): $!" if !defined $pid or $pid < 0;

  # parent process, log PID and wait for child to initialize
  if($pid > 0) {
    $SIG{CHLD} = sub { die "Initialization failed.\n"; };
    $SIG{ALRM} = sub { kill $pid, 9; die "Initialization timeout.\n"; };
    $SIG{USR1} = sub {
      open my $P, '>', "$VNDB::ROOT/data/multi.pid" or kill($pid, 9) && die $!;
      print $P $pid;
      close $P;
      exit;
    };
    alarm(10);
    pause();
    exit 1;
  }
  $poe_kernel->has_forked();

  # spawn our SQL handling session
  my @db = @{$VNDB::O{db_login}};
  my(@dsn) = DBI->parse_dsn($db[0]);
  $dsn[2] = ($dsn[2]?$dsn[2].',':'').'pg_enable_utf8=>1';
  $db[0] = "$dsn[0]:$dsn[1]($dsn[2]):$dsn[4]";
  POE::Component::Pg->spawn(alias => 'pg', dsn => $db[0], user => $db[1], password => $db[2]);

  # spawn the core session (which handles logging & external signals)
  POE::Session->create(
    package_states => [
      $p => [qw| _start log pg_error sig_shutdown shutdown |],
    ],
  );

  $poe_kernel->run();
}


sub _start {
  $_[KERNEL]->alias_set('core');
  $_[KERNEL]->call(core => log => 'Starting Multi '.$VNDB::S{version});
  $_[KERNEL]->post(pg => register => error => 'pg_error');
  $_[KERNEL]->post(pg => 'connect');
  $_[KERNEL]->sig(INT => 'sig_shutdown');
  $_[KERNEL]->sig(TERM => 'sig_shutdown');
  $_[KERNEL]->sig('shutdown', 'shutdown');

  # dynamically load and spawn modules
  for (keys %{$VNDB::M{modules}}) {
    my($mod, $args) = ($_, $VNDB::M{modules}{$_});
    next if !$args || ref($args) ne 'HASH';
    require "Multi/$mod.pm";
    # I'm surprised the strict pagma isn't complaining about this
    "Multi::$mod"->spawn(%$args);
  }

  # finish daemonizing
  kill SIGUSR1, getppid();
  setsid();
  chdir '/';
  umask 0022;
  open STDIN, '/dev/null';
  tie *STDOUT, 'Multi::Core::STDIO', 'STDOUT';
  tie *STDERR, 'Multi::Core::STDIO', 'STDERR';
}


# subroutine, not supposed to be called as a POE event
sub log_msg { # msg
  (my $msg = shift) =~ s/\n+$//;
  open(my $F, '>>', $VNDB::M{log_dir}.'/multi.log');
  printf $F "[%s] %s\n", scalar localtime, $msg;
  close $F;
}


# the POE event
sub log { # level, msg
  (my $p = eval { $_[SENDER][2]{$_[CALLER_STATE]}[0] } || '') =~ s/^Multi:://;
  log_msg sprintf '%s::%s: %s', $p, $_[CALLER_STATE],
    $#_>ARG0 ? sprintf($_[ARG0], @_[ARG1..$#_]) : $_[ARG0];
}


sub pg_error { # ARG: command, errmsg, [ query, params, orig_session, event-args ]
  my $s = $_[ARG2] ? sprintf ' (Session: %s, Query: "%s", Params: %s, Args: %s)',
    join(', ', $_[KERNEL]->alias_list($_[ARG4])), $_[ARG2],
    join(', ', $_[ARG3] ? map qq|"$_"|, @{$_[ARG3]} : '[none]'), $_[ARG5]||'' : '';
  die sprintf 'SQL Error for command %s: %s%s', $_[ARG0], $_[ARG1], $s;
}


sub sig_shutdown {
  # Multi modules should listen to the shutdown signal (but should never call sig_handled() on it!)
  $_[KERNEL]->signal($_[SESSION], 'shutdown', 'SIG'.$_[ARG0]);
  # consider this event as handled, so our process won't be killed directly
  $_[KERNEL]->sig_handled();
}


sub shutdown {
  $_[KERNEL]->call(core => log => 'Shutting down (%s)', $_[ARG1]);
  $_[KERNEL]->post(pg => 'shutdown');
  $_[KERNEL]->alias_remove('core');
  unlink "$VNDB::ROOT/data/multi.pid";
}


# Tiny class for forwarding output for STDERR/STDOUT to the log file using tie().
package Multi::Core::STDIO;

use base 'Tie::Handle';
sub TIEHANDLE { return bless \"$_[1]", $_[0] }
sub WRITE     {
  my($s, $msg) = @_;
  # Surpress warning about STDIO being tied in POE::Wheel::Run::new().
  # the untie() is being performed in the child process, which doesn't effect
  # the parent process, so the tie() will still be in place where we want it.
  return if $msg =~ /^Cannot redirect into tied STD(?:ERR|OUT)\.  Untying it/;
  Multi::Core::log_msg($$s.': '.$msg);
}


1;

