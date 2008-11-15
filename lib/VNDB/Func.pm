
package VNDB::Func;

use strict;
use warnings;
use Exporter 'import';
use POSIX 'strftime';
our @EXPORT = qw| shorten date datestr userstr bb2html |;


# I would've done this as a #define if this was C...
sub shorten {
  my($str, $len) = @_;
  return length($str) > $len ? substr($str, 0, $len-3).'...' : $str;
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
#  v+,  v+.+
#  http://../
sub bb2html { 
  my $raw = shift;
  my $maxlength = shift;
  $raw =~ s/\r//g;
  return '' if !$raw && $raw ne "0";

  my($result, $length, @open) = ('', 0, 'first');

  my $e = sub {
    local $_ = shift;
    tr/A-Za-z/N-ZA-Mn-za-m/ if !@_ && grep /spoiler/, @open;
    s/&/&amp;/g;
    s/>/&gt;/g;
    s/</&lt;/g;
    s/\n/<br \/>/g if !$maxlength;
    s/\n/ /g if $maxlength;
    return $_;
  };

  for (split /(\s|\n|\[[^\]]+\])/, $raw) {
    next if !defined $_;

    my $lit = $_;
    if($open[$#open] ne 'raw') {
      if    ($_ eq '[raw]')      { push @open, 'raw'; next }
      elsif ($_ eq '[spoiler]')  { push @open, 'spoiler'; next }
      elsif ($_ eq '[/spoiler]') { pop @open if $open[$#open] eq 'spoiler'; next }
      elsif ($_ eq '[/url]')     {
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
           s{(.*)(http|https)://(.+[0-9a-zA-Z=/])(.*)}
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
    } elsif($_ eq '[/raw]') {
      pop @open if $open[$#open] eq 'raw';
      next;
    } 
    
    # normal text processing
    $length += length $_;
    last if $maxlength && $length > $maxlength;
    $result .= $e->($_);
  }

  $result .= '</a>' 
    while((local $_ = pop @open) ne 'first');
  $result .= '...' if $maxlength && $length > $maxlength;

  return $result;
}


1;

