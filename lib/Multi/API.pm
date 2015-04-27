
#
#  Multi::API  -  The public VNDB API
#

package Multi::API;

use strict;
use warnings;
use Multi::Core;
use AnyEvent::Socket;
use AnyEvent::Handle;
use POE::Filter::VNDBAPI 'encode_filters';
use Digest::SHA 'sha256';
use Encode 'encode_utf8';
use Crypt::ScryptKDF 'scrypt_raw';;
use VNDBUtil 'normalize_query', 'norm_ip';
use JSON::XS;


# what our JSON encoder considers 'true' or 'false'
sub TRUE  () { JSON::XS::true }
sub FALSE () { JSON::XS::false }

my %O = (
  port => 19534,
  logfile => "$VNDB::M{log_dir}/api.log",
  conn_per_ip => 5,
  max_results => 25, # For get vn/release/producer/character
  max_results_lists => 100, # For get votelist/vnlist/wishlist
  default_results => 10,
  throttle_cmd => [ 6, 100 ], # interval between each command, allowed burst
  throttle_sql => [ 60, 1 ], # sql time multiplier, allowed burst (in sql time)
);


my %C;
my $connid = 0;


sub writelog {
  my $c = ref $_[0] && shift;
  my($msg, @args) = @_;
  if(open(my $F, '>>:utf8', $O{logfile})) {
    printf $F "[%s] %s: %s\n", scalar localtime,
      $c ? sprintf '%d %s:%d', $c->{id}, $c->{ip}, $c->{port} : 'global',
      @args ? sprintf $msg, @args : $msg;
    close $F;
  }
}


sub run {
  shift;
  %O = (%O, @_);

  push_watcher tcp_server undef, $O{port}, \&newconn;
  writelog 'API starting up on port %d', $O{port};
}


sub unload {
  $C{$_}{h}->destroy() for keys %C;
  %C = ();
}


sub newconn {
  my $c = {
    fh    => $_[0],
    ip    => $_[1],
    port  => $_[2],
    id    => ++$connid,
    cid   => norm_ip($_[1]),
    filt  => POE::Filter::VNDBAPI->new(),
  };

  if($O{conn_per_ip} <= grep $c->{ip} eq $C{$_}{ip}, keys %C) {
    writelog $c, 'Connection denied, limit of %d connections per IP reached', $O{conn_per_ip};
    close $c->{fh};
    return;
  }

  writelog $c, 'Connected';
  $C{$connid} = $c;

  $c->{h} = AnyEvent::Handle->new(
    rbuf_max =>     50*1024, # Commands aren't very huge, a 50k read buffer should suffice.
    wbuf_max => 5*1024*1024,
    fh       => $c->{fh},
    on_error => sub {
      writelog $c, 'IO error: %s', $_[2];
      $c->{h}->destroy;
      delete $C{$c->{id}};
    },
    on_eof => sub {
      writelog $c, 'Disconnected';
      $c->{h}->destroy;
      delete $C{$c->{id}};
    },
  );
  cmd_read($c);
}


sub cres {
  my($c, $msg, $log, @arg) = @_;
  $msg = $c->{filt}->put([$msg])->[0];
  $c->{h}->push_write($msg);
  writelog $c, '[%2d/%4.0fms %5.0f] %s',
    $c->{sqlq}, $c->{sqlt}*1000, length($msg),
    @arg ? sprintf $log, @arg : $log;
  cmd_read($c);
}


sub cerr {
  my($c, $id, $msg, %o) = @_;
  cres $c, [ error => { id => $id, msg => $msg, %o } ], "Error: %s, %s", $id, $msg;
  return undef;
}


# Wrapper around pg_cmd() that updates the SQL throttle for the client and
# sends an error response if the query error'ed. The callback is not called on
# error.
sub cpg {
  my($c, $q, $a, $cb) = @_;
  pg_cmd $q, $a, sub {
    my($res, $time) = @_;
    $c->{sqlq}++;
    $c->{sqlt} += $time;
    return cerr $c, internal => 'SQL error' if pg_expect $res;
    throttle $O{throttle_sql}, "api_sql_$c->{cid}", $time;
    $cb->($res);
  };
}


sub cmd_read {
  my $c = shift;

  # Prolly should make POE::Filter::VNDBAPI aware of AnyEvent::Handle stuff, so
  # this code wouldn't require a few protocol specific chunks.
  $c->{h}->push_read(line => "\x04", sub {
    my $cmd = $c->{filt}->get([$_[1], "\x04"]);
    die "No or too many commands in a single message" if @$cmd != 1;

    my @arg;
    ($cmd, @arg) = @{$cmd->[0]};

    # log raw message (except login command, which may include a password)
    (my $msg = $_[1]) =~ s/[\r\n]*/ /;
    $msg =~ s/^[\s\r\n\t]+//;
    $msg =~ s/[\s\r\n\t]+$//;
    writelog $c, "< $msg" if $cmd && $cmd ne 'login';

    # Stats for the current cmd
    $c->{sqlt} = $c->{sqlq} = 0;

    # parse error
    return cerr $c, $arg[0]{id}, $arg[0]{msg} if !defined $cmd;

    # check for thottle rule violation
    for ('cmd', 'sql') {
      my $left = throttle $O{"throttle_$_"}, "api_${_}_$c->{cid}", 0;
      return cerr $c, throttled => 'Throttle limit reached.', type => $_,
          minwait  => int(10*($left))/10+1,
          fullwait => int(10*($left + $O{"throttle_$_"}[0] * $O{"throttle_$_"}[1]))/10+1
        if $left;
    }

    # update commands/second throttle
    throttle $O{throttle_cmd}, "api_cmd_$c->{cid}";
    cmd_handle($c, $cmd, @arg);
  });
}


sub cmd_handle {
  my($c, $cmd, @arg) = @_;

  # login
  return login($c, @arg) if $cmd eq 'login';
  return cerr $c, needlogin => 'Not logged in.' if !$c->{client};

  # dbstats
  if($cmd eq 'dbstats') {
    return cerr $c, parse => 'Invalid arguments to get command' if @arg > 0;
    return dbstats($c);
  }

  # get
  if($cmd eq 'get') {
    return get($c, @arg);
  }

  # set
  if($cmd eq 'set') {
    return set($c, @arg);
  }

  # unknown command
  cerr $c, 'parse', "Unknown command '$cmd'";
}


