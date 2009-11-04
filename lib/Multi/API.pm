
#
#  Multi::API  -  The public VNDB API
#

package Multi::API;

use strict;
use warnings;
use Socket 'inet_ntoa', 'SO_KEEPALIVE', 'SOL_SOCKET', 'IPPROTO_TCP';
use Errno 'ECONNABORTED', 'ECONNRESET';
use POE 'Wheel::SocketFactory', 'Wheel::ReadWrite';
use POE::Filter::VNDBAPI 'encode_filters';
use Digest::SHA 'sha256_hex';
use Encode 'encode_utf8';


# not exported by Socket, taken from netinet/tcp.h (specific to Linux, AFAIK)
sub TCP_KEEPIDLE  { 4 }
sub TCP_KEEPINTVL { 5 }
sub TCP_KEEPCNT   { 6 }


sub spawn {
  my $p = shift;
  POE::Session->create(
    package_states => [
      $p => [qw|
        _start shutdown log server_error client_connect client_error client_input
        login login_res
        get_vn get_vn_res
      |],
    ],
    heap => {
      port => 19534,
      logfile => "$VNDB::M{log_dir}/api.log",
      conn_per_ip => 5,
      sess_per_user => 3,
      tcp_keepalive => [ 120, 60, 3 ], # time, intvl, probes
      @_,
      c => {},
    },
  );
}


## Non-POE helper functions

sub cerr {
  my($c, $id, $msg, %o) = @_;
  $c->{wheel}->put([ error => { id => $id, msg => $msg, %o }]);
  # using $poe_kernel here isn't really a clean solution...
  $poe_kernel->yield(log => $c, 'error: %s, %s', $id, $msg);
  return undef;
}


sub formatdate {
  return undef if $_[0] == 0;
  (local $_ = sprintf '%08d', $_[0]) =~
    s/^(\d{4})(\d{2})(\d{2})$/$1 == 9999 ? 'tba' : $2 == 99 ? $1 : $3 == 99 ? "$1-$2" : "$1-$2-$3"/e;
  return $_;
}


sub filtertosql {
  my($c, $p, $t, $field, $op, $value) = ($_[1], $_[2], $_[3], @{$_[0]});
  my %e = ( field => $field, op => $op, value => $value );

  $t = (grep $_->[0] eq $field, @$t)[0];
  return cerr $c, filterfield => "Unknown field '$field'", %e if !$t;
  shift @$t; # field name
  my $type = shift @$t;
  my %o = @$t;

  # integer, options: dbfield
  if($type eq 'int') {
    if($value && ref $value eq 'ARRAY') {
      return cerr $c, filterop => "Operator for '$field' must be either = or != for array values", %e if $op ne '=' && $op ne '!=';
      return cerr $c, filterval => "Array elements for '$field' must be integers", %e if grep !defined($_) || !/^\d+$/, @$value;
      push @$p, @$value;
      return sprintf '%s %s(%s)', $o{dbfield}, $op eq '=' ? 'IN' : 'NOT IN', join ',', map '?', @$value;
    } elsif(defined $value && !ref $value && $value =~ /^\d+$/) {
      my @ops = qw(= != > >= < <=);
      return cerr $c, filterop => "Operator for '$field' must be one of ".join(', ', @ops), %e if !grep $op eq $_, @ops;
      push @$p, $value;
      return sprintf '%s %s ?', $o{dbfield}, $op eq '!=' ? '<>' : $op;
    }
    return cerr $c, filterval => "Value for '$field' must be either an integer or an array of integers", %e;
  }

  # string, options: dbfield, null
  if($type eq 'str') {
    if(!defined $value) {
      return cerr $c, filterval => "null not allowed for '$field'", %e if !exists $o{null};
      return cerr $c, filterop => "Operator for '$field' must be either = or != for null", %e if $op ne '=' && $op ne '!=';
      return sprintf '%s %s', $o{dbfield}, $op eq '=' ? 'IS NULL' : 'IS NOT NULL' if !defined $o{null};
      push @$p, $o{null};
      return sprintf '%s %s ?', $o{dbfield}, $op eq '=' ? '=' : '<>';
    } elsif(ref($value) eq 'ARRAY') {
      return cerr $c, filterop => "Operator for '$field' must be either = or != for array values", %e if $op ne '=' && $op ne '!=';
      return cerr $c, filterval => "Array elements for '$field' must be scalars", %e if grep !defined($_) || ref($_), @$value;
      push @$p, @$value;
      return sprintf '%s %s(%s)', $o{dbfield}, $op eq '=' ? 'IN' : 'NOT IN', join ',', map '?', @$value;
    } elsif(!ref $value) {
      my @ops = qw(= != ~);
      if($op eq '=' || $op eq '!=') {
        push @$p, $value;
        return sprintf '%s %s ?', $o{dbfield}, $op eq '!=' ? '<>' : $op;
      } elsif($op eq '~') {
        $value =~ s/%//;
        push @$p, "%$value%";
        return sprintf '%s ILIKE ?', $o{dbfield};
      } else {
        return cerr $c, filterop => "Operator for '$field' must be =, != or ~", %e;
      }
    } else {
      return cerr $c, filterval => "Value for '$field' must be a string or an array of strings.", %e;
    }
  }

  die "This shouldn't happen!";
}


