
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


# see the notes after __END__ for an explanation of what this function does
sub filtertosql {
  my($c, $p, $t, $field, $op, $value) = ($_[1], $_[2], $_[3], @{$_[0]});
  my %e = ( field => $field, op => $op, value => $value );

  # get the field that matches
  $t = (grep $_->[0] eq $field, @$t)[0];
  return cerr $c, filter => "Unknown field '$field'", %e if !$t;
  shift @$t; # field name

  # get the type that matches
  $t = (grep +(
    # wrong operator? don't even look further!
    !$_->[2]{$op} ? 0
    # undef
    : !defined($_->[0]) ? !defined($value)
    # int
    : $_->[0] eq 'int'  ? (defined($value) && !ref($value) && $value =~ /^-?\d+$/)
    # str
    : $_->[0] eq 'str'  ? defined($value) && !ref($value)
    # inta
    : $_->[0] eq 'inta' ? ref($value) eq 'ARRAY' && !grep(!defined($_) || ref($_) || $_ !~ /^-?\d+$/, @$value)
    # stra
    : $_->[0] eq 'stra' ? ref($value) eq 'ARRAY' && !grep(!defined($_) || ref($_), @$value)
    # oops
    : die "Invalid filter type $_->[0]"
  ), @$t)[0];
  return cerr $c, filter => 'Wrong field/operator/expression type combination', %e if !$t;

  my($type, $sql, $ops, %o) = @$t;

  # substistute :op: in $sql, which is the same for all types
  $sql =~ s/:op:/$ops->{$op}/g;

  # no further processing required for type=undef
  return $sql if !defined $type;

  # pre-process the argument(s)
  for (!$o{process} ? () : ref($value) eq 'ARRAY' ? @$value : $value) {
    if(!ref $o{process}) {
      $_ = sprintf $o{process}, $_;
    } elsif(ref($o{process}) eq 'CODE') {
      $_ = $o{process}->($_);
    } elsif(${$o{process}} eq 'like') {
      y/%//;
      $_ = "%$_%";
    }
  }

  # type=str and type=int are now quite simple
  if(!ref $value) {
    $sql =~ s/:value:/push @$p, $value; '?'/eg;
    return $sql;
  }

  # and do some processing for type=stra and type=inta
  my @parameters;
  if($o{serialize}) {
    for (@$value) {
      my $v = $o{serialize};
      $v =~ s/:op:/$ops->{$op}/g;
      $v =~ s/:value:/push @parameters, $_; '?'/eg;
      $_ = $v;
    }
  } else {
    @parameters = @$value;
    $_ = '?' for @$value;
  }
  my $joined = join defined $o{join} ? $o{join} : '', @$value;
  $sql =~ s/:value:/push @$p, @parameters; $joined/eg;
  return $sql;
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
    [ 'id',
      [ 'int' => 'v.id :op: :value:', {qw|= =  != <>  > >  < <  <= <=  >= >=|} ],
      [ inta  => 'v.id :op:(:value:)', {'=' => 'IN', '!= ' => 'NOT IN'}, join => ',' ],
    ], [ 'title',
      [ str   => 'vr.title :op: :value:', {qw|= =  != <>|} ],
      [ str   => 'vr.title ILIKE :value:', {'~',1}, process => \'like' ],
    ], [ 'original',
      [ undef,   "vr.original :op: ''", {qw|= =  != <>|} ],
      [ str   => 'vr.original :op: :value:', {qw|= =  != <>|} ],
      [ str   => 'vr.original ILIKE :value:', {'~',1}, process => \'like' ]
    ], [ 'platforms',
      [ undef,   "v.c_platforms :op: ''", {qw|= =  != <>|} ],
      [ str   => 'v.c_platforms :op: :value:', {'=' => 'LIKE', '!=' => 'NOT LIKE'}, process => \'like' ],
      [ stra  => '(:value:)', {'=', 1}, join => ' OR ',  serialize => 'v.c_platforms LIKE :value:', \'like' ],
      [ stra  => '(:value:)', {'!=',1}, join => ' AND ', serialize => 'v.c_platforms NOT LIKE :value:', \'like' ],
    ], [ 'languages', # rather similar to platforms
      [ undef,   "v.c_languages :op: ''", {qw|= =  != <>|} ],
      [ str   => 'v.c_languages :op: :value:', {'=' => 'LIKE', '!=' => 'NOT LIKE'}, process => \'like' ],
      [ stra  => '(:value:)', {'=', 1}, join => ' OR ',  serialize => 'v.c_languages LIKE :value:', process => \'like' ],
      [ stra  => '(:value:)', {'!=',1}, join => ' AND ', serialize => 'v.c_languages NOT LIKE :value:', process => \'like' ],
    ], [ 'search',
      [ str   => '(vr.title ILIKE :value: OR vr.alias ILIKE :value: OR v.id IN(
           SELECT rv.vid FROM releases r JOIN releases_rev rr ON rr.id = r.latest JOIN releases_vn rv ON rv.rid = rr.id
           WHERE rr.title ILIKE :value: OR rr.original ILIKE :value:
         ))', {'~', 1}, process => \'like' ],
    ],
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


