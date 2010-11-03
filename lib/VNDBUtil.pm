# Misc. utility functions, do not rely on YAWF or POE and can be used from any script

package VNDBUtil;

use strict;
use warnings;
use Exporter 'import';
use Unicode::Normalize 'NFKD';

our @EXPORT = qw|shorten bb2html gtintype normalize normalize_titles normalize_query imgsize|;


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
  $_[0] = ('0'x(12-length $_[0])) . $_[0] if length($_[0]) < 12; # pad with zeros to GTIN-12
  my $c = shift;
  return undef if $c !~ /^[0-9]{12,13}$/;
  $c = "0$c" if length($c) == 12; # pad with another zero for GTIN-13

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


# a rather aggressive normalization
sub normalize {
  local $_ = lc shift;
  # remove combining markings. assuming the string is in NFD or NFKD,
  #  this effectively removes all accents from the characters (e.g. é -> e)
  s/\pM//g;
  # remove some characters that have no significance when searching
  use utf8;
  tr/\r\n\t ,_\-.~:[]()%+!?&#$"'`♥★☆♪†「」『』【】・”//d;
  tr/@/a/;
  # remove commonly used release titles ("x Edition" and "x Version")
  # this saves some space and speeds up the search
  s/(?:
    first|firstpress|firstpresslimited|limited|regular|standard
   |package|boxed|download|complete|popular
   |lowprice|best|cheap|budget
   |special|trial|allages|fullvoice
   |cd|cdr|cdrom|dvdrom|dvd|dvdpack|dvdpg|windows
   |初回限定|初回|限定|通常|廉価|パッケージ|ダウンロード
   )(?:edition|version|版|生産)//xg;
  # other common things
  s/fandisk/fandisc/g;
  no utf8;
  return $_;
}


# normalizes each title and returns a concatenated string of unique titles
sub normalize_titles {
  my %t = map +(normalize(NFKD($_)), 1), @_;
  return join ' ', grep $_, keys %t;
}


sub normalize_query {
  my $q = NFKD shift;
  # remove spaces within quotes, so that it's considered as one search word
  $q =~ s/"([^"]+)"/(my $s=$1)=~y{ }{}d;$s/ge;
  # split into search words, normalize, and remove too short words
  return map length($_)>=(/^[\x01-\x7F]+$/?2:1) ? quotemeta($_) : (), map normalize($_), split / /, $q;
}


# arguments: <image size>, <max dimensions>
# returns the size of the thumbnail with the same aspect ratio as the full-size
#   image, but fits within the specified maximum dimensions
sub imgsize {
  my($ow, $oh, $sw, $sh) = @_;
  return ($ow, $oh) if $ow <= $sw && $oh <= $sh;
  if($ow/$oh > $sw/$sh) { # width is the limiting factor
    $oh *= $sw/$ow;
    $ow = $sw;
  } else {
    $ow *= $sh/$oh;
    $oh = $sh;
  }
  return (int $ow, int $oh);
}


1;

