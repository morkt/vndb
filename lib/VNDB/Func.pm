
package VNDB::Func;

use strict;
use warnings;
use YAWF ':html';
use Exporter 'import';
use POSIX 'strftime';
our @EXPORT = qw| shorten age date datestr monthstr userstr bb2html gtintype liststat clearfloat cssicon |;


# I would've done this as a #define if this was C...
sub shorten {
  my($str, $len) = @_;
  return length($str) > $len ? substr($str, 0, $len-3).'...' : $str;
}


# Argument: unix timestamp
# Returns: age
sub age {
  my $a = time-$_[0];
  return sprintf '%d %s ago',
    $a > 60*60*24*365*2       ? ( $a/60/60/24/365,      'years'  ) :
    $a > 60*60*24*(365/12)*2  ? ( $a/60/60/24/(365/12), 'months' ) :
    $a > 60*60*24*7*2         ? ( $a/60/60/24/7,        'weeks'  ) :
    $a > 60*60*24*2           ? ( $a/60/60/24,          'days'   ) :
    $a > 60*60*2              ? ( $a/60/60,             'hours'  ) :
    $a > 60*2                 ? ( $a/60,                'min'    ) :
                                ( $a,                   'sec'    );
}


# argument: unix timestamp and optional format (compact/full)
# return value: yyyy-mm-dd
# (maybe an idea to use cgit-style ages for recent timestamps)
sub date {
  my($t, $f) = @_;
  return strftime '%Y-%m-%d', gmtime $t if !$f || $f eq 'compact';
  return strftime '%Y-%m-%d at %R', gmtime $t;
}


# argument: database release date format (yyyymmdd)
#  y = 0000 -> unkown
#  y = 9999 -> TBA
#  m = 99   -> month+day unkown
#  d = 99   -> day unknown
# return value: (unknown|TBA|yyyy|yyyy-mm|yyyy-mm-dd)
#  if date > now: <b class="future">str</b>
sub datestr {
  my $date = sprintf '%08d', shift||0;
  my $future = $date > strftime '%Y%m%d', gmtime;
  my($y, $m, $d) = ($1, $2, $3) if $date =~ /^([0-9]{4})([0-9]{2})([0-9]{2})$/;

  my $str = $y == 0 ? 'unknown' : $y == 9999 ? 'TBA' :
    $m == 99 ? sprintf('%04d', $y) :
    $d == 99 ? sprintf('%04d-%02d', $y, $m) :
               sprintf('%04d-%02d-%02d', $y, $m, $d);

  return $str if !$future;
  return qq|<b class="future">$str</b>|;
}

# same as datestr(), but different output format:
#  e.g.: 'Jan 2009', '2009', 'unknown', 'TBA'
sub monthstr {
  my $date = sprintf '%08d', shift||0;
  my($y, $m) = ($1, $2) if $date =~ /^([0-9]{4})([0-9]{2})/;
  return 'TBA' if $y == 9999;
  return 'unknown' if $y == 0;
  return $y if $m == 99;
  return sprintf '%s %d', [qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec)]->[$m-1], $y;
}


# Arguments: (uid, username), or a hashref containing that info
sub userstr {
  my($id,$n) = ref($_[0])eq'HASH'?($_[0]{uid}||$_[0]{requester}, $_[0]{username}):@_;
  return !$id ? '[deleted]' : '<a href="/u'.$id.'">'.$n.'</a>';
}


# Arguments: input, and optionally the maximum length
# Parses:
#  [url=..] [/url]
#  [raw] .. [/raw]
#  [spoiler] .. [/spoiler]
#  [quote] .. [/quote]
#  v+,  v+.+
#  http://../
sub bb2html {
  my $raw = shift;
  my $maxlength = shift;
  $raw =~ s/\r//g;
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

    $rmnewline = s/\n//g if $rmnewline;
    next if $_ eq '';

    my $lit = $_;
    if($open[$#open] ne 'raw') {
      if    (lc$_ eq '[raw]')      { push @open, 'raw'; next }
      elsif (lc$_ eq '[spoiler]')  { push @open, 'spoiler'; $result .= '<b class="spoiler">'; next }
      elsif (lc$_ eq '[quote]')    {
        push @open, 'quote';
        $result .= '<div class="quote">' if !$maxlength;
        $rmnewline++;
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
          $rmnewline++;
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
          s{^(.*[^\w]|)([tduvpr][1-9][0-9]*)([^\w].*|)$}{$e->($1).qq|<a href="/$2">$2</a>|.$e->($3)}e)) {
        $length += length $lit;
        last if $maxlength && $length > $maxlength;
        $result .= $_;
        next;
      }
    } elsif(lc$_ eq '[/raw]') {
      pop @open if $open[$#open] eq 'raw';
      next;
    }

    # normal text processing
    $length += length $_;
    last if $maxlength && $length > $maxlength;
    $result .= $e->($_);
  }

  $result .= $_ eq 'url' ? '</a>' : $_ eq 'quote' ? '</div>' : '</b>'
    while((local $_ = pop @open) ne 'first');
  $result .= '...' if $maxlength && $length > $maxlength;

  return $result;
}


# GTIN code as argument,
# Returns 'JAN', 'EAN', 'UPC' or undef,
# Also 'normalizes' the first argument in place
sub gtintype {
  $_[0] =~ s/[^\d]+//g;
  $_[0] =~ s/^0+//;
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
  return  undef if /(?:0[2-5]|2|97[789]|9[6-9])/; # some codes we don't want: 020–059 & 200-299 & 977-999
  return 'EAN'; # let's just call everything else EAN :)
}


# Argument: hashref with rstat and vstat
# Returns: empty string if not in list, otherwise colour-encoded list status
sub liststat {
  my $l = shift;
  return '' if !$l;
  my $rs = $YAWF::OBJ->{vn_rstat}[$l->{rstat}];
  $rs = qq|<b class="done">$rs</b>| if $l->{rstat} == 2; # Obtained
  $rs = qq|<b class="todo">$rs</b>| if $l->{rstat} < 2; # Unknown/pending
  my $vs = $YAWF::OBJ->{vn_vstat}[$l->{vstat}];
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


1;

