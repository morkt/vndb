
package VNDB::Func;

use strict;
use warnings;
use TUWF ':html';
use Exporter 'import';
use POSIX 'strftime', 'ceil', 'floor';
use VNDBUtil;
our @EXPORT = (@VNDBUtil::EXPORT, qw|
  clearfloat cssicon tagscore mt minage fil_parse fil_serialize parenttags
  childtags charspoil imgpath imgurl fmtvote
|);


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
sub mt {
  return $TUWF::OBJ->{l10n}->maketext(@_);
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


# generates a parent tags/traits listing
sub parenttags {
  my($t, $index, $type) = @_;
  p;
   my @p = _parenttags(@{$t->{parents}});
   for my $p (@p ? @p : []) {
     a href => "/$type", $index; #mt '_tagp_indexlink';
     for (reverse @$p) {
       txt ' > ';
       a href => "/$type$_->{id}", $_->{name};
     }
     txt " > $t->{name}";
     br;
   }
  end 'p';
}

# arg: tag/trait hashref
# returns: [ [ tag1, tag2, tag3 ], [ tag1, tag2, tag5 ] ]
sub _parenttags {
  my @r;
  for my $t (@_) {
    for (@{$t->{'sub'}}) {
      push @r, [ $t, @$_ ] for _parenttags($_);
    }
    push @r, [$t] if !@{$t->{'sub'}};
  }
  return @r;
}


# a child tags/traits box
sub childtags {
  my($self, $title, $type, $t, $order) = @_;

  div class => 'mainbox';
   h1 $title;
   ul class => 'tagtree';
    for my $p (sort { !$order ? @{$b->{'sub'}} <=> @{$a->{'sub'}} : $a->{$order} <=> $b->{$order} } @{$t->{childs}}) {
      li;
       a href => "/$type$p->{id}", $p->{name};
       b class => 'grayedout', " ($p->{c_items})" if $p->{c_items};
       end, next if !@{$p->{'sub'}};
       ul;
        for (0..$#{$p->{'sub'}}) {
          last if $_ >= 5 && @{$p->{'sub'}} > 6;
          li;
           txt '> ';
           a href => "/$type$p->{sub}[$_]{id}", $p->{'sub'}[$_]{name};
           b class => 'grayedout', " ($p->{sub}[$_]{c_items})" if $p->{'sub'}[$_]{c_items};
          end;
        }
        if(@{$p->{'sub'}} > 6) {
          li;
           txt '> ';
           a href => "/$type$p->{id}", style => 'font-style: italic', mt $type eq 'g' ? '_tagp_moretags' : '_traitp_more', @{$p->{'sub'}}-5;
          end;
        }
       end;
      end 'li';
    }
   end 'ul';
   clearfloat;
   br;
  end 'div';
}


# generates the class elements for character spoiler hiding
sub charspoil {
  return "charspoil charspoil_$_[0]".($_[0] ? ' hidden' : '');
}


# generates a local path to an image in static/
sub imgpath { # <type>, <id>
  return sprintf '%s/static/%s/%02d/%d.jpg', $VNDB::ROOT, $_[0], $_[1]%100, $_[1];
}


# generates a URL for an image in static/
sub imgurl {
  return sprintf '%s/%s/%02d/%d.jpg', $TUWF::OBJ->{url_static}, $_[0], $_[1]%100, $_[1];
}


# Formats a vote number.
sub fmtvote {
  return !$_[0] ? '-' : $_[0] % 10 == 0 ? $_[0]/10 : sprintf '%.1f', $_[0]/10;
}

1;

