
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
use Time::HiRes 'time'; # important for throttling
use VNDBUtil 'normalize_query';
use JSON::XS;


# not exported by Socket, taken from netinet/tcp.h (specific to Linux, AFAIK)
sub TCP_KEEPIDLE  () { 4 }
sub TCP_KEEPINTVL () { 5 }
sub TCP_KEEPCNT   () { 6 }


# what our JSON encoder considers 'true' or 'false'
sub TRUE  () { JSON::XS::true }
sub FALSE () { JSON::XS::false }


# Global throttle hash, key = username, value = [ cmd_time, sql_time ]
# TODO: clean up items in this hash when username isn't connected anymore and throttle times < current time
my %throttle;


sub spawn {
  my $p = shift;
  POE::Session->create(
    package_states => [
      $p => [qw|
        _start shutdown log server_error client_connect client_error client_input
        login login_res get_results get_vn get_vn_res get_release get_release_res
        get_producer get_producer_res admin
      |],
    ],
    heap => {
      port => 19534,
      logfile => "$VNDB::M{log_dir}/api.log",
      conn_per_ip => 5,
      sess_per_user => 3,
      max_results => 25,
      default_results => 10,
      tcp_keepalive => [ 120, 60, 3 ], # time, intvl, probes
      throttle_cmd => [ 6, 100 ], # interval between each command, allowed burst
      throttle_sql => [ 60, 1 ], # sql time multiplier, allowed burst (in sql time)
      ipbans => [],
      @_,
      c => {}, # open connections
      s => {conn => 0, cmds => 0, cmd_err => 0}, # stats
    },
  );
}


## Non-POE helper functions

sub cerr {
  my($c, $id, $msg, %o) = @_;

  # update stat counters
  $c->{cmd_err}++;
  $poe_kernel->get_active_session()->get_heap()->{s}{cmd_err}++;

  # send error
  $c->{wheel}->put([ error => { id => $id, msg => $msg, %o }]);

  # log
  $poe_kernel->yield(log => $c, 'error: %s, %s', $id, $msg);
  return undef;
}


sub formatdate {
  return undef if $_[0] == 0;
  (local $_ = sprintf '%08d', $_[0]) =~
    s/^(\d{4})(\d{2})(\d{2})$/$1 == 9999 ? 'tba' : $2 == 99 ? $1 : $3 == 99 ? "$1-$2" : "$1-$2-$3"/e;
  return $_;
}


sub parsedate {
  return 0 if !defined $_[0];
  return \'Invalid date value' if $_[0] !~ /^(?:tba|\d{4}(?:-\d{2}(?:-\d{2})?)?)$/;
  my @v = split /-/, $_[0];
  return $v[0] eq 'tba' ? 99999999 : @v==1 ? "$v[0]9999" : @v==2 ? "$v[0]$v[1]99" : $v[0].$v[1].$v[2];
}


