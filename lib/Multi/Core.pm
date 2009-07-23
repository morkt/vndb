
#
#  Multi::Core  -  handles logging and the main command queue
#

package Multi::Core;

use strict;
use warnings;
use POE;
use POE::Component::Pg;
use DBI;


sub run {
  my $p = shift;

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

  # log warnings
  $SIG{__WARN__} = sub {(local$_=shift)=~s/\r?\n//;$poe_kernel->call(core=>log=>'__WARN__: '.$_)};

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
}


sub log { # level, msg
  (my $p = eval { $_[SENDER][2]{$_[CALLER_STATE]}[0] } || '') =~ s/^Multi:://;
  my $msg = sprintf '%s::%s: %s', $p, $_[CALLER_STATE],
    $_[ARG1] ? sprintf($_[ARG0], @_[ARG1..$#_]) : $_[ARG0];

  open(my $F, '>>', $VNDB::M{log_dir}.'/multi.log');
  printf "[%s] %s\n", scalar localtime, $msg;
  close $F;
}


sub pg_error { # ARG: command, errmsg, [ query, params, orig_session, event-args ]
  my $s = $_[ARG2] ? sprintf ' (Session: %s, Query: "%s", Params: %s, Args: %s)',
    join(', ', $_[KERNEL]->alias_list($_[ARG4])), $_[ARG2],
    join(', ', $_[ARG3] ? map qq|"$_"|, @{$_[ARG3]} : '[none]'), $_[ARG5] : '';
  $_[KERNEL]->call(core => log => 'SQL Error for command %s: %s %s', $_[ARG0], $_[ARG1], $s);
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
}


1;

