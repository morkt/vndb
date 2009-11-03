# Implements a POE::Filter for the VNDB API, and includes basic error checking
#
# Currently recognised commands and their mapping between Perl and strings
# (this is just a simple overview, actual implementation is more advanced)
#
# C: login <json-object>
#    [ 'login', {object} ]
#
# C: get <type> <info> <filters>
#    [ 'get', <type>, <info>[ split ',', $2 ], [ filters ] ]
#    <type> must match /[a-z\/_]+/
#    <info> as string: /[a-z_]+(,[a-z_]+)*/, in perl: [ /[a-z_]+/, .. ]
#
# S: ok
#    [ 'ok' ]
#
# S: results <json-object>
#    [ 'results', {object} ]
#
# S: error <json-object>
#    [ 'error', {object} ]
#
# <filters>:
#   string: ((<field> <op> <json-value>) <bool-op> (<field> <op> <json-value> ))
#   perl:   [ [ 'field', 'op', value ], 'bool-op', [ 'field', 'op', value ] ]
# <field> must match /[a-z_]+/
# <op> must be one of =, !=, <, >, >=, <= or ~
# whitespace around fields/ops/json-values/bool-ops are ignored.
#
# When type='server', put() will accept the objects marked by 'S' and get() will accept the strings marked by 'C'
# When type='client', put() will accept the objects marked by 'C' and get() will accept the strings marked by 'S'
#
# When invalid data is given to put(), ...don't do that, seriously.
# When invalid data is given to get(), it will return the following arrayref:
#   [ undef, { id => 'parse', msg => 'error message' } ]
# When type='server', a valid error response can be sent back simply by
#   changing the undef to 'error' and forwarding the arrayref to put()
#
# See the POE::Filter documentation for information on how to use this module.
# This module supports filter switching (which will be required to implement
#   gzip compression or backwards compatibility on API changes)
# Note that this module is also suitable for use outside of the POE framework.


package POE::Filter::VNDBAPI;

use strict;
use warnings;
use JSON::XS;
use Encode 'decode_utf8', 'encode_utf8';
use Exporter 'import';

our @EXPORT_OK = qw|decode_filters encode_filters|;


my $EOT          = "\x04"; # End Of Transmission, this string is searched in the binary data using index()
my $WS           = qr/[\x20\x09\x0a\x0d]/;       # witespace as defined by RFC4627
my $GET_TYPE     = qr/(?:[a-z\/_]+)/;            # get <type>
my $GET_INFO     = qr/(?:[a-z_]+(?:,[a-z_]+)*)/; # get <info>
my $FILTER_FIELD = qr/(?:[a-z_]+)/;              # <field> in the filters
my $FILTER_OP    = qr/(?:=|!=|<|>|>=|<=|~)/;     # <op> in the filters
my $FILTER_BOOL  = qr/(?:and|or)/;               # <boolean-op> in the filters


sub new {
  my($class, %o) = @_;
  my $type = ($o{type}||'') eq 'server' ? 'server' : 'client';
  return bless {
    type => $type,
    buffer => ''
  }, $class;
}


sub clone {
  my $self = shift;
  return bless {
    type => $self->{type},
  }, ref $self;
}


sub get {
  my ($self, $data) = @_;
  my @r;

  $self->get_one_start($data);
  my $d;
  do {
    $d = $self->get_one();
    push @r, @$d if @$d;
  } while(@$d);

  return \@r;
}


sub get_one_start {
  my($self, $data) = @_;
  $self->{buffer} .= join '', @$data;
}


sub get_pending {
  my $self = shift;
  return $self->{buffer} ne '' ? [ $self->{buffer} ] : undef;
}


sub _err($) { [ [ undef, { id => 'parse', msg => $_[0] } ] ] };