sub login {
  my($c, @arg) = @_;

  # validation (bah)
  return cerr $c, parse => 'Argument to login must be a single JSON object' if @arg != 1 || ref($arg[0]) ne 'HASH';
  my $arg = $arg[0];
  return cerr $c, loggedin => 'Already logged in, please reconnect to start a new session' if $c->{client};

  !exists $arg->{$_} && return cerr $c, missing => "Required field '$_' is missing", field => $_
    for(qw|protocol client clientver|);
  for(qw|protocol client clientver username password|) {
    exists $arg->{$_} && !defined $arg->{$_} && return cerr $c, badarg  => "Field '$_' cannot be null", field => $_;
    exists $arg->{$_} && ref $arg->{$_}      && return cerr $c, badarg  => "Field '$_' must be a scalar", field => $_;
  }
  return cerr $c, badarg => 'Unknown protocol version', field => 'protocol' if $arg->{protocol}  ne '1';
  return cerr $c, badarg => 'The fields "username" and "password" must either both be present or both be missing.', field => 'username'
    if exists $arg->{username} && !exists $arg->{password} || exists $arg->{password} && !exists $arg->{username};
  return cerr $c, badarg => 'Invalid client name', field => 'client'        if $arg->{client}    !~ /^[a-zA-Z0-9 _-]{3,50}$/;
  return cerr $c, badarg => 'Invalid client version', field => 'clientver'  if $arg->{clientver} !~ /^[a-zA-Z0-9_.\/-]{1,25}$/;

  if(!exists $arg->{username}) {
    $c->{client} = $arg->{client};
    $c->{clientver} = $arg->{clientver};
    cres $c, ['ok'], 'Login using client "%s" ver. %s', $c->{client}, $c->{clientver};
    return;
  }

  login_auth($c, $arg);
}


sub login_auth {
  my($c, $arg) = @_;

  # check login throttle
  cpg $c, 'SELECT extract(\'epoch\' from timeout) FROM login_throttle WHERE ip = $1', [ norm_ip($c->{ip}) ], sub {
    my $tm = $_[0]->nRows ? $_[0]->value(0,0) : AE::time;
    return cerr $c, auth => "Too many failed login attempts"
      if $tm-AE::time() > $VNDB::S{login_throttle}[1];

    # Fetch user info
    cpg $c, 'SELECT id, encode(passwd, \'hex\') FROM users WHERE username = $1', [ $arg->{username} ], sub {
      login_verify($c, $arg, $tm, $_[0]);
    };
  };
}


sub login_verify {
  my($c, $arg, $tm, $res) = @_;

  return cerr $c, auth => "No user with the name '$arg->{username}'" if $res->nRows == 0;

  my $passwd = pack 'H*', $res->value(0,1);
  my $uid = $res->value(0,0);
  my $accepted = 0;

  if(length $passwd == 41) { # Old sha256
    my $salt = substr $passwd, 0, 9;
    $accepted = sha256($VNDB::S{global_salt}.encode_utf8($arg->{password}).$salt) eq substr $passwd, 9;
  } elsif(length $passwd == 46) { # New scrypt
    my($N, $r, $p, $salt, $hash) = unpack 'NCCa8a*', $passwd;
    $accepted = $hash eq scrypt_raw($arg->{password}, $VNDB::S{scrypt_salt} . $salt, $N, $r, $p, 32);
  } else {
    return cerr $c, auth => "Account disabled";
  }

  if($accepted) {
    $c->{uid} = $uid;
    $c->{username} = $arg->{username};
    $c->{client} = $arg->{client};
    $c->{clientver} = $arg->{clientver};
    cres $c, ['ok'], 'Successful login by %s (%s) using client "%s" ver. %s', $arg->{username}, $c->{uid}, $c->{client}, $c->{clientver};

  } else {
    my @a = ( $tm + $VNDB::S{login_throttle}[0], norm_ip($c->{ip}) );
    pg_cmd 'UPDATE login_throttle SET timeout = to_timestamp($1) WHERE ip = $2', \@a;
    pg_cmd 'INSERT INTO login_throttle (ip, timeout) SELECT $2, to_timestamp($1) WHERE NOT EXISTS(SELECT 1 FROM login_throttle WHERE ip = $2)', \@a;
    cerr $c, auth => "Wrong password for user '$arg->{username}'";
  }
}