## POE handlers

sub _start {
  $_[KERNEL]->alias_set('api');
  $_[KERNEL]->sig(shutdown => 'shutdown');
  
  # create listen socket
  $_[HEAP]{listen} = POE::Wheel::SocketFactory->new(
    BindPort     => $_[HEAP]{port},
    Reuse        => 1,
    FailureEvent => 'server_error',
    SuccessEvent => 'client_connect',
  );
  $_[KERNEL]->yield(log => 0, 'API starting up on port %d', $_[HEAP]{port});
}


sub shutdown {
  $_[KERNEL]->alias_remove('api');
  $_[KERNEL]->yield(log => 0, 'API shutting down');
  delete $_[HEAP]{listen};
  delete $_[HEAP]{c}{$_}{wheel} for (keys %{$_[HEAP]{c}});
}


sub log {
  my($c, $msg, @args) = @_[ARG0..$#_];
  if(open(my $F, '>>', $_[HEAP]{logfile})) {
    printf $F "[%s] %s: %s\n", scalar localtime,
      $c ? sprintf '%d %s', $c->{wheel}->ID(), $c->{ip} : 'global',
      @args ? sprintf $msg, @args : $msg;
    close $F;
  }
}


sub server_error {
  return if $_[ARG0] eq 'accept' && $_[ARG1] == ECONNABORTED;
  $_[KERNEL]->yield(log => 0, 'Server socket failed on %s: (%s) %s', @_[ ARG0..ARG2 ]);
  $_[KERNEL]->call(core => log => 'API shutting down due to error.');
  $_[KERNEL]->yield('shutdown');
}


sub client_connect {
  my $ip = inet_ntoa($_[ARG1]);
  my $sock = $_[ARG0];

  if($_[HEAP]{conn_per_ip} <= grep $ip eq $_[HEAP]{c}{$_}{ip}, keys %{$_[HEAP]{c}}) {
    $_[KERNEL]->yield(log => 0,
      'Connect from %s denied, limit of %d connections per IP reached', $ip, $_[HEAP]{conn_per_ip});
    close $sock;
    return;
  }

  # set TCP keepalive (silently ignoring errors, it's not really important)
  my $keep = $_[HEAP]{tcp_keepalive};
  $keep && eval {
    setsockopt($sock, SOL_SOCKET,  SO_KEEPALIVE,  1);
    setsockopt($sock, IPPROTO_TCP, TCP_KEEPIDLE,  $keep->[0]);
    setsockopt($sock, IPPROTO_TCP, TCP_KEEPINTVL, $keep->[1]);
    setsockopt($sock, IPPROTO_TCP, TCP_KEEPCNT,   $keep->[2]);
  };

  # the wheel
  my $w = POE::Wheel::ReadWrite->new(
    Handle     => $sock,
    Filter     => POE::Filter::VNDBAPI->new(type => 'server'),
    ErrorEvent => 'client_error',
    InputEvent => 'client_input',
  );
  $_[HEAP]{c}{ $w->ID() } = {
    wheel => $w,
    ip => $ip,
  };
  $_[KERNEL]->yield(log => $_[HEAP]{c}{ $w->ID() }, 'Connected');
}


sub client_error { # func, errno, errmsg, wheelid
  my $c = $_[HEAP]{c}{$_[ARG3]};
  if($_[ARG0] eq 'read' && ($_[ARG1] == 0 || $_[ARG1] == ECONNRESET)) {
    $_[KERNEL]->yield(log => $c, 'Disconnected');
  } else {
    $_[KERNEL]->yield(log => $c, 'SOCKET ERROR on operation %s: (%s) %s', @_[ARG0..ARG2]);
  }
  delete $_[HEAP]{c}{$_[ARG3]};
}


sub client_input {
  my($arg, $id) = @_[ARG0,ARG1];
  my $cmd = shift @$arg;
  my $c = $_[HEAP]{c}{$id};

  return cerr $c, $arg->[0]{id}, $arg->[0]{msg} if !defined $cmd;

  # when we're here, we can assume that $cmd contains a valid command
  # and the arguments are syntactically valid

  # login
  return $_[KERNEL]->yield(login => $c, @$arg) if $cmd eq 'login';

  return cerr $c, needlogin => 'Not logged in.' if !$c->{username};
  # TODO: throttling

  # get
  return cerr $c, 'parse', "Unkown command '$cmd'" if $cmd ne 'get';
  my $type = shift @$arg;
  return cerr $c, 'gettype', "Unknown get type: '$type'" if $type ne 'vn';
  $_[KERNEL]->yield("get_$type", $c, @$arg);
}


sub login {
  my($c, $arg) = @_[ARG0,ARG1];

  # validation (bah)
  return cerr $c, loggedin => 'Already logged in, please reconnect to start a new session' if $c->{username};
  for (qw|protocol client clientver username password|) {
    !exists $arg->{$_}  && return cerr $c, missing => "Required field '$_' is missing", field => $_;
    !defined $arg->{$_} && return cerr $c, badarg  => "Field '$_' cannot be null", field => $_;
    # note that 'true' and 'false' are also refs
    ref $arg->{$_}      && return cerr $c, badarg  => "Field '$_' must be a scalar", field => $_;
  }
  return cerr $c, badarg => 'Unkonwn protocol version', field => 'protocol' if $arg->{protocol}  ne '1';
  return cerr $c, badarg => 'Invalid client name', field => 'client'        if $arg->{client}    !~ /^[a-zA-Z0-9 _-]{3,50}$/;
  return cerr $c, badarg => 'Invalid client version', field => 'clientver'  if $arg->{clientver} !~ /^\d+(\.\d+)?$/;
  return cerr $c, sesslimit => "Too many open sessions for user '$arg->{username}'", max_allowed => $_[HEAP]{sess_per_user}
    if $_[HEAP]{sess_per_user} <= grep $_[HEAP]{c}{$_}{username} && $arg->{username} eq $_[HEAP]{c}{$_}{username}, keys %{$_[HEAP]{c}};

  # fetch user info
  $_[KERNEL]->post(pg => query => "SELECT rank, salt, encode(passwd, 'hex') as passwd FROM users WHERE username = ?",
    [ $arg->{username} ], 'login_res', [ $c, $arg ]);
}


sub login_res { # num, res, [ c, arg ]
  my($num, $res, $c, $arg) = (@_[ARG0, ARG1], $_[ARG2][0], $_[ARG2][1]);

  return cerr $c, auth => "No user with the name '$arg->{username}'" if $num == 0;
  return cerr $c, auth => "Outdated password format, please relogin on $VNDB::S{url}/ and try again" if $res->[0]{salt} =~ /^ +$/;

  my $encrypted = sha256_hex($VNDB::S{global_salt}.encode_utf8($arg->{password}).encode_utf8($res->[0]{salt}));
  return cerr $c, auth => "Wrong password for user '$arg->{username}'" if lc($encrypted) ne lc($res->[0]{passwd});

  $c->{wheel}->put(['ok']);
  $c->{username} = $arg->{username};
  $_[KERNEL]->yield(log => $c,
    'Successful login by %s using client "%s" ver. %s', $arg->{username}, $arg->{client}, $arg->{clientver});
}


sub get_vn {
  my($c, $info, $filters) = @_[ARG0..$#_];
  
  return cerr $c, getinfo => "Unkown info flag '$_'", flag => $_ for (grep $_ ne 'basic', @$info);

  my $select = 'v.id, vr.title, vr.original, v.c_released, v.c_languages, v.c_platforms';

  my @placeholders;
  my $where = encode_filters $filters, \&filtertosql, $c, \@placeholders, [
    [ id => 'int',       dbfield => 'v.id' ],
    [ title => 'str',    dbfield => 'vr.title' ],
    [ original => 'str', dbfield => 'vr.original', null => '' ],
  ];
  return if !$where;

  $_[KERNEL]->post(pg => query =>
    qq|SELECT $select FROM vn v JOIN vn_rev vr ON v.latest = vr.id WHERE NOT v.hidden AND $where LIMIT 10|,
    \@placeholders, 'get_vn_res', [ $c, $info, $filters ]);
}


sub get_vn_res {
  my($num, $res, $c, $info, $filters, $time) = (@_[ARG0, ARG1], @{$_[ARG2]}, $_[ARG3]);

  for (@$res) {
    $_->{id}*=1;
    $_->{original} ||= undef;
    $_->{platforms} = [ split /\//, delete $_->{c_platforms} ];
    $_->{languages} = [ split /\//, delete $_->{c_languages} ];
    $_->{released} = formatdate delete $_->{c_released};
  }

  $c->{wheel}->put([ results => { num => $#$res+1, items => $res }]);
  $_[KERNEL]->yield(log => $c, "%4.0fms %2d get vn %s %s", $time*1000, $#$res+1, join (',', @$info), encode_filters $filters);
}


1;