sub get_one {
  my $self = shift;
  # look for EOT
  my $end = index $self->{buffer}, $EOT;
  return [] if $end < 0;
  my $str = substr $self->{buffer}, 0, $end;
  $self->{buffer} = substr $self->{buffer}, $end+1;

  # $str now contains our request/response encoded in UTF8, time to decode
  $str = eval { decode_utf8($str, Encode::FB_CROAK); };
  return _err "Encoding error: $@" if !defined $str;

  # C: login
  # S: error, results
  if($str =~ /^$WS*(login|error|results)$WS+(.+)$/s && ($self->{type} eq 'server' && $1 eq 'login' || $self->{type} eq 'client' && $1 ne 'login')) {
    my($cmd, $json) = ($1, $2);
    $json = eval { JSON::XS->new->decode($json) };
    if(!defined $json) {
      my $err = $@;
      $err =~ s/,? at .+ line [0-9]+[\.\r\n ]*$//;
      return _err "JSON-decode: $err" if !defined $json;
    }
    return _err qq|"$cmd" command requires a JSON object| if ref($json) ne 'HASH';
    return [[ $cmd, $json ]];
  }

  # C: get
  if($self->{type} eq 'server' && $str =~ /^$WS*get$WS+($GET_TYPE)$WS+($GET_INFO)$WS+(.+)$/s) {
    my($type, $info) = ($1, $2);
    my($filters, $rest) = decode_filters($3);
    return _err $filters if !ref $filters;
    return _err 'Leading characters' if length $rest && $rest !~ /^$WS+$/;
    return [[ 'get', $type, [ split /,/, $info ], $filters ]];
  }

  # S: ok
  if($self->{type} eq 'client' && $str =~ /^$WS*ok$WS*$/) {
    return [[ 'ok' ]];
  }

  # if we're here, we've received something strange
  return _err 'Invalid command or argument';
}


# arguments come from the application and are assumed to be correct,
# passing incorrect arguments will result in undefined behaviour.
sub put {
  my($self, $cmds) = @_;
  my @r;
  for my $p (@$cmds) {
    my $cmd = shift @$p;

    # C: login
    push @r, 'login '.JSON::XS->new->encode($p->[0])
      if $self->{type} eq 'client' && $cmd eq 'login';

    # C: get
    push @r, sprintf 'get %s %s %s', $p->[0], join(',',@{$p->[1]}), encode_filters($p->[2])
      if $self->{type} eq 'client' && $cmd eq 'get';

    # S: ok
    push @r, 'ok'
      if $self->{type} eq 'server' && $cmd eq 'ok';

    # S: error, results
    push @r, "$cmd ".JSON::XS->new->encode($p->[0])
      if $self->{type} eq 'server' && ($cmd eq 'error' || $cmd eq 'results');
  }
  # the $EOT can also be passed through encode_utf8(), the result is the same.
  return [ map encode_utf8($_).$EOT, @r ];
}


# decodes "<field> <op> <value>", and returns the arrayref and the remaining (unparsed) string after <value>
sub decode_filter_expr {
  my $str = shift;
  return ('Invalid filter expression') if $str !~ /^$WS*($FILTER_FIELD)$WS*($FILTER_OP)([^=].*)$/s;
  my($field, $op, $val) = ($1, $2, $3);
  my($value, $chars) = eval { JSON::XS->new->allow_nonref->decode_prefix($val) };
  if(!defined $chars) {
    my $err = $@;
    $err =~ s/,? at .+ line [0-9]+[\.\r\n ]*$//;
    return ("Invalid JSON value in filter expression: $err");
  }
  $str = substr $val, $chars;
  return ([ $field, $op, $value ], $str);
}