sub dbstats {
  my $c = shift;

  cpg $c, 'SELECT section, count FROM stats_cache', undef, sub {
    my $res = shift;
    cres $c, [ dbstats => { map {
      $_->{section} =~ s/^threads_//;
      ($_->{section}, 1*$_->{count})
    } $res->rowsAsHashes } ], 'dbstats';
  };
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


sub splitarray {
  (my $s = shift) =~ s/^{(.*)}$/$1/;
  return [ split /,/, $s ];
}


# sql     => str: Main sql query, three printf args: select, where part, order by and limit clauses
# sqluser => str: Alternative to 'sql' if the user is logged in. One additional printf arg: user id.
#            If sql is undef and sqluser isn't, the command is only available to logged in users.
# select  => str: string to add to the select part of the main query
# proc    => &sub->($row): called on each row of the main query
# sorts   => { sort_key => sql_string }, %s is replaced with 'ASC/DESC' in sql_string
# sortdef => str: default sort (as per 'sorts')
# islist  => bool: Whether this is a vnlist/wishlist/votelist thing (determines max results)
# flags   => {
#   flag_name => {
#     select    => str: string to add to the select part of the main query
#     proc      => &sub->($row): same as parent proc
#     fetch     => [ [
#       idx:  str: name of the field from the main query to get the id list from,
#       sql:  str: SQL query to fetch more data. %s is replaced with the list of ID's based on fetchidx
#       proc: &sub->($rows, $fetchrows)
#     ], .. ],
#   }
# }
# filters => filters args for get_filters() (TODO: Document)
my %GET_VN = (
  sql     => 'SELECT %s FROM vn v JOIN vn_rev vr ON v.latest = vr.id WHERE NOT v.hidden AND (%s) %s',
  select  => 'v.id, v.latest',
  proc    => sub {
    delete $_[0]{latest};
    $_[0]{id} *= 1
  },
  sortdef => 'id',
  sorts   => {
    id => 'v.id %s',
    title => 'vr.title %s',
    released => 'v.c_released %s',
  },
  flags  => {
    basic => {
      select => 'vr.title, vr.original, v.c_released, v.c_languages, v.c_olang, v.c_platforms',
      proc   => sub {
        $_[0]{original}  ||= undef;
        $_[0]{platforms} = splitarray delete $_[0]{c_platforms};
        $_[0]{languages} = splitarray delete $_[0]{c_languages};
        $_[0]{orig_lang} = splitarray delete $_[0]{c_olang};
        $_[0]{released}  = formatdate delete $_[0]{c_released};
      },
    },
    details => {
      select => 'vr.image, vr.img_nsfw, vr.alias AS aliases, vr.length, vr.desc AS description, vr.l_wp, vr.l_encubed, vr.l_renai',
      proc   => sub {
        $_[0]{aliases}     ||= undef;
        $_[0]{length}      *= 1;
        $_[0]{length}      ||= undef;
        $_[0]{description} ||= undef;
        $_[0]{image_nsfw}  = delete($_[0]{img_nsfw}) =~ /t/ ? TRUE : FALSE;
        $_[0]{links} = {
          wikipedia => delete($_[0]{l_wp})     ||undef,
          encubed   => delete($_[0]{l_encubed})||undef,
          renai     => delete($_[0]{l_renai})  ||undef
        };
        $_[0]{image} = $_[0]{image} ? sprintf '%s/cv/%02d/%d.jpg', $VNDB::S{url_static}, $_[0]{image}%100, $_[0]{image} : undef;
      },
    },
    stats => {
      select => 'v.c_popularity, v.c_rating, v.c_votecount',
      proc => sub {
        $_[0]{popularity} = 1 * sprintf '%.2f', 100*(delete $_[0]{c_popularity} or 0);
        $_[0]{rating}     = 1 * sprintf '%.2f', 0.1*(delete $_[0]{c_rating} or 0);
        $_[0]{votecount}  = 1 * delete $_[0]{c_votecount};
      },
    },
    anime => {
      fetch => [[ 'latest', 'SELECT va.vid, a.id, a.year, a.ann_id, a.nfo_id, a.type, a.title_romaji, a.title_kanji
                     FROM anime a JOIN vn_anime va ON va.aid = a.id WHERE va.vid IN(%s)',
        sub { my($r, $n) = @_;
          # link
          for my $i (@$r) {
            $i->{anime} = [ grep $i->{latest} == $_->{vid}, @$n ];
          }
          # cleanup
          for (@$n) {
            $_->{id}     *= 1;
            $_->{year}   *= 1 if defined $_->{year};
            $_->{ann_id} *= 1 if defined $_->{ann_id};
            delete $_->{vid};
          }
        }
      ]],
    },
    relations => {
      fetch => [[ 'latest', 'SELECT vl.vid1, v.id, vl.relation, vr.title, vr.original FROM vn_relations vl
                     JOIN vn v ON v.id = vl.vid2 JOIN vn_rev vr ON vr.id = v.latest WHERE vl.vid1 IN(%s) AND NOT v.hidden',
        sub { my($r, $n) = @_;
          for my $i (@$r) {
            $i->{relations} = [ grep $i->{latest} == $_->{vid1}, @$n ];
          }
          for (@$n) {
            $_->{id} *= 1;
            $_->{original} ||= undef;
            delete $_->{vid1};
          }
        }
      ]],
    },
    tags => {
      fetch => [[ 'id', 'SELECT vid, tag AS id, avg(CASE WHEN ignore THEN NULL ELSE vote END) as score,
                          COALESCE(avg(CASE WHEN ignore THEN NULL ELSE spoiler END), 0) as spoiler
                     FROM tags_vn tv WHERE vid IN(%s) GROUP BY vid, id
                   HAVING avg(CASE WHEN ignore THEN NULL ELSE vote END) > 0',
        sub { my($r, $n) = @_;
          for my $i (@$r) {
            $i->{tags} = [ map
              [ $_->{id}*1, 1*sprintf('%.2f', $_->{score}), 1*sprintf('%.0f', $_->{spoiler}) ],
              grep $i->{id} == $_->{vid}, @$n ];
          }
        },
      ]],
    },
  },
  filters => {
    id => [
      [ 'int' => 'v.id :op: :value:', {qw|= =  != <>  > >  < <  <= <=  >= >=|}, range => [1,1e6] ],
      [ inta  => 'v.id :op:(:value:)', {'=' => 'IN', '!= ' => 'NOT IN'}, range => [1,1e6], join => ',' ],
    ],
    title => [
      [ str   => 'vr.title :op: :value:', {qw|= =  != <>|} ],
      [ str   => 'vr.title ILIKE :value:', {'~',1}, process => \'like' ],
    ],
    original => [
      [ undef,   "vr.original :op: ''", {qw|= =  != <>|} ],
      [ str   => 'vr.original :op: :value:', {qw|= =  != <>|} ],
      [ str   => 'vr.original ILIKE :value:', {'~',1}, process => \'like' ]
    ],
    firstchar => [
      [ undef,   '(:op: ((ASCII(vr.title) < 97 OR ASCII(vr.title) > 122) AND (ASCII(vr.title) < 65 OR ASCII(vr.title) > 90)))', {'=', '', '!=', 'NOT'} ],
      [ str   => 'LOWER(SUBSTR(vr.title, 1, 1)) :op: :value:' => {qw|= = != <>|}, process => sub { shift =~ /^([a-z])$/ ? $1 : \'Invalid character' } ],
    ],
    released => [
      [ undef,   'v.c_released :op: 0', {qw|= =  != <>|} ],
      [ str   => 'v.c_released :op: :value:', {qw|= =  != <>  > >  < <  <= <=  >= >=|}, process => \&parsedate ],
    ],
    platforms => [
      [ undef,   "v.c_platforms :op: '{}'", {qw|= =  != <>|} ],
      [ str   => ':op: (v.c_platforms && ARRAY[:value:]::platform[])', {'=' => '', '!=' => 'NOT'}, process => \'plat' ],
      [ stra  => ':op: (v.c_platforms && ARRAY[:value:]::platform[])', {'=' => '', '!=' => 'NOT'}, join => ',', process => \'plat' ],
    ],
    languages => [
      [ undef,   "v.c_languages :op: '{}'", {qw|= =  != <>|} ],
      [ str   => ':op: (v.c_languages && ARRAY[:value:]::language[])', {'=' => '', '!=' => 'NOT'}, process => \'lang' ],
      [ stra  => ':op: (v.c_languages && ARRAY[:value:]::language[])', {'=' => '', '!=' => 'NOT'}, join => ',', process => \'lang' ],
    ],
    orig_lang => [
      [ str   => ':op: (v.c_olang && ARRAY[:value:]::language[])', {'=' => '', '!=' => 'NOT'}, process => \'lang' ],
      [ stra  => ':op: (v.c_olang && ARRAY[:value:]::language[])', {'=' => '', '!=' => 'NOT'}, join => ',', process => \'lang' ],
    ],
    search => [
      [ str   => '(:value:)', {'~',1}, split => \&normalize_query,
                  join => ' AND ', serialize => 'v.c_search LIKE :value:', process => \'like' ],
    ]
  },
);

my %GET_RELEASE = (
  sql     => 'SELECT %s FROM releases r JOIN releases_rev rr ON rr.id = r.latest WHERE NOT hidden AND (%s) %s',
  select  => 'r.id, r.latest',
  sortdef => 'id',
  sorts   => {
    id => 'r.id %s',
    title => 'rr.title %s',
    released => 'rr.released %s',
  },
  proc    => sub {
    delete $_[0]{latest};
    $_[0]{id} *= 1
  },
  flags => {
    basic => {
      select => 'rr.title, rr.original, rr.released, rr.type, rr.patch, rr.freeware, rr.doujin',
      proc   => sub {
        $_[0]{original} ||= undef;
        $_[0]{released} = formatdate($_[0]{released});
        $_[0]{patch}    = $_[0]{patch}    =~ /^t/ ? TRUE : FALSE;
        $_[0]{freeware} = $_[0]{freeware} =~ /^t/ ? TRUE : FALSE;
        $_[0]{doujin}   = $_[0]{doujin}   =~ /^t/ ? TRUE : FALSE;
      },
      fetch => [[ 'latest', 'SELECT rid, lang FROM releases_lang WHERE rid IN(%s)',
        sub { my($n, $r) = @_;
          for my $i (@$n) {
            $i->{languages} = [ map $i->{latest} == $_->{rid} ? $_->{lang} : (), @$r ];
          }
        },
      ]],
    },
    details => {
      select => 'rr.website, rr.notes, rr.minage, rr.gtin, rr.catalog',
      proc   => sub {
        $_[0]{website}  ||= undef;
        $_[0]{notes}    ||= undef;
        $_[0]{minage}   = $_[0]{minage} < 0 ? undef : $_[0]{minage}*1;
        $_[0]{gtin}     ||= undef;
        $_[0]{catalog}  ||= undef;
      },
      fetch => [
        [ 'latest', 'SELECT rid, platform FROM releases_platforms WHERE rid IN(%s)',
          sub { my($n, $r) = @_;
            for my $i (@$n) {
               $i->{platforms} = [ map $i->{latest} == $_->{rid} ? $_->{platform} : (), @$r ];
            }
          } ],
        [ 'latest', 'SELECT rid, medium, qty FROM releases_media WHERE rid IN(%s)',
          sub { my($n, $r) = @_;
            for my $i (@$n) {
              $i->{media} = [ grep $i->{latest} == $_->{rid}, @$r ];
            }
            for (@$r) {
              delete $_->{rid};
              $_->{qty} = $VNDB::S{media}{$_->{medium}} ? $_->{qty}*1 : undef;
            }
          } ],
      ]
    },
    vn => {
      fetch => [[ 'latest', 'SELECT rv.rid, v.id, vr.title, vr.original FROM releases_vn rv JOIN vn v ON v.id = rv.vid
                    JOIN vn_rev vr ON vr.id = v.latest WHERE NOT v.hidden AND rv.rid IN(%s)',
        sub { my($n, $r) = @_;
          for my $i (@$n) {
            $i->{vn} = [ grep $i->{latest} == $_->{rid}, @$r ];
          }
          for (@$r) {
            $_->{id}*=1;
            $_->{original} ||= undef;
            delete $_->{rid};
          }
        }
      ]],
    },
    producers => {
      fetch => [[ 'latest', 'SELECT rp.rid, rp.developer, rp.publisher, p.id, pr.type, pr.name, pr.original FROM releases_producers rp
                    JOIN producers p ON p.id = rp.pid JOIN producers_rev pr ON pr.id = p.latest WHERE NOT p.hidden AND rp.rid IN(%s)',
        sub { my($n, $r) = @_;
          for my $i (@$n) {
            $i->{producers} = [ grep $i->{latest} == $_->{rid}, @$r ];
          }
          for (@$r) {
            $_->{id}*=1;
            $_->{original}  ||= undef;
            $_->{developer} = $_->{developer} =~ /^t/ ? TRUE : FALSE;
            $_->{publisher} = $_->{publisher} =~ /^t/ ? TRUE : FALSE;
            delete $_->{rid};
          }
        }
      ]],
    }
  },
  filters => {
    id => [
      [ 'int' => 'r.id :op: :value:', {qw|= =  != <>  > >  >= >=  < <  <= <=|}, range => [1,1e6] ],
      [ inta  => 'r.id :op:(:value:)', {'=' => 'IN', '!=' => 'NOT IN'}, join => ',', range => [1,1e6] ],
    ],
    vn => [
      [ 'int' => 'rr.id IN(SELECT rv.rid FROM releases_vn rv WHERE rv.vid = :value:)', {'=',1}, range => [1,1e6] ],
    ],
    producer => [
      [ 'int' => 'rr.id IN(SELECT rp.rid FROM releases_producers rp WHERE rp.pid = :value:)', {'=',1}, range => [1,1e6] ],
    ],
    title => [
      [ str   => 'rr.title :op: :value:', {qw|= =  != <>|} ],
      [ str   => 'rr.title ILIKE :value:', {'~',1}, process => \'like' ],
    ],
    original => [
      [ undef,   "rr.original :op: ''", {qw|= =  != <>|} ],
      [ str   => 'rr.original :op: :value:', {qw|= =  != <>|} ],
      [ str   => 'rr.original ILIKE :value:', {'~',1}, process => \'like' ]
    ],
    released => [
      [ undef,   'rr.released :op: 0', {qw|= =  != <>|} ],
      [ str   => 'rr.released :op: :value:', {qw|= =  != <>  > >  < <  <= <=  >= >=|}, process => \&parsedate ],
    ],
    patch    => [ [ bool => 'rr.patch = :value:',    {'=',1} ] ],
    freeware => [ [ bool => 'rr.freeware = :value:', {'=',1} ] ],
    doujin   => [ [ bool => 'rr.doujin = :value:',   {'=',1} ] ],
    type => [
      [ str   => 'rr.type :op: :value:', {qw|= =  != <>|},
        process => sub { !grep($_ eq $_[0], @{$VNDB::S{release_types}}) ? \'No such release type' : $_[0] } ],
    ],
    gtin => [
      [ 'int' => 'rr.gtin :op: :value:', {qw|= =  != <>|}, process => sub { length($_[0]) > 14 ? \'Too long GTIN code' : $_[0] } ],
    ],
    catalog => [
      [ str   => 'rr.catalog :op: :value:', {qw|= =  != <>|} ],
    ],
    languages => [
      [ str   => 'rr.id :op:(SELECT rl.rid FROM releases_lang rl WHERE rl.lang = :value:)', {'=' => 'IN', '!=' => 'NOT IN'}, process => \'lang' ],
      [ stra  => 'rr.id :op:(SELECT rl.rid FROM releases_lang rl WHERE rl.lang IN(:value:))', {'=' => 'IN', '!=' => 'NOT IN'}, join => ',', process => \'lang' ],
    ],
  },
);

my %GET_PRODUCER = (
  sql     => 'SELECT %s FROM producers p JOIN producers_rev pr ON p.latest = pr.id WHERE NOT p.hidden AND (%s) %s',
  select  => 'p.id, p.latest',
  proc    => sub {
    delete $_[0]{latest};
    $_[0]{id} *= 1
  },
  sortdef => 'id',
  sorts   => {
    id => 'p.id %s',
    name => 'pr.name %s',
  },
  flags  => {
    basic => {
      select => 'pr.type, pr.name, pr.original, pr.lang AS language',
      proc => sub {
        $_[0]{original}    ||= undef;
      },
    },
    details => {
      select => 'pr.website, pr.l_wp, pr.desc AS description, pr.alias AS aliases',
      proc => sub {
        $_[0]{description} ||= undef;
        $_[0]{aliases}     ||= undef;
        $_[0]{links} = {
          homepage  => delete($_[0]{website})||undef,
          wikipedia => delete $_[0]{l_wp},
        };
      },
    },
    relations => {
      fetch => [[ 'latest', 'SELECT pl.pid1, p.id, pl.relation, pr.name, pr.original FROM producers_relations pl
                    JOIN producers p ON p.id = pl.pid2 JOIN producers_rev pr ON pr.id = p.latest WHERE pl.pid1 IN(%s) AND NOT p.hidden',
        sub { my($n, $r) = @_;
          for my $i (@$n) {
            $i->{relations} = [ grep $i->{latest} == $_->{pid1}, @$r ];
          }
          for (@$r) {
            $_->{id}*=1;
            $_->{original} ||= undef;
            delete $_->{pid1};
          }
        },
      ]],
    },
  },
  filters => {
    id => [
      [ 'int' => 'p.id :op: :value:', {qw|= =  != <>  > >  < <  <= <=  >= >=|}, range => [1,1e6] ],
      [ inta  => 'p.id :op:(:value:)', {'=' => 'IN', '!= ' => 'NOT IN'}, join => ',', range => [1,1e6] ],
    ],
    name => [
      [ str   => 'pr.name :op: :value:', {qw|= =  != <>|} ],
      [ str   => 'pr.name ILIKE :value:', {'~',1}, process => \'like' ],
    ],
    original => [
      [ undef,   "pr.original :op: ''", {qw|= =  != <>|} ],
      [ str   => 'pr.original :op: :value:', {qw|= =  != <>|} ],
      [ str   => 'pr.original ILIKE :value:', {'~',1}, process => \'like' ]
    ],
    type => [
      [ str   => 'pr.type :op: :value:', {qw|= =  != <>|},
        process => sub { !grep($_ eq $_[0], @{$VNDB::S{producer_types}}) ? \'No such producer type' : $_[0] } ],
    ],
    language => [
      [ str   => 'pr.lang :op: :value:', {qw|= =  != <>|}, process => \'lang' ],
      [ stra  => 'pr.lang :op:(:value:)', {'=' => 'IN', '!=' => 'NOT IN'}, join => ',', process => \'lang' ],
    ],
    search => [
      [ str   => '(pr.name ILIKE :value: OR pr.original ILIKE :value: OR pr.alias ILIKE :value:)', {'~',1}, process => \'like' ],
    ],
  },
);

my %GET_CHARACTER = (
  sql     => 'SELECT %s FROM chars c JOIN chars_rev cr ON c.latest = cr.id WHERE NOT c.hidden AND (%s) %s',
  select  => 'c.id, c.latest',
  proc    => sub {
    delete $_[0]{latest};
    $_[0]{id} *= 1
  },
  sortdef => 'id',
  sorts   => {
    id => 'c.id %s',
    name => 'cr.name %s',
  },
  flags  => {
    basic => {
      select => 'cr.name, cr.original, cr.gender, cr.bloodt, cr.b_day, cr.b_month',
      proc => sub {
        $_[0]{original} ||= undef;
        $_[0]{gender}   = undef if $_[0]{gender} eq 'unknown';
        $_[0]{bloodt}   = undef if $_[0]{bloodt} eq 'unknown';
        $_[0]{birthday} = [ delete($_[0]{b_day})*1||undef, delete($_[0]{b_month})*1||undef ];
      },
    },
    details => {
      select => 'cr.alias AS aliases, cr.image, cr."desc" AS description',
      proc => sub {
        $_[0]{aliases}     ||= undef;
        $_[0]{image}       = $_[0]{image} ? sprintf '%s/ch/%02d/%d.jpg', $VNDB::S{url_static}, $_[0]{image}%100, $_[0]{image} : undef;
        $_[0]{description} ||= undef;
      },
    },
    meas => {
      select => 'cr.s_bust AS bust, cr.s_waist AS waist, cr.s_hip AS hip, cr.height, cr.weight',
      proc => sub {
        $_[0]{$_} = $_[0]{$_} ? $_[0]{$_}*1 : undef for(qw|bust waist hip height weight|);
      },
    },
    traits => {
      fetch => [[ 'latest', 'SELECT cid, tid, spoil FROM chars_traits WHERE cid IN(%s)',
        sub { my($n, $r) = @_;
          for my $i (@$n) {
            $i->{traits} = [ map [ $_->{tid}*1, $_->{spoil}*1 ], grep $i->{latest} == $_->{cid}, @$r ];
          }
        },
      ]],
    },
  },
  filters => {
    id => [
      [ 'int' => 'c.id :op: :value:', {qw|= =  != <>  > >  < <  <= <=  >= >=|}, range => [1,1e6] ],
      [ inta  => 'c.id :op:(:value:)', {'=' => 'IN', '!= ' => 'NOT IN'}, range => [1,1e6], join => ',' ],
    ],
    name => [
      [ str   => 'cr.name :op: :value:', {qw|= =  != <>|} ],
      [ str   => 'cr.name ILIKE :value:', {'~',1}, process => \'like' ],
    ],
    original => [
      [ undef,   "cr.original :op: ''", {qw|= =  != <>|} ],
      [ str   => 'cr.original :op: :value:', {qw|= =  != <>|} ],
      [ str   => 'cr.original ILIKE :value:', {'~',1}, process => \'like' ]
    ],
    search => [
      [ str   => '(cr.name ILIKE :value: OR cr.original ILIKE :value: OR cr.alias ILIKE :value:)', {'~',1}, process => \'like' ],
    ],
    vn => [
      [ 'int' => 'cr.id IN(SELECT cv.cid FROM chars_vns cv WHERE cv.vid = :value:)', {'=',1}, range => [1,1e6] ],
    ],
  },
);


# the uid filter for votelist/vnlist/wishlist. Needs special care to handle the 'uid=0' case.
my $UID_FILTER =
  [ 'int' => 'uid :op: :value:', {qw|= =|}, range => [0,1e6], process =>
      sub { my($uid, $c) = @_; !$uid && !$c->{uid} ? \'Not logged in.' : $uid || $c->{uid} } ];

my %GET_VOTELIST = (
  islist  => 1,
  sql     => "SELECT %s FROM votes v WHERE (%s) AND NOT EXISTS(SELECT 1 FROM users_prefs WHERE uid = v.uid AND key = 'hide_list') %s",
  sqluser => q{SELECT %1$s FROM votes v WHERE (%2$s) AND (uid = %4$d OR NOT EXISTS(SELECT 1 FROM users_prefs WHERE uid = v.uid AND key = 'hide_list')) %3$s},
  select  => "vid as vn, vote, extract('epoch' from date) AS added",
  proc    => sub {
    $_[0]{vn}*=1;
    $_[0]{vote}*=1;
    $_[0]{added} = int $_[0]{added};
  },
  sortdef => 'vn',
  sorts   => { vn => 'vid %s' },
  flags   => { basic => {} },
  filters => { uid => [ $UID_FILTER ] }
);

my %GET_VNLIST = (
  islist  => 1,
  sql     => "SELECT %s FROM vnlists v WHERE (%s) AND NOT EXISTS(SELECT 1 FROM users_prefs WHERE uid = v.uid AND key = 'hide_list') %s",
  sqluser => q{SELECT %1$s FROM vnlists v WHERE (%2$s) AND (uid = %4$d OR NOT EXISTS(SELECT 1 FROM users_prefs WHERE uid = v.uid AND key = 'hide_list')) %3$s},
  select  => "vid as vn, status, extract('epoch' from added) AS added, notes",
  proc    => sub {
    $_[0]{vn}*=1;
    $_[0]{status}*=1;
    $_[0]{added} = int $_[0]{added};
    $_[0]{notes} ||= undef;
  },
  sortdef => 'vn',
  sorts   => { vn => 'vid %s' },
  flags   => { basic => {} },
  filters => { uid => [ $UID_FILTER ] }
);

my %GET_WISHLIST = (
  islist  => 1,
  sql     => "SELECT %s FROM wlists w WHERE (%s) AND NOT EXISTS(SELECT 1 FROM users_prefs WHERE uid = w.uid AND key = 'hide_list') %s",
  sqluser => q{SELECT %1$s FROM wlists w WHERE (%2$s) AND (uid = %4$d OR NOT EXISTS(SELECT 1 FROM users_prefs WHERE uid = w.uid AND key = 'hide_list')) %3$s},
  select  => "vid AS vn, wstat AS priority, extract('epoch' from added) AS added",
  proc    => sub {
    $_[0]{vn}*=1;
    $_[0]{priority}*=1;
    $_[0]{added} = int $_[0]{added};
  },
  sortdef => 'vn',
  sorts   => { vn => 'vid %s' },
  flags   => { basic => {} },
  filters => { uid => [ $UID_FILTER ] }
);


my %GET = (
  vn        => \%GET_VN,
  release   => \%GET_RELEASE,
  producer  => \%GET_PRODUCER,
  character => \%GET_CHARACTER,
  votelist  => \%GET_VOTELIST,
  vnlist    => \%GET_VNLIST,
  wishlist  => \%GET_WISHLIST,
);


sub get {
  my($c, @arg) = @_;

  return cerr $c, parse => 'Invalid arguments to get command' if @arg < 3 || @arg > 4
    || ref($arg[0]) || ref($arg[1]) || ref($arg[2]) ne 'POE::Filter::VNDBAPI::filter'
    || exists($arg[3]) && ref($arg[3]) ne 'HASH';
  my $opt = $arg[3] || {};
  return cerr $c, badarg => 'Invalid argument for the "page" option', field => 'page'
    if defined($opt->{page}) && (ref($opt->{page}) || $opt->{page} !~ /^\d+$/ || $opt->{page} < 1 || $opt->{page} > 1e3);
  return cerr $c, badarg => '"reverse" option must be boolean', field => 'reverse'
    if defined($opt->{reverse}) && !JSON::XS::is_bool($opt->{reverse});

  my $type = $GET{$arg[0]};
  return cerr $c, 'gettype', "Unknown get type: '$arg[0]'" if !$type;
  return cerr $c, badarg => 'Invalid argument for the "results" option', field => 'results'
    if defined($opt->{results}) && (ref($opt->{results}) || $opt->{results} !~ /^\d+$/ || $opt->{results} < 1
        || $opt->{results} > ($type->{islist} ? $O{max_results_lists} : $O{max_results}));
  return cerr $c, badarg => 'Unknown sort field', field => 'sort'
    if defined($opt->{sort}) && (ref($opt->{sort}) || !$type->{sorts}{$opt->{sort}});

  my @flags = split /,/, $arg[1];
  return cerr $c, getinfo => 'No info flags specified' if !@flags;
  return cerr $c, getinfo => "Unknown info flag '$_'", flag => $_
    for (grep !$type->{flags}{$_}, @flags);

  $opt->{page} = $opt->{page}||1;
  $opt->{results} = $opt->{results}||$O{default_results};
  $opt->{sort} ||= $type->{sortdef};
  $opt->{reverse} = defined($opt->{reverse}) && $opt->{reverse};

  get_mainsql($c, $type, {type => $arg[0], info => \@flags, filters => $arg[2], opt => $opt});
}


sub get_filters {
  my($c, $p, $t, $field, $op, $value) = ($_[1], $_[2], $_[3], @{$_[0]});
  my %e = ( field => $field, op => $op, value => $value );

  # get the field that matches
  $t = $t->{$field};
  return cerr $c, filter => "Unknown field '$field'", %e if !$t;

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
      $v = $o{process}->($v, $c);
      return cerr $c, filter => $$v, %e if ref($v) eq 'SCALAR';
    } elsif(${$o{process}} eq 'like') {
      y/%//;
      $v = "%$v%";
    } elsif(${$o{process}} eq 'lang') {
      return cerr $c, filter => 'Invalid language code', %e if !grep $v eq $_, @{$VNDB::S{languages}};
    } elsif(${$o{process}} eq 'plat') {
      return cerr $c, filter => 'Invalid platform code', %e if !grep $v eq $_, @{$VNDB::S{platforms}};
    }
  }

  # type=bool and no processing done? convert bool to what DBD::Pg wants
  $values[0] = $values[0] ? 1 : 0 if $type eq 'bool' && !$o{process};

  # Ensure that integers stay within their range
  for($o{range} ? @values : ()) {
    return cerr $c, filter => 'Integer out of range', %e if $_ < $o{range}[0] || $_ > $o{range}[1];
  }

  # type=str, int and bool are now quite simple
  if(!ref $value) {
    $sql =~ s/:value:/push @$p, $values[0]; '$'.scalar @$p/eg;
    return $sql;
  }

  # and do some processing for type=stra and type=inta
  my @parameters;
  if($o{serialize}) {
    for(@values) {
      my $v = $o{serialize};
      $v =~ s/:op:/$ops->{$op}/g;
      $v =~ s/:value:/push @$p, $_; '$'.scalar @$p/eg;
      $_ = $v;
    }
  } else {
    for(@values) {
      push @$p, $_;
      $_ = '$'.scalar @$p;
    }
  }
  my $joined = join defined $o{join} ? $o{join} : '', @values;
  $sql =~ s/:value:/$joined/eg;
  return $sql;
}