# see the notes after __END__ for an explanation of what this function does
sub filtertosql {
  my($c, $p, $t, $field, $op, $value) = ($_[1], $_[2], $_[3], @{$_[0]});
  my %e = ( field => $field, op => $op, value => $value );

  # get the field that matches
  $t = (grep $_->[0] eq $field, @$t)[0];
  return cerr $c, filter => "Unknown field '$field'", %e if !$t;
  $t = [ @$t[1..$#$t] ];

  # get the type that matches
  $t = (grep +(
    # wrong operator? don't even look further!
    !defined($_->[2]{$op}) ? 0
    # undef
    : !defined($_->[0]) ? !defined($value)
    # int
    : $_->[0] eq 'int'  ? (defined($value) && !ref($value) && $value =~ /^-?\d+$/)
    # str
    : $_->[0] eq 'str'  ? defined($value) && !ref($value)
    # inta
    : $_->[0] eq 'inta' ? ref($value) eq 'ARRAY' && @$value && !grep(!defined($_) || ref($_) || $_ !~ /^-?\d+$/, @$value)
    # stra
    : $_->[0] eq 'stra' ? ref($value) eq 'ARRAY' && @$value && !grep(!defined($_) || ref($_), @$value)
    # bool
    : $_->[0] eq 'bool' ? defined($value) && JSON::XS::is_bool($value)
    # oops
    : die "Invalid filter type $_->[0]"
  ), @$t)[0];
  return cerr $c, filter => 'Wrong field/operator/expression type combination', %e if !$t;

  my($type, $sql, $ops, %o) = @$t;

  # substistute :op: in $sql, which is the same for all types
  $sql =~ s/:op:/$ops->{$op}/g;

  # no further processing required for type=undef
  return $sql if !defined $type;

  # split a string into an array of strings
  if($type eq 'str' && $o{split}) {
    $value = [ $o{split}->($value) ];
    # assume that this match failed if the function doesn't return anything useful
    return 'false' if !@$value || grep(!defined($_) || ref($_), @$value);
    $type = 'stra';
  }

  # pre-process the argument(s)
  my @values = ref($value) eq 'ARRAY' ? @$value : $value;
  for my $v (!$o{process} ? () : @values) {
    if(!ref $o{process}) {
      $v = sprintf $o{process}, $v;
    } elsif(ref($o{process}) eq 'CODE') {
      $v = $o{process}->($v);
      return cerr $c, filter => $$v, %e if ref($v) eq 'SCALAR';
    } elsif(${$o{process}} eq 'like') {
      y/%//;
      $v = "%$v%";
    } elsif(${$o{process}} eq 'lang') {
      return cerr $c, filter => 'Invalid language code', %e if !grep $v eq $_, @{$VNDB::S{languages}};
    }
  }

  # type=bool and no processing done? convert bool to what DBD::Pg wants
  $values[0] = $values[0] ? 1 : 0 if $type eq 'bool' && !$o{process};

  # type=str, int and bool are now quite simple
  if(!ref $value) {
    $sql =~ s/:value:/push @$p, $values[0]; '?'/eg;
    return $sql;
  }

  # and do some processing for type=stra and type=inta
  my @parameters;
  if($o{serialize}) {
    for (@values) {
      my $v = $o{serialize};
      $v =~ s/:op:/$ops->{$op}/g;
      $v =~ s/:value:/push @parameters, $_; '?'/eg;
      $_ = $v;
    }
  } else {
    @parameters = @values;
    $_ = '?' for @values;
  }
  my $joined = join defined $o{join} ? $o{join} : '', @values;
  $sql =~ s/:value:/push @$p, @parameters; $joined/eg;
  return $sql;
}


# generates the LIMIT/OFFSET/ORDER BY part of the queries
sub sqllast { # $get, default sort field, hashref with sort fields and SQL variant
  my($get, $def, $sort) = @_;

  my $o = $get->{opt}{reverse} ? 'DESC' : 'ASC';
  $get->{opt}{sort} = $def if !defined $get->{opt}{sort};
  my $s = $sort->{$get->{opt}{sort}};
  return cerr $get->{c}, badarg => 'Invalid sort field', field => 'sort' if !$s;
  my $q = 'ORDER BY '.sprintf($s, $o);

  $q .= sprintf ' LIMIT %d OFFSET %d', $get->{opt}{results}+1, $get->{opt}{results}*($get->{opt}{page}-1);
  return $q;
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

  $_[HEAP]{s}{conn}++;

  return close $sock if grep $ip eq $_, @{$_[HEAP]{ipbans}};
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
    Filter     => POE::Filter::VNDBAPI->new(),
    ErrorEvent => 'client_error',
    InputEvent => 'client_input',
  );
  $_[HEAP]{c}{ $w->ID() } = {
    wheel     => $w,
    ip        => $ip,
    connected => time,
    cmds      => 0,
    cmd_err   => 0,
    # username, client, clientver are added after logging in
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

  # stats
  $_[HEAP]{s}{cmds}++;
  $c->{cmds}++;

  # parse error?
  return cerr $c, $arg->[0]{id}, $arg->[0]{msg} if !defined $cmd;

  # handle login command
  return $_[KERNEL]->yield(login => $c, $arg) if $cmd eq 'login';
  return cerr $c, needlogin => 'Not logged in.' if !$c->{username};

  # update throttle array of the current user
  my $time = time;
  $_ < $time && ($_ = $time) for @{$c->{throttle}};

  # check for thottle rule violation
  my @limits = ('cmd', 'sql');
  for (0..$#limits) {
    my $threshold = $_[HEAP]{"throttle_$limits[$_]"}[0]*$_[HEAP]{"throttle_$limits[$_]"}[1];
    return cerr $c, throttled => 'Throttle limit reached.', type => $limits[$_],
        minwait  => int(10*($c->{throttle}[$_]-$time-$threshold))/10+1,
        fullwait => int(10*($c->{throttle}[$_]-$time))/10+1
      if $c->{throttle}[$_]-$time > $threshold;
  }

  # update commands/second throttle
  $c->{throttle}[0] += $_[HEAP]{throttle_cmd}[0];

  # handle get command
  if($cmd eq 'get') {
    return cerr $c, parse => 'Invalid arguments to get command' if @$arg < 3 || @$arg > 4
      || ref($arg->[0]) || ref($arg->[1]) || ref($arg->[2]) ne 'POE::Filter::VNDBAPI::filter'
      || exists($arg->[3]) && ref($arg->[3]) ne 'HASH';
    my $opt = $arg->[3] || {};
    return cerr $c, badarg => 'Invalid argument for the "page" option', field => 'page'
      if defined($opt->{page}) && (ref($opt->{page}) || $opt->{page} !~ /^\d+$/ || $opt->{page} < 1);
    return cerr $c, badarg => 'Invalid argument for the "results" option', field => 'results'
      if defined($opt->{results}) && (ref($opt->{results}) || $opt->{results} !~ /^\d+$/ || $opt->{results} < 1 || $opt->{results} > $_[HEAP]{max_results});
    return cerr $c, badarg => '"reverse" option must be boolean', field => 'reverse'
      if defined($opt->{reverse}) && !JSON::XS::is_bool($opt->{reverse});
    return cerr $c, badarg => '"sort" option must be a string', field => 'sort'
      if defined($opt->{sort}) && ref($opt->{sort});
    $opt->{page} = $opt->{page}||1;
    $opt->{results} = $opt->{results}||$_[HEAP]{default_results};
    $opt->{reverse} = defined($opt->{reverse}) && $opt->{reverse};
    my %obj = (
      c => $c,
      info => [ split /,/, $arg->[1] ],
      filters => $arg->[2],
      opt => $opt,
    );
    return cerr $c, 'gettype', "Unknown get type: '$arg->[0]'" if $arg->[0] !~ /^(?:vn|release|producer)$/;
    return $_[KERNEL]->yield("get_$arg->[0]", \%obj);
  }

  # unknown command
  return cerr $c, 'parse', "Unknown command '$cmd'" if $cmd ne 'get';
}


sub login {
  my($c, $arg) = @_[ARG0,ARG1];

  # validation (bah)
  return cerr $c, parse => 'Argument to login must be a single JSON object' if @$arg != 1 || ref($arg->[0]) ne 'HASH';
  $arg = $arg->[0];
  return cerr $c, loggedin => 'Already logged in, please reconnect to start a new session' if $c->{username};
  for (qw|protocol client clientver username password|) {
    !exists $arg->{$_}  && return cerr $c, missing => "Required field '$_' is missing", field => $_;
    !defined $arg->{$_} && return cerr $c, badarg  => "Field '$_' cannot be null", field => $_;
    # note that 'true' and 'false' are also refs
    ref $arg->{$_}      && return cerr $c, badarg  => "Field '$_' must be a scalar", field => $_;
  }
  return cerr $c, badarg => 'Unknown protocol version', field => 'protocol' if $arg->{protocol}  ne '1';
  return cerr $c, badarg => 'Invalid client name', field => 'client'        if $arg->{client}    !~ /^[a-zA-Z0-9 _-]{3,50}$/;
  return cerr $c, badarg => 'Invalid client version', field => 'clientver'  if $arg->{clientver} !~ /^[a-zA-Z0-9_.\/-]{1,25}$/;
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

  # link this connection to the users' throttle array (create this if necessary)
  $throttle{$arg->{username}} = [ time, time ] if !$throttle{$arg->{username}};
  $c->{throttle} = $throttle{$arg->{username}};

  $c->{username} = $arg->{username};
  $c->{client} = $arg->{client};
  $c->{clientver} = $arg->{clientver};

  $c->{wheel}->put(['ok']);
  $_[KERNEL]->yield(log => $c,
    'Successful login by %s using client "%s" ver. %s', $arg->{username}, $arg->{client}, $arg->{clientver});
}


sub get_results {
  my $get = $_[ARG0]; # hashref, must contain: type, c, queries, time, list, info, filters, more, opt

  # update sql throttle
  $get->{c}{throttle}[1] += $get->{time}*$_[HEAP]{throttle_sql}[0];

  # send and log
  my $num = @{$get->{list}};
  $get->{c}{wheel}->put([ results => { num => $num, more => $get->{more} ? TRUE : FALSE, items => $get->{list} }]);
  $_[KERNEL]->yield(log => $get->{c}, "T:%4.0fms  Q:%d  R:%02d get %s %s %s {%s %s, page %d}",
    $get->{time}*1000, $get->{queries}, $num, $get->{type}, join(',', @{$get->{info}}), encode_filters($get->{filters}),
    $get->{opt}{sort}, $get->{opt}{reverse}?'desc':'asc', $get->{opt}{page});
}


sub get_vn {
  my $get = $_[ARG0];

  return cerr $get->{c}, getinfo => "Unknown info flag '$_'", flag => $_
    for (grep !/^(basic|details|anime|relations)$/, @{$get->{info}});

  my $select = 'v.id, v.latest';
  $select .= ', vr.title, vr.original, v.c_released, v.c_languages::text[], v.c_platforms' if grep /basic/, @{$get->{info}};
  $select .= ', vr.image, vr.img_nsfw, vr.alias AS aliases, vr.length, vr.desc AS description, vr.l_wp, vr.l_encubed, vr.l_renai' if grep /details/, @{$get->{info}};

  my @placeholders;
  my $where = encode_filters $get->{filters}, \&filtertosql, $get->{c}, \@placeholders, [
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
    ], [ 'released',
      [ undef,   'v.c_released :op: 0', {qw|= =  != <>|} ],
      [ str   => 'v.c_released :op: :value:', {qw|= =  != <>  > >  < <  <= <=  >= >=|}, process => \&parsedate ],
    ], [ 'platforms',
      [ undef,   "v.c_platforms :op: ''", {qw|= =  != <>|} ],
      [ str   => 'v.c_platforms :op: :value:', {'=' => 'LIKE', '!=' => 'NOT LIKE'}, process => \'like' ],
      [ stra  => '(:value:)', {'=', 1}, join => ' OR ',  serialize => 'v.c_platforms LIKE :value:', process => \'like' ],
      [ stra  => '(:value:)', {'!=',1}, join => ' AND ', serialize => 'v.c_platforms NOT LIKE :value:', process => \'like' ],
    ], [ 'languages',
      [ undef,   "v.c_languages :op: '{}'", {qw|= =  != <>|} ],
      [ str   => ':op: (v.c_languages && ARRAY[:value:]::language[])', {'=' => '', '!=' => 'NOT'} ],
      [ stra  => ':op: (v.c_languages && ARRAY[:value:]::language[])', {'=' => '', '!=' => 'NOT'}, join => ',' ],
    ], [ 'search',
      [ str   => '(:value:)', {'=',1}, split => \&normalize_query,
                  join => ' AND ', serialize => 'v.c_search LIKE :value:', process => \'like' ],
    ],
  ];
  my $last = sqllast $get, 'id', {
    id => 'v.id %s',
    title => 'vr.title %s',
    released => 'v.c_released %s',
  };
  return if !$last || !$where;

  $_[KERNEL]->post(pg => query =>
    qq|SELECT $select FROM vn v JOIN vn_rev vr ON v.latest = vr.id WHERE NOT v.hidden AND $where $last|,
    \@placeholders, 'get_vn_res', $get);
}


sub get_vn_res {
  my($num, $res, $get, $time) = (@_[ARG0..$#_]);

  $get->{time} += $time;
  $get->{queries}++;

  # process the results
  if(!$get->{type}) {
    for (@$res) {
      $_->{id}*=1;
      if(grep /basic/, @{$get->{info}}) {
        $_->{original}  ||= undef;
        $_->{platforms} = [ split /\//, delete $_->{c_platforms} ];
        $_->{languages} = delete $_->{c_languages};
        $_->{released}  = formatdate delete $_->{c_released};
      }
      if(grep /details/, @{$get->{info}}) {
        $_->{aliases}     ||= undef;
        $_->{length}      *= 1;
        $_->{length}      ||= undef;
        $_->{description} ||= undef;
        $_->{image_nsfw}  = delete($_->{img_nsfw}) ? TRUE : FALSE;
        $_->{links} = {
          wikipedia => delete($_->{l_wp})     ||undef,
          encubed   => delete($_->{l_encubed})||undef,
          renai     => delete($_->{l_renai})  ||undef
        };
        $_->{image} = $_->{image} ? sprintf '%s/cv/%02d/%d.jpg', $VNDB::S{url_static}, $_->{image}%100, $_->{image} : undef;
      }
    }
    $get->{more} = pop(@$res)&&1 if @$res > $get->{results};
    $get->{list} = $res;
  }

  elsif($get->{type} eq 'anime') {
    # link
    for my $i (@{$get->{list}}) {
      $i->{anime} = [ grep $i->{latest} == $_->{vid}, @$res ];
    }
    # cleanup
    for (@$res) {
      $_->{id}     *= 1;
      $_->{year}   *= 1 if defined $_->{year};
      $_->{ann_id} *= 1 if defined $_->{ann_id};
      delete $_->{vid};
    }
    $get->{anime} = 1;
  }

  elsif($get->{type} eq 'relations') {
    for my $i (@{$get->{list}}) {
      $i->{relations} = [ grep $i->{latest} == $_->{vid1}, @$res ];
    }
    for (@$res) {
      $_->{id} *= 1;
      $_->{original} ||= undef;
      delete $_->{vid1};
    }
    $get->{relations} = 1;
  }

  # fetch more results
  my @ids = map $_->{latest}, @{$get->{list}};
  my $ids = join ',', map '?', @ids;

  @ids && !$get->{anime} && grep(/anime/, @{$get->{info}}) && return $_[KERNEL]->post(pg => query => qq|
    SELECT va.vid, a.id, a.year, a.ann_id, a.nfo_id, a.type, a.title_romaji, a.title_kanji
      FROM anime a JOIN vn_anime va ON va.aid = a.id WHERE va.vid IN($ids)|,
    \@ids, 'get_vn_res', { %$get, type => 'anime' });

  @ids && !$get->{relations} && grep(/relations/, @{$get->{info}}) && return $_[KERNEL]->post(pg => query => qq|
    SELECT vl.vid1, v.id, vl.relation, vr.title, vr.original FROM vn_relations vl
      JOIN vn v ON v.id = vl.vid2 JOIN vn_rev vr ON vr.id = v.latest WHERE vl.vid1 IN($ids) AND NOT v.hidden|,
    \@ids, 'get_vn_res', { %$get, type => 'relations' });

  # send results
  delete $_->{latest} for @{$get->{list}};
  $_[KERNEL]->yield(get_results => { %$get, type => 'vn' });
}


sub get_release {
  my $get = $_[ARG0];

  return cerr $get->{c}, getinfo => "Unknown info flag '$_'", flag => $_ for (grep !/^(basic|details|vn|producers)$/, @{$get->{info}});

  my $select = 'r.id, r.latest';
  $select .= ', rr.title, rr.original, rr.released, rr.type, rr.patch, rr.freeware, rr.doujin' if grep /basic/, @{$get->{info}};
  $select .= ', rr.website, rr.notes, rr.minage, rr.gtin, rr.catalog' if grep /details/, @{$get->{info}};

  my @placeholders;
  my $where = encode_filters $get->{filters}, \&filtertosql, $get->{c}, \@placeholders, [
    [ 'id',
      [ 'int' => 'r.id :op: :value:', {qw|= =  != <>  > >  >= >=  < <  <= <=|} ],
      [ inta  => 'r.id :op:(:value:)', {'=' => 'IN', '!=' => 'NOT IN'}, join => ',' ],
    ], [ 'vn',
      [ 'int' => 'rr.id IN(SELECT rv.rid FROM releases_vn rv WHERE rv.vid = :value:)', {'=',1} ],
    ], [ 'producer',
      [ 'int' => 'rr.id IN(SELECT rp.rid FROM releases_producers rp WHERE rp.pid = :value:)', {'=',1} ],
    ], [ 'title',
      [ str   => 'rr.title :op: :value:', {qw|= =  != <>|} ],
      [ str   => 'rr.title ILIKE :value:', {'~',1}, process => \'like' ],
    ], [ 'original',
      [ undef,   "rr.original :op: ''", {qw|= =  != <>|} ],
      [ str   => 'rr.original :op: :value:', {qw|= =  != <>|} ],
      [ str   => 'rr.original ILIKE :value:', {'~',1}, process => \'like' ]
    ], [ 'released',
      [ undef,   'rr.released :op: 0', {qw|= =  != <>|} ],
      [ str   => 'rr.released :op: :value:', {qw|= =  != <>  > >  < <  <= <=  >= >=|}, process => \&parsedate ],
    ], [ 'patch',    [ bool  => 'rr.patch = :value:',    {'=',1} ],
    ], [ 'freeware', [ bool  => 'rr.freeware = :value:', {'=',1} ],
    ], [ 'doujin',   [ bool  => 'rr.doujin = :value:',   {'=',1} ],
    ], [ 'type',
      [ str   => 'rr.type :op: :value:', {qw|= =  != <>|},
        process => sub { !grep($_ eq $_[0], @{$VNDB::S{release_types}}) ? \'No such release type' : $_[0] } ],
    ], [ 'gtin',
      [ 'int' => 'rr.gtin :op: :value:', {qw|= =  != <>|} ],
    ], [ 'catalog',
      [ str   => 'rr.catalog :op: :value:', {qw|= =  != <>|} ],
    ], [ 'languages',
      [ str   => 'rr.id :op:(SELECT rl.rid FROM releases_lang rl WHERE rl.lang = :value:)', {'=' => 'IN', '!=' => 'NOT IN'}, process => \'lang' ],
      [ stra  => 'rr.id :op:(SELECT rl.rid FROM releases_lang rl WHERE rl.lang IN(:value:))', {'=' => 'IN', '!=' => 'NOT IN'}, join => ',', process => \'lang' ],
    ],
  ];
  my $last = sqllast $get, 'id', {
    id => 'r.id %s',
    title => 'rr.title %s',
    released => 'rr.released %s',
  };
  return if !$where || !$last;

  $_[KERNEL]->post(pg => query =>
    qq|SELECT $select FROM releases r JOIN releases_rev rr ON rr.id = r.latest WHERE $where AND NOT hidden $last|,
    \@placeholders, 'get_release_res', $get);
}


sub get_release_res {
  my($num, $res, $get, $time) = (@_[ARG0..$#_]);

  $get->{time} += $time;
  $get->{queries}++;

  # process the results
  if(!$get->{type}) {
    for (@$res) {
      $_->{id}*=1;
      if(grep /basic/, @{$get->{info}}) {
        $_->{original} ||= undef;
        $_->{released} = formatdate($_->{released});
        $_->{patch}    = $_->{patch}    ? TRUE : FALSE;
        $_->{freeware} = $_->{freeware} ? TRUE : FALSE;
        $_->{doujin}   = $_->{doujin}   ? TRUE : FALSE;
      }
      if(grep /details/, @{$get->{info}}) {
        $_->{website}  ||= undef;
        $_->{notes}    ||= undef;
        $_->{minage}    *= 1 if defined $_->{minage};
        $_->{gtin}     ||= undef;
        $_->{catalog}  ||= undef;
      }
    }
    $get->{more} = pop(@$res)&&1 if @$res > $get->{results};
    $get->{list} = $res;
  }
  elsif($get->{type} eq 'languages') {
    for my $i (@{$get->{list}}) {
      $i->{languages} = [ map $i->{latest} == $_->{rid} ? $_->{lang} : (), @$res ];
    }
    $get->{languages} = 1;
  }
  elsif($get->{type} eq 'platforms') {
    for my $i (@{$get->{list}}) {
      $i->{platforms} = [ map $i->{latest} == $_->{rid} ? $_->{platform} : (), @$res ];
    }
    $get->{platforms} = 1;
  }
  elsif($get->{type} eq 'media') {
    for my $i (@{$get->{list}}) {
      $i->{media} = [ grep $i->{latest} == $_->{rid}, @$res ];
    }
    for (@$res) {
      delete $_->{rid};
      $_->{qty} = $VNDB::S{media}{$_->{medium}} ? $_->{qty}*1 : undef;
    }
    $get->{media} = 1;
  }
  elsif($get->{type} eq 'vn') {
    for my $i (@{$get->{list}}) {
      $i->{vn} = [ grep $i->{latest} == $_->{rid}, @$res ];
    }
    for (@$res) {
      $_->{id}*=1;
      $_->{original} ||= undef;
      delete $_->{rid};
    }
    $get->{vn} = 1;
  }
  elsif($get->{type} eq 'producers') {
    for my $i (@{$get->{list}}) {
      $i->{producers} = [ grep $i->{latest} == $_->{rid}, @$res ];
    }
    for (@$res) {
      $_->{id}*=1;
      $_->{original}  ||= undef;
      $_->{developer} = $_->{developer} ? TRUE : FALSE;
      $_->{publisher} = $_->{publisher} ? TRUE : FALSE;
      delete $_->{rid};
    }
    $get->{producers} = 1;
  }

  # get more info
  my @ids = map $_->{latest}, @{$get->{list}};
  my $ids = join ',', map '?', @ids;

  @ids && !$get->{languages} && grep(/basic/, @{$get->{info}}) && return $_[KERNEL]->post(pg => query =>
    qq|SELECT rid, lang FROM releases_lang WHERE rid IN($ids)|,
    \@ids, 'get_release_res', { %$get, type => 'languages' });

  @ids && !$get->{platforms} && grep(/details/, @{$get->{info}}) && return $_[KERNEL]->post(pg => query =>
    qq|SELECT rid, platform FROM releases_platforms WHERE rid IN($ids)|,
    \@ids, 'get_release_res', { %$get, type => 'platforms' });

  @ids && !$get->{media} && grep(/details/, @{$get->{info}}) && return $_[KERNEL]->post(pg => query =>
    qq|SELECT rid, medium, qty FROM releases_media WHERE rid IN($ids)|,
    \@ids, 'get_release_res', { %$get, type => 'media' });

  @ids && !$get->{vn} && grep(/vn/, @{$get->{info}}) && return $_[KERNEL]->post(pg => query => qq|
    SELECT rv.rid, v.id, vr.title, vr.original FROM releases_vn rv JOIN vn v ON v.id = rv.vid
      JOIN vn_rev vr ON vr.id = v.latest WHERE NOT v.hidden AND rv.rid IN($ids)|,
    \@ids, 'get_release_res', { %$get, type => 'vn' });

  @ids && !$get->{producers} && grep(/producers/, @{$get->{info}}) && return $_[KERNEL]->post(pg => query => qq|
    SELECT rp.rid, rp.developer, rp.publisher, p.id, pr.type, pr.name, pr.original FROM releases_producers rp
      JOIN producers p ON p.id = rp.pid JOIN producers_rev pr ON pr.id = p.latest WHERE NOT p.hidden AND rp.rid IN($ids)|,
    \@ids, 'get_release_res', { %$get, type => 'producers' });

  # send results
  delete $_->{latest} for @{$get->{list}};
  $_[KERNEL]->yield(get_results => { %$get, type => 'release' });
}


sub get_producer {
  my $get = $_[ARG0];

  return cerr $get->{c}, getinfo => "Unknown info flag '$_'", flag => $_
    for (grep !/^(basic|details|relations)$/, @{$get->{info}});

  my $select = 'p.id, p.latest';
  $select .= ', pr.type, pr.name, pr.original, pr.lang AS language' if grep /basic/, @{$get->{info}};
  $select .= ', pr.website, pr.l_wp, pr.desc AS description, pr.alias AS aliases' if grep /details/, @{$get->{info}};

  my @placeholders;
  my $where = encode_filters $get->{filters}, \&filtertosql, $get->{c}, \@placeholders, [
    [ 'id',
      [ 'int' => 'p.id :op: :value:', {qw|= =  != <>  > >  < <  <= <=  >= >=|} ],
      [ inta  => 'p.id :op:(:value:)', {'=' => 'IN', '!= ' => 'NOT IN'}, join => ',' ],
    ], [ 'name',
      [ str   => 'pr.name :op: :value:', {qw|= =  != <>|} ],
      [ str   => 'pr.name ILIKE :value:', {'~',1}, process => \'like' ],
    ], [ 'original',
      [ undef,   "pr.original :op: ''", {qw|= =  != <>|} ],
      [ str   => 'pr.original :op: :value:', {qw|= =  != <>|} ],
      [ str   => 'pr.original ILIKE :value:', {'~',1}, process => \'like' ]
    ], [ 'type',
      [ str   => 'pr.type :op: :value:', {qw|= =  != <>|},
        process => sub { !grep($_ eq $_[0], @{$VNDB::S{producer_types}}) ? \'No such producer type' : $_[0] } ],
    ], [ 'language',
      [ str   => 'pr.lang :op: :value:', {qw|= =  != <>|}, process => \'lang' ],
      [ stra  => 'pr.lang :op:(:value:)', {'=' => 'IN', '!=' => 'NOT IN'}, join => ',', process => \'lang' ],
    ], [ 'search',
      [ str   => '(pr.name ILIKE :value: OR pr.original ILIKE :value: OR pr.alias ILIKE :value:)', {'~',1}, process => \'like' ],
    ],
  ];
  my $last = sqllast $get, 'id', {
    id => 'p.id %s',
    name => 'pr.name %s',
  };
  return if !$where || !$last;

  $_[KERNEL]->post(pg => query =>
    qq|SELECT $select FROM producers p JOIN producers_rev pr ON pr.id = p.latest WHERE $where AND NOT hidden $last|,
    \@placeholders, 'get_producer_res', $get);
}


sub get_producer_res {
  my($num, $res, $get, $time) = (@_[ARG0..$#_]);

  $get->{time} += $time;
  $get->{queries}++;

  # process the results
  if(!$get->{type}) {
    for (@$res) {
      $_->{id}*=1;
      $_->{original} ||= undef if grep /basic/, @{$get->{info}};
      if(grep /details/, @{$get->{info}}) {
        $_->{links} = {
          homepage  => delete($_->{website})||undef,
          wikipedia => delete $_->{l_wp},
        };
        $_->{description} ||= undef;
        $_->{aliases}     ||= undef;
      }
    }
    $get->{more} = pop(@$res)&&1 if @$res > $get->{results};
    $get->{list} = $res;
  }
  elsif($get->{type} eq 'relations') {
    for my $i (@{$get->{list}}) {
      $i->{relations} = [ grep $i->{latest} == $_->{pid1}, @$res ];
    }
    for (@$res) {
      $_->{id}*=1;
      $_->{original} ||= undef;
      delete $_->{pid1};
    }
    $get->{relations} = 1;
  }

  # get more info
  my @ids = map $_->{latest}, @{$get->{list}};
  my $ids = join ',', map '?', @ids;

  @ids && !$get->{relations} && grep(/relations/, @{$get->{info}}) && return $_[KERNEL]->post(pg => query => qq|
    SELECT pl.pid1, p.id, pl.relation, pr.name, pr.original FROM producers_relations pl
      JOIN producers p ON p.id = pl.pid2 JOIN producers_rev pr ON pr.id = p.latest WHERE pl.pid1 IN($ids) AND NOT p.hidden|,
    \@ids, 'get_producer_res', { %$get, type => 'relations' });

  # send results
  delete $_->{latest} for @{$get->{list}};
  $_[KERNEL]->yield(get_results => { %$get, type => 'producer' });
}


# can be call()'ed from other sessions (specifically written for IRC)
sub admin {
  my($func, @arg) = @_[ARG0..$#_];

  if($func eq 'stats') {
    return { %{$_[HEAP]{s}}, online => scalar keys %{$_[HEAP]{c}} };
  }
  if($func eq 'list') {
    return [ map {
      my $c = $_[HEAP]{c}{$_};
      my $r = { # make sure not to return our wheel
        id => $_,
        (map +($_, $c->{$_}), qw|username ip client clientver connected cmds cmd_err|)
      };
      if($c->{username}) {
        $r->{t_cmd} = ($c->{throttle}[0]-time())/$_[HEAP]{throttle_cmd}[0];
        $r->{t_sql} = ($c->{throttle}[1]-time())/$_[HEAP]{throttle_sql}[0];
        $r->{t_cmd} = 0 if $r->{t_cmd} < 0;
        $r->{t_sql} = 0 if $r->{t_sql} < 0;
      }
      $r
    } keys %{$_[HEAP]{c}} ];
  }
  if($func eq 'bans') {
    return $_[HEAP]{ipbans};
  }
  if($func eq 'ban') {
    my $ip = $_[HEAP]{c}{$arg[0]} ? $_[HEAP]{c}{$arg[0]}{ip} : $arg[0];
    return undef if !$ip || $ip !~ /^\d{1,3}(?:\.\d{1,3}){3}$/;
    push @{$_[HEAP]{ipbans}}, $ip;
    delete $_[HEAP]{c}{$_} for grep $_[HEAP]{c}{$_}{ip} eq $ip, keys %{$_[HEAP]{c}};
  }
  if($func eq 'unban') {
    $_[HEAP]{ipbans} = [ grep $_ ne $arg[0], @{$_[HEAP]{ipbans}} ];
  }
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
    'bool'
  sql string:
    The relevant SQL string, with :op: and :value: subsistutions. :value: is not available for type=undef
  split: (only when the type is str)
    sub, splits the string into an array and further processes it as if it was of type 'stra'
  join: (only used when type is an array)
    scalar, join string used when joining multiple values.
  serialize: (serializes the values before join()'ing, only for arrays)
    scalar, :op: and :value: subsistution
  process: (process the value(s) that will be passed to Pg)
    scalar, %s subsitutes the value
    sub, argument = value, returns new value
    scalarref, template:
      \'like' => sub { (local$_=shift)=~y/%//; lc "%$_%" }
      \'lang' => sub { !grep($_ eq $_[0], @{$VNDB::S{languages}}) ? \'Invalid language' : $_[0] }

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

