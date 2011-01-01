
package VNDB::Func;

use strict;
use warnings;
use YAWF ':html';
use Exporter 'import';
use POSIX 'strftime', 'ceil', 'floor';
use VNDBUtil;
our @EXPORT = (@VNDBUtil::EXPORT, qw| clearfloat cssicon tagscore mt minage fil_parse fil_serialize |);


# three ways to represent the same information
our $fil_escape = '_ !"#$%&\'()*+,-./:;<=>?@[\]^`{}~';
our @fil_escape = split //, $fil_escape;
our %fil_escape = map +($fil_escape[$_], sprintf '%02d', $_), 0..$#fil_escape;


# Clears a float, to make sure boxes always have the correct height
sub clearfloat {
  div class => 'clearfloat', '';
}


# Draws a CSS icon, arguments: class, title
sub cssicon {
  acronym class => "icons $_[0]", title => $_[1];
   lit '&nbsp;';
  end;
}


# Tag score in html tags, argument: score, users
sub tagscore {
  my $s = shift;
  div class => 'taglvl', style => sprintf('width: %.0fpx', ($s-floor($s))*10), ' ' if $s < 0 && $s-floor($s) > 0;
  for(-3..3) {
    div(class => "taglvl taglvl0", sprintf '%.1f', $s), next if !$_;
    if($_ < 0) {
      if($s > 0 || floor($s) > $_) {
        div class => "taglvl taglvl$_", ' ';
      } elsif(floor($s) != $_) {
        div class => "taglvl taglvl$_ taglvlsel", ' ';
      } else {
        div class => "taglvl taglvl$_ taglvlsel", style => sprintf('width: %.0fpx', 10-($s-$_)*10), ' ';
      }
    } else {
      if($s < 0 || ceil($s) < $_) {
        div class => "taglvl taglvl$_", ' ';
      } elsif(ceil($s) != $_) {
        div class => "taglvl taglvl$_ taglvlsel", ' ';
      } else {
        div class => "taglvl taglvl$_ taglvlsel", style => sprintf('width: %.0fpx', 10-($_-$s)*10), ' ';
      }
    }
  }
  div class => 'taglvl', style => sprintf('width: %.0fpx', (ceil($s)-$s)*10), ' ' if $s > 0 && ceil($s)-$s > 0;
}


# short wrapper around maketext()
# (not thread-safe, in the same sense as YAWF::XML. But who cares about threads, anyway?)
sub mt {
  return $YAWF::OBJ->{l10n}->maketext(@_);
}


sub minage {
  my($a, $ex) = @_;
  my $str = $a == -1 ? mt '_minage_null' : !$a ? mt '_minage_all' : mt '_minage_age', $a;
  $ex = !defined($a) ? '' : {
     0 => 'CERO A',
    12 => 'CERO B',
    15 => 'CERO C',
    17 => 'CERO D',
    18 => 'CERO Z',
  }->{$a} if $ex;
  return $str if !$ex;
  return $str.' '.mt('_minage_example', $ex);
}


# arguments: $filter_string, @allowed_keys
sub fil_parse {
  my $str = shift;
  my %keys = map +($_,1), @_;
  my %r;
  for (split /\./, $str) {
    next if !/^([a-z0-9_]+)-([a-zA-Z0-9_~]+)$/ || !$keys{$1};
    my($f, $v) = ($1, $2);
    my @v = split /~/, $v;
    s/_([0-9]{2})/$1 > $#fil_escape ? '' : $fil_escape[$1]/eg for(@v);
    $r{$f} = @v > 1 ? \@v : $v[0]
  }
  return \%r;
}


sub fil_serialize {
  my $fil = shift;
  my $e = qr/([\Q$fil_escape\E])/;
  return join '.', map {
    my @v = ref $fil->{$_} ? @{$fil->{$_}} : ($fil->{$_});
    s/$e/_$fil_escape{$1}/g for(@v);
    $_.'-'.join '~', @v
  } grep defined($fil->{$_}), keys %$fil;
}

1;