sub get_mainsql {
  my($c, $type, $get) = @_;

  my $select = join ', ',
    $type->{select} ? $type->{select} : (),
    map $type->{flags}{$_}{select} ? $type->{flags}{$_}{select} : (), @{$get->{info}};

  my @placeholders;
  my $where = encode_filters $get->{filters}, \&get_filters, $c, \@placeholders, $type->{filters};
  return if !$where;

  my $col = $type->{sorts}{ $get->{opt}{sort} };
  my $last = sprintf 'ORDER BY %s LIMIT %d OFFSET %d',
    sprintf($col, $get->{opt}{reverse} ? 'DESC' : 'ASC'),
    $get->{opt}{results}+1, $get->{opt}{results}*($get->{opt}{page}-1);

  my $sql = $type->{sql};
  return cerr $c, needlogin => 'Not logged in as a user' if !$sql && !$c->{uid};
  $sql = $type->{sqluser} if $c->{uid} && $type->{sqluser};

  cpg $c, sprintf($sql, $select, $where, $last, $c->{uid}), \@placeholders, sub {
    my @res = $_[0]->rowsAsHashes;
    $get->{more} = pop(@res)&&1 if @res > $get->{opt}{results};
    $get->{list} = \@res;

    get_fetch($c, $type, $get);
  };
}


