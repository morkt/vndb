# Misc. utility functions, do not rely on YAWF or POE and can be used from any script

package VNDBUtil;

use strict;
use warnings;
use Exporter 'import';
use Encode 'encode_utf8';
use Unicode::Normalize 'NFKD';
use Socket 'inet_pton', 'inet_ntop', 'AF_INET', 'AF_INET6';

our @EXPORT = qw|shorten bb2html gtintype normalize normalize_titles normalize_query imgsize norm_ip|;


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
# XXX: Make sure to sync any changes in the formating with
#   VNDB::Util::Misc::bbSubstLinks() if necessary. Or, alternatively, abstract
#   parsing into a separate function as per http://beta.vndb.org/t5564.12
sub bb2html {
  my($raw, $maxlength, $charspoil) = @_;
  $raw =~ s/\r//g;
  return '' if !$raw && $raw ne "0";

  my($result, $last, $length, $rmnewline, @open) = ('', 0, 0, 0, 'first');

  # escapes, returns string, and takes care of $length and $maxlength; also
  # takes care to remove newlines and double spaces when necessary
  my $e = sub {
    local $_ = shift;
    s/^\n//         if $rmnewline && $rmnewline--;
    s/\n{5,}/\n\n/g if $open[$#open] ne 'code';
    s/  +/ /g       if $open[$#open] ne 'code';
    $length += length $_;
    if($maxlength && $length > $maxlength) {
      $_ = substr($_, 0, $maxlength-$length);
      s/[ \.,:;]+[^ \.,:;]*$//; # cleanly cut off on word boundary
    }
    s/&/&amp;/g;
    s/>/&gt;/g;
    s/</&lt;/g;
    s/\n/<br \/>/g if !$maxlength;
    s/\n/ /g       if $maxlength;
    return $_;
  };

  while($raw =~ m{(
    (d[1-9][0-9]*\.[1-9][0-9]*\.[1-9][0-9]*)  | # 2. longid
    ([tdvprcs][1-9][0-9]*\.[1-9][0-9]*)       | # 3. exid
    ([tdvprcsugi][1-9][0-9]*)                 | # 4. id
    (\[[^\s\]]+\])                            | # 5. tag
    ((?:https?|ftp)://[^><"\n\s\]\[]+[\d\w=/-]) # 6. url
  )}xg) {
    my($match, $longid, $exid, $id, $tag, $url) = ($1, $2, $3, $4, $5, $6);

    # add string before the match
    $result .= $e->(substr $raw, $last, (pos($raw)-length($match))-$last);
    last if $maxlength && $length > $maxlength;
    $last = pos $raw;

    if($open[$#open] ne 'raw' && $open[$#open] ne 'code') {
      # handle tags
      if($tag) {
        $tag = lc $tag;
        if($tag eq '[raw]') {
          push @open, 'raw';
          next;
        } elsif($tag eq '[spoiler]') {
          push @open, 'spoiler';
          $result .= !$charspoil ? '<b class="spoiler">'
            : '<b class="grayedout charspoil charspoil_-1">&lt;hidden by spoiler settings&gt;</b><span class="charspoil charspoil_2 hidden">';
          next;
        } elsif($tag eq '[quote]') {
          push @open, 'quote';
          $result .= '<div class="quote">' if !$maxlength;
          $rmnewline = 1;
          next;
        } elsif($tag eq '[code]') {
          push @open, 'code';
          $result .= '<pre>' if !$maxlength;
          $rmnewline = 1;
          next;
        } elsif($tag eq '[/spoiler]' && $open[$#open] eq 'spoiler') {
          $result .= !$charspoil ? '</b>' : '</span>';
          pop @open;
          next;
        } elsif($tag eq '[/quote]' && $open[$#open] eq 'quote') {
          $result .= '</div>' if !$maxlength;
          $rmnewline = 1;
          next;
        } elsif($tag eq '[/url]' && $open[$#open] eq 'url') {
          $result .= '</a>';
          pop @open;
          next;
        } elsif($match =~ s{\[url=((https?://|/)[^\]>]+)\]}{<a href="$1" rel="nofollow">}i) {
          $result .= $match;
          push @open, 'url';
          next;
        }
      }
      # handle URLs
      if($url && !grep(/url/, @open)) {
        $length += 4;
        last if $maxlength && $length > $maxlength;
        $result .= sprintf '<a href="%s" rel="nofollow">link</a>', $url;
        next;
      }
      # id
      if(($id || $exid || $longid) && !grep(/url/, @open) && (!$result || substr($raw, $last-1-length($match), 1) !~ /[\w]/) && substr($raw, $last, 1) !~ /[\w]/) {
        (my $lnk = $match) =~ s/^d(\d+)\.(\d+)\.(\d+)$/d$1#$2.$3/;
        $length += length $lnk;
        last if $maxlength && $length > $maxlength;
        $result .= sprintf '<a href="/%s">%s</a>', $lnk, $match;
        next
      }
    }

    if($tag && $open[$#open] eq 'raw' && lc$tag eq '[/raw]') {
      pop @open;
      next;
    }

    if($tag && $open[$#open] eq 'code' && lc$tag eq '[/code]') {
      $result .= '</pre>' if !$maxlength;
      pop @open;
      next;
    }

    # We'll only get here when the bbcode input isn't correct or something else
    # didn't work out. In that case, just output whatever we've matched.
    $result .= $e->($match);
    last if $maxlength && $length > $maxlength;
  }

  # the last unmatched part, just escape and output
  $result .= $e->(substr $raw, $last);

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
  tr/\r\n\t,_\-.~～〜∼῀:[]()%+!?#$"'`♥★☆♪†「」『』【】・‟”‛’‘‚„«‹»›//d;
  tr/@/a/;
  s/&/and/;
  # Consider wo and o the same thing (when used as separate word)
  s/(?:^| )o(?:$| )/wo/g;
  # Remove spaces. We're doing substring search, so let it cross word boundary to find more stuff
  tr/ //d;
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
  s/sempai/senpai/g;
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
  # Consider wo and o the same thing (when used as separate word). Has to be
  # done here (in addition to normalize()) to make it work in combination with
  # double quote search.
  $q =~ s/(^| )o($| )/$1wo$2/ig;
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


# Normalized IP address to use for duplicate detection/throttling. For IPv4
# this is the /23 subnet (is this enough?), for IPv6 the /48 subnet, with the
# least significant bits of the address zero'd.
sub norm_ip {
    my $ip = shift;

    # There's a whole bunch of IP manipulation modules on CPAN, but many seem
    # quite bloated and still don't offer the functionality to return an IP
    # with its mask applied (admittedly not a common operation). The libc
    # socket functions will do fine in parsing and formatting addresses, and
    # the actual masking is quite trivial in binary form.
    my $v4 = inet_pton AF_INET, $ip;
    if($v4) {
      $v4 =~ s/(..)(.)./$1 . chr(ord($2) & 254) . "\0"/se;
      return inet_ntop AF_INET, $v4;
    }

    $ip = inet_pton AF_INET6, $ip;
    return '::' if !$ip;
    $ip =~ s/^(.{6}).+$/$1 . "\0"x10/se;
    return inet_ntop AF_INET6, $ip;
}

1;

