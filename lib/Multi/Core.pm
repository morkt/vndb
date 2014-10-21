
#
#  Multi::Core  -  handles spawning and logging
#

package Multi::Core;

use strict;
use warnings;
use AnyEvent;
use AnyEvent::Log;
use AnyEvent::Pg::Pool;
use DBI;
use POSIX 'setsid', 'pause', 'SIGUSR1';
use Exporter 'import';

our @EXPORT = qw|PG|;
our $PG;


my $logger;
my $pidfile;


sub daemon_init {
  my $pid = fork();
  die "fork(): $!" if !defined $pid or $pid < 0;

  # parent process, log PID and wait for child to initialize
  if($pid > 0) {
    $SIG{CHLD} = sub { die "Initialization failed.\n"; };
    $SIG{ALRM} = sub { kill $pid, 9; die "Initialization timeout.\n"; };
    $SIG{USR1} = sub {
      open my $P, '>', $pidfile or kill($pid, 9) && die $!;
      print $P $pid;
      close $P;
      exit;
    };
    alarm(10);
    pause();
    exit 1;
  }
}


sub daemon_done {
  kill SIGUSR1, getppid();
  setsid();
  chdir '/';
  umask 0022;
  open STDIN, '/dev/null';
  tie *STDOUT, 'Multi::Core::STDIO', 'STDOUT';
  tie *STDERR, 'Multi::Core::STDIO', 'STDERR';

  AE::signal TERM => sub { unlink $pidfile };
  AE::signal INT  => sub { unlink $pidfile };
}


sub load_pg {
  my @db = @{$VNDB::O{db_login}};
  my @dsn = DBI->parse_dsn($db[0]);
  my %vars = split /[,=]/, $dsn[4];
  $PG = AnyEvent::Pg::Pool->new(
    {%vars, user => $db[1], password => $db[2], host => 'localhost'},
    on_error => sub { die "Lost connection to PostgreSQL\n"; },
    on_connect_error => sub { die "Lost connection to PostgreSQL\n"; },
  );

  # Test that we're connected, so that a connection failure results in a failure to start Multi.
  my $cv = AE::cv;
  my $w = $PG->push_query(
    query => 'SELECT',
    on_result => sub { $cv->send; },
    on_error => sub { die "Connection to PostgreSQL has failed"; },
  );
  $cv->recv;
}


sub load_mods {
  for(keys %{$VNDB::M{modules}}) {
    my($mod, $args) = ($_, $VNDB::M{modules}{$_});
    next if !$args || ref($args) ne 'HASH';
    require "Multi/$mod.pm";
    # I'm surprised the strict pagma isn't complaining about this
    "Multi::$mod"->run(%$args);
  }
}


sub run {
  my $p = shift;
  $pidfile = "$VNDB::ROOT/data/multi.pid";
  die "PID file already exists\n" if -e $pidfile;

  AnyEvent::Log::ctx('Multi')->attach(
    AnyEvent::Log::Ctx->new(log_to_file => "$VNDB::M{log_dir}/multi.log", level => 'trace')
  );

  daemon_init;
  load_pg;
  load_mods;
  daemon_done;
  AE::log info => "Starting Multi $VNDB::S{version}";

  # Run forever
  AE::cv->recv;
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
  #return if $msg =~ /^Cannot redirect into tied STD(?:ERR|OUT)\.  Untying it/;
  AE::log warn => "$$s: $msg";
}


1;