sub get_fetch {
  my($c, $type, $get) = @_;

  my @need = map { my $f = $type->{flags}{$_}{fetch}; $f ? @$f : () } @{$get->{info}};
  return get_final($c, $type, $get) if !@need || !@{$get->{list}};

  # Turn into a hash for easy self-deletion
  my %need = map +($_, $need[$_]), 0..$#need;

  for my $n (keys %need) {
    my @ids = map $_->{ $need{$n}[0] }, @{$get->{list}};
    my $ids = join ',', map '$'.$_, 1..@ids;
    cpg $c, sprintf($need{$n}[1], $ids), \@ids, sub {
      $get->{fetched}{$n} = [ $need{$n}[2], [$_[0]->rowsAsHashes] ];
      delete $need{$n};
      get_final($c, $type, $get) if !keys %need;
    };
  }
}


sub get_final {
  my($c, $type, $get) = @_;

  # Run process callbacks (fetchprocs first, so that they have access to fields that may get deleted in later procs)
  for my $n (values %{$get->{fetched}}) {
    $n->[0]->($get->{list}, $n->[1]);
  }

  for my $p (
    $type->{proc} || (),
    map $type->{flags}{$_}{proc} || (), @{$get->{info}}
  ) {
    $p->($_) for @{$get->{list}};
  }

  my $num = @{$get->{list}};
  cres $c, [ results => { num => $num , more => $get->{more} ? TRUE : FALSE, items => $get->{list} }],
    'R:%2d  get %s %s %s {%s %s, page %d}', $num, $get->{type}, join(',', @{$get->{info}}), encode_filters($get->{filters}),
    $get->{opt}{sort}, $get->{opt}{reverse}?'desc':'asc', $get->{opt}{page};
}



