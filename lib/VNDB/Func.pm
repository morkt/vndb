
package VNDB::Func;

use strict;
use warnings;
use YAWF ':html';
use Exporter 'import';
use POSIX 'strftime', 'ceil', 'floor';
our @EXPORT = qw| shorten bb2html gtintype liststat clearfloat cssicon tagscore mt minage |;


# I would've done this as a #define if this was C...
sub shorten {
  my($str, $len) = @_;
  return length($str) > $len ? substr($str, 0, $len-3).'...' : $str;
}


# Arguments: input, and optionally the maximum length
# Parses:
#  [url=..] [/url]
#  [raw] .. [/raw]
#  [spoiler] .. [/spoiler]
#  [quote] .. [/quote]
#  [code] .. [/code]
#  v+,  v+.+
#  http://../
sub bb2html {
  my $raw = shift;
  my $maxlength = shift;
  $raw =~ s/\r//g;
  $raw =~ s/\n{5,}/\n\n/g;
  return '' if !$raw && $raw ne "0";

  my($result, $length, $rmnewline, @open) = ('', 0, 0, 'first');

  my $e = sub {
    local $_ = shift;
    s/&/&amp;/g;
    s/>/&gt;/g;
    s/</&lt;/g;
    s/\n/<br \/>/g if !$maxlength;
    s/\n/ /g if $maxlength;
    return $_;
  };

  for (split /(\s|\n|\[[^\]]+\])/, $raw) {
    next if !defined $_;
    next if $_ eq '';

    # (note to self: stop using unreadable hacks like these!)
    $rmnewline-- && $_ eq "\n" && next if $rmnewline;

    my $lit = $_;
    if($open[$#open] ne 'raw' && $open[$#open] ne 'code') {
      if    (lc$_ eq '[raw]')      { push @open, 'raw'; next }
      elsif (lc$_ eq '[spoiler]')  { push @open, 'spoiler'; $result .= '<b class="spoiler">'; next }
      elsif (lc$_ eq '[quote]')    {
        push @open, 'quote';
        $result .= '<div class="quote">' if !$maxlength;
        $rmnewline = 1;
        next
      } elsif (lc$_ eq '[code]') {
        push @open, 'code';
        $result .= '<pre>' if !$maxlength;
        $rmnewline = 1;
        next
      } elsif (lc$_ eq '[/spoiler]') {
        if($open[$#open] eq 'spoiler') {
          $result .= '</b>';
          pop @open;
        }
        next;
      } elsif (lc$_ eq '[/quote]') {
        if($open[$#open] eq 'quote') {
          $result .= '</div>' if !$maxlength;
          $rmnewline = 1;
          pop @open;
        }
        next;
      } elsif(lc$_ eq '[/url]') {
        if($open[$#open] eq 'url') {
          $result .= '</a>';
          pop @open;
        }
        next;
      } elsif(s{\[url=((https?://|/)[^\]>]+)\]}{<a href="$1" rel="nofollow">}i) {
        $result .= $_;
        push @open, 'url';
        next;
      } elsif(!grep(/url/, @open) &&
           s{(.*)(http|https)://(.+[\d\w=/-])(.*)}
            {$e->($1).qq|<a href="$2://|.$e->($3, 1).'" rel="nofollow">'.$e->('link').'</a>'.$e->($4)}e) {
        $length += 4;
        last if $maxlength && $length > $maxlength;
        $result .= $_;
        next;
      } elsif(!grep(/url/, @open) && (
          s{^(.*[^\w]|)([tdvpr][1-9][0-9]*)\.([1-9][0-9]*)([^\w].*|)$}{$e->($1).qq|<a href="/$2.$3">$2.$3</a>|.$e->($4)}e ||
          s{^(.*[^\w]|)([tdvprug][1-9][0-9]*)([^\w].*|)$}{$e->($1).qq|<a href="/$2">$2</a>|.$e->($3)}e)) {
        $length += length $lit;
        last if $maxlength && $length > $maxlength;
        $result .= $_;
        next;
      }
    } elsif($open[$#open] eq 'raw' && lc$_ eq '[/raw]') {
      pop @open;
      next;
    } elsif($open[$#open] eq 'code' && lc$_ eq '[/code]') {
      $result .= '</pre>' if !$maxlength;
      pop @open;
      next;
    }

    # normal text processing
    $length += length $_;
    last if $maxlength && $length > $maxlength;
    $result .= $e->($_);
  }

  # close open tags
  while((local $_ = pop @open) ne 'first') {
    $result .= $_ eq 'url' ? '</a>' : $_ eq 'spoiler' ? '</b>' : '';
    $result .= $_ eq 'quote' ? '</div>' : $_ eq 'code' ? '</pre>' : '' if !$maxlength;
  }
  $result .= '...' if $maxlength && $length > $maxlength;

  return $result;
}


# GTIN code as argument,
# Returns 'JAN', 'EAN', 'UPC' or undef,
# Also 'normalizes' the first argument in place
sub gtintype {
  $_[0] =~ s/[^\d]+//g;
  my $c = shift;
  return undef if $c !~ /^[0-9]{12,13}$/; # only gtin-12 and 13
  $c = ('0'x(13-length $c)) . $c; # pad with zeros

  # calculate check digit according to
  #  http://www.gs1.org/productssolutions/barcodes/support/check_digit_calculator.html#how
  my @n = reverse split //, $c;
  my $n = shift @n;
  $n += $n[$_] * ($_ % 2 != 0 ? 1 : 3) for (0..$#n);
  return undef if $n % 10 != 0;

  # Do some rough guesses based on:
  #  http://www.gs1.org/productssolutions/barcodes/support/prefix_list.html
  #  and http://en.wikipedia.org/wiki/List_of_GS1_country_codes
  local $_ = $c;
  return 'JAN' if /^4[59]/; # prefix code 450-459 & 490-499
  return 'UPC' if /^(?:0[01]|0[6-9]|13|75[45])/; # prefix code 000-019 & 060-139 & 754-755
  return  undef if /^(?:0[2-5]|2|97[789]|9[6-9])/; # some codes we don't want: 020–059 & 200-299 & 977-999
  return 'EAN'; # let's just call everything else EAN :)
}


# Argument: hashref with rstat and vstat
# Returns: empty string if not in list, otherwise colour-encoded list status
sub liststat {
  my $l = shift;
  return '' if !$l;
  my $rs = mt('_rlst_rstat_'.$l->{rstat});
  $rs = qq|<b class="done">$rs</b>| if $l->{rstat} == 2; # Obtained
  $rs = qq|<b class="todo">$rs</b>| if $l->{rstat} < 2; # Unknown/pending
  my $vs = mt('_rlst_vstat_'.$l->{vstat});
  $vs = qq|<b class="done">$vs</b>| if $l->{vstat} == 2; # Finished
  $vs = qq|<b class="todo">$vs</b>| if $l->{vstat} == 0 || $l->{vstat} == 4; # Unknown/dropped
  return "$rs / $vs";
}


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
  my $str = !defined($a) ? mt '_minage_null' : !$a ? mt '_minage_all' : mt '_minage_age', $a;
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


1;