sub decode_filters {
  my($str, $sub) = @_;
  $sub ||= 0;
  my @r;
  return ('Too many nested filter expressions') if $sub > 10;
  return ('Filter must start with a (') if !$sub && $str !~ s/^$WS*\(//;
  while(length $str && $str !~ /^$WS*\)/) {
    my $ret;
    $str =~ s/^$WS+//;
    # AND/OR
    if(@r%2 == 1 && $str =~ s/^($FILTER_BOOL)//) {
      push @r, $1;
      next;
    }
    # sub-expression ()
    if($str =~ s/^\(//) {
      ($ret, $str) = decode_filters($str, $sub+1);
      return ($ret) if !ref $ret;
      return ('Unterminated ( in filter expression') if $str !~ s/^$WS*\)//;
      push @r, $ret;
      next;
    }
    # <expr>
    ($ret, $str) = decode_filter_expr($str);
    return ($ret) if !ref $ret;
    push @r, $ret;
  }
  return ('Unterminated ( in filter expression') if !$sub && $str !~ s/^$WS*\)//;
  # validate what we have parsed
  return ('Empty filter expression') if !@r;
  return ('Invalid filter expression') if @r % 2 != 1 || grep ref $r[$_] eq ($_%2 ? 'ARRAY' : ''), 0..$#r;
  return (@r == 1 ? @r : \@r, $str);
}


# arguments: arrayref returned by decode_filters and an optional serialize function,
#  this function is called for earch filter expression, in the same order the expressions
#  are serialized. Should return the serialized string. This can be used to easily
#  convert the filters into SQL.
sub encode_filters {
  my($fil, $func, @extra) = @_;
  return '('.join('', map {
    if(!ref $_) { # and/or
      " $_ "
    } elsif(ref $_->[0]) { # sub expression
      my $v = encode_filters($_, $func, @extra);
      return undef if !defined $v;
      $v
    } else { # expression
      my $v = $func ? $func->($_, @extra) : "$_->[0] $_->[1] ".JSON::XS->new->allow_nonref->encode($_->[2]);
      return undef if !defined $v;
      $v
    }
  } ref($fil->[0]) ? @$fil : $fil).')';
}


1;


__END__

# and here is a relatively comprehensive test suite for the above implementation of decode_filter()

use lib '/home/yorhel/dev/vndb/lib';
use POE::Filter::VNDBAPI 'decode_filters';
require Test::More;
use utf8;
my @tests = (
  # these should all parse fine
  [q|(test = 1)|,                         ['test', '=', '1'], ''],
  [q|((vn_name ~ "20") and length > 2)|,  [['vn_name', '~', '20'], 'and', ['length', '>', 2]], ''],
  [q|(padding < ["val1", 4]) padding|,    ['padding', '<', ['val1', 4]], ' padding' ],
  [q|(s=nulland_f<3)()|,                  [['s', '=', undef], 'and', ['_f', '<', 3]], '()'],
  [qq|\r(p\r\t=\n \t\r3\n\n)|,            ['p', '=', 3], ''],
  [q|(s=4and((m="3"ort="str")or_g_={}))|, [['s','=',4],'and',[[['m','=','3'],'or',['t','=','str']],'or',['_g_','=',{}]]], ''],
  [q|(z = ")\"){})")|,                    ['z', '=', ')"){})'], '' ],
  [q| (name ~ "月姫") |,                  ['name', '~', '月姫'], ' ' ],
  [q| (id >= 2) |,                        ['id', '>=', 2], ' '],
  [q|(original = null)|,                  ['original', '=', undef],  ''],
  # and these should fail
  [q|(name = true|],
  [q|(and (f=1) or g=1)|],
  [q|name = null|],
  [q|(invalid-field > 6)|],
  [q|(invalid ~ "JSON)|],
  [q|()|],
  [q|(v = 2 and ())|],
);
import Test::More tests => ($#tests+1)*2;
for (@tests) {
  my @ret = decode_filters($_->[0]);
  if($_->[1]) {
    is_deeply($ret[0], $_->[1]);
    is($ret[1], $_->[2]);
  } else {
    ok(ref $ret[0] eq '', "nonref: $_->[0]");
    is($ret[1], undef, "rest: $_->[0]");
  }
}