sub set {
  my($c, @arg) = @_;

  my %types = (
    votelist => \&set_votelist,
    vnlist   => \&set_vnlist,
    wishlist => \&set_wishlist,
  );

  return cerr $c, parse => 'Invalid arguments to set command' if @arg < 2 || @arg > 3 || ref($arg[0])
    || ref($arg[1]) || $arg[1] !~ /^\d+$/ || $arg[1] < 1 || $arg[1] > 1e6 || (defined($arg[2]) && ref($arg[2]) ne 'HASH');
  return cerr $c, 'settype', "Unknown set type: '$arg[0]'" if !$types{$arg[0]};
  return cerr $c, needlogin => 'Not logged in as a user' if !$c->{uid};

  my %obj = (
    c    => $c,
    type => $arg[0],
    id   => $arg[1],
    opt  => $arg[2]
  );
  $types{$obj{type}}->($c, \%obj);
}


# Wrapper around cpg that calls cres for a set command. First argument is the $obj created in set().
sub setpg {
  my($obj, $sql, $a) = @_;

  cpg $obj->{c}, $sql, $a, sub {
    my $args = $obj->{opt} ? JSON::XS->new->encode($obj->{opt}) : 'delete';
    cres $obj->{c}, ['ok'], 'R:%2d  set %s %d %s', $_[0]->cmdRows(), $obj->{type}, $obj->{id}, $args;
  };
}