__END__

Filter definitions:

  [ 'field name', [ type, 'sql string', { filterop => sqlop, .. }, %options{process serialize join} ] ]
  type (does not have to be unique, to support multiple operators with different SQL but with the same type):
    undef (null)
    'str' (normal string)
    'int' (normal int)
    'stra' (array of strings)
    'inra' (array of ints)
  sql string:
    The relevant SQL string, with :op: and :value: subsistutions. :value: is not available for type=undef
  join: (only used when type is an array)
    scalar, join string used when joining multiple values.
  serialize: (serializes the values before join()'ing, only for arrays)
    scalar, :op: and :value: subsistution
  process: (process the value(s) that will be passed to Pg)
    scalar, %s subsitutes the value
    sub, argument = value, returns new value
    scalarref, template:
      \'like' => sub { (local$_=shift)=~y/%//; lc "%$_%" }

  example for v.id:
  [ 'id',
    [ int  => 'v.id :op: :value:', {qw|= =  != <>  > >  < <  <= <=  >= >=|} ],
    [ inta => 'v.id :op:(:value:)', {'=' => 'IN', '!= ' => 'NOT IN'}, join => ',' ]
  ]

  example for vr.original:
  [ 'original',
    [ undef,   "vr.original :op: ''", {qw|= =  != <>|} ],
    [ str   => 'vr.original :op: :value:', {qw|= =  != <>|} ],
    [ str   => 'vr.original :op: :value:', {qw|~ ILIKE|}, process => \'like' ],
  ]

  example for v.c_platforms:
  [ 'platforms',
    [ undef,   "v.c_platforms :op: ''", {qw|= =  != <>|} ],
    [ str   => 'v.c_platforms :op: :value:', {'=' => 'LIKE', '!=' => 'NOT LIKE'}, process => \'like' ],
    [ stra  => '(:value:)', {'=' => 'LIKE', '!=' => 'NOT LIKE'}, join => ' or ', serialize => 'v.c_platforms :op: :value:', process => \'like' ],
  ]

  example for the VN search:
  [ 'search', [ '(vr.title ILIKE :value:
       OR vr.alias ILIKE :value:
       OR v.id IN(
         SELECT rv.vid
         FROM releases r
         JOIN releases_rev rr ON rr.id = r.latest
         JOIN releases_vn rv ON rv.rid = rr.id
         WHERE rr.title ILIKE :value:
            OR rr.original ILIKE :value:
     ))', {'~', 1}, process => \'like'
  ]],

  example for vn_anime (for the sake of the example...)
  [ 'anime',
    [ undef,  ':op:(SELECT 1 FROM vn_anime va WHERE va.vid = v.id)', {'=' => 'EXISTS', '!=' => 'NOT EXISTS'} ],
    [ int  => 'v.id :op:(SELECT va.vid FROM vn_anime va WHERE va.aid = :value:)', {'=' => 'IN', '!=' => 'NOT IN'} ],
    [ inta => 'v.id :op:(SELECT va.vid FROM vn_anime va WHERE va.aid IN(:value:))', {'=' => 'IN', '!=' => 'NOT IN'}, join => ','],
  ]