sub set_votelist {
  my($c, $obj) = @_;

  return setpg $obj, 'DELETE FROM votes WHERE uid = $1 AND vid = $2',
    [ $c->{uid}, $obj->{id} ] if !$obj->{opt};

  my($ev, $vv) = (exists($obj->{opt}{vote}), $obj->{opt}{vote});
  return cerr $c, missing => 'No vote given', field => 'vote' if !$ev;
  return cerr $c, badarg => 'Invalid vote', field => 'vote' if ref($vv) || !defined($vv) || $vv !~ /^\d+$/ || $vv < 10 || $vv > 100;

  setpg $obj, 'WITH upsert AS (UPDATE votes SET vote = $1 WHERE uid = $2 AND vid = $3 RETURNING vid)
      INSERT INTO votes (vote, uid, vid) SELECT $1, $2, $3 WHERE EXISTS(SELECT 1 FROM vn v WHERE v.id = $3) AND NOT EXISTS(SELECT 1 FROM upsert)',
    [ $vv, $c->{uid}, $obj->{id} ];
}


sub set_vnlist {
  my($c, $obj) = @_;

  return setpg $obj, 'DELETE FROM vnlists WHERE uid = $1 AND vid = $2',
    [ $c->{uid}, $obj->{id} ] if !$obj->{opt};

  my($es, $en, $vs, $vn) = (exists($obj->{opt}{status}), exists($obj->{opt}{notes}), $obj->{opt}{status}, $obj->{opt}{notes});
  return cerr $c, missing => 'No status or notes given', field => 'status,notes' if !$es && !$en;
  return cerr $c, badarg => 'Invalid status', field => 'status' if $es && (!defined($vs) || ref($vs) || $vs !~ /^[0-4]$/);
  return cerr $c, badarg => 'Invalid notes', field => 'notes' if $en && (ref($vn) || (defined($vn) && $vn =~ /[\r\n]/));

  $vs ||= 0;
  $vn ||= '';

  my $set = join ', ', $es ? 'status = $3' : (), $en ? 'notes = $4' : ();
  setpg $obj, 'WITH upsert AS (UPDATE vnlists SET '.$set.' WHERE uid = $1 AND vid = $2 RETURNING vid)
      INSERT INTO vnlists (uid, vid, status, notes) SELECT $1, $2, $3, $4 WHERE EXISTS(SELECT 1 FROM vn v WHERE v.id = $2) AND NOT EXISTS(SELECT 1 FROM upsert)',
    [ $c->{uid}, $obj->{id}, $vs, $vn ];
}


sub set_wishlist {
  my($c, $obj) = @_;

  return setpg $obj, 'DELETE FROM wlists WHERE uid = $1 AND vid = $2',
    [ $c->{uid}, $obj->{id} ] if !$obj->{opt};

  my($ep, $vp) = (exists($obj->{opt}{priority}), $obj->{opt}{priority});
  return cerr $c, missing => 'No priority given', field => 'priority' if !$ep;
  return cerr $c, badarg => 'Invalid priority', field => 'priority' if ref($vp) || !defined($vp) || $vp !~ /^[0-3]$/;

  setpg $obj, 'WITH upsert AS (UPDATE wlists SET wstat = $1 WHERE uid = $2 AND vid = $3 RETURNING vid)
      INSERT INTO wlists (wstat, uid, vid) SELECT $1, $2, $3 WHERE EXISTS(SELECT 1 FROM vn v WHERE v.id = $3) AND NOT EXISTS(SELECT 1 FROM upsert)',
    [ $vp, $c->{uid}, $obj->{id} ];
}

1;
