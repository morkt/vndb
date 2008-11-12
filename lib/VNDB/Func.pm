
package VNDB::Func;

use strict;
use warnings;
use Exporter 'import';
use POSIX 'strftime';
our @EXPORT = qw| shorten date datestr bb2html |;


# I would've done this as a #define if this was C...
sub shorten {
  my($str, $len) = @_;
  return length($str) > $len ? substr($str, 0, $len-3).'...' : $str;
}


# argument: unix timestamp
# return value: yyyy-mm-dd
# (maybe an idea to use cgit-style ages for recent timestamps)
sub date {
  return strftime '%Y-%m-%d', gmtime shift;
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


# Parses BBCode-enhanced strings into the correct HTML variant with an optional maximum length
sub bb2html { # input, length
  return $_[2] || ' ' if !$_[0];  # No clue what this is for, but it is included from the previous verison for posterity...
  my $raw = $_[0];
  my $maxLength;
  if (defined($_[1])) {$maxLength = $_[1]}
  else {$maxLength = length $_[0]}

  my $result = '';
  my $length = 0;
  my $inRaw = 0;
  my $inSpoiler = 0;
  my $inUrl = 0;

  # Split the input string into segments
  foreach (split /(\s|\[.+?\])/, $raw)
  {
    if (!defined($_)) {next}

    if (!$inRaw)
    {
      # Cases for BBCode tags
      if    ($_ eq '[raw]')      {$inRaw = 1; next}
      elsif ($_ eq '[spoiler]')  {$inSpoiler = 1; next}
      elsif ($_ eq '[/spoiler]') {$inSpoiler = 0; next}
      elsif ($_ eq '[/url]')
      {
        $result .= '</a>';
        $inUrl = 0;
        next;
      }
      # Process [url=.+] tags
      if (s/\[url=((https?:\/\/|\/)[^\]>]+)\]/<a href="$1" rel="nofollow">/i)
      {
        $result .= $_;
        $inUrl = 1;
        next;
      }
    }

    my $lit = $_;   # Literal version of the segment to refence in case we link-ify the original

    if ($_ eq '[/raw]')
    {
      # Special case for leaving raw mode
      $inRaw = 0;
    }
    elsif ($_ =~ m/\n/)
    {
      # Parse line breaks
      $result .= (defined($_[1])?'':'<br />');
    }
    elsif (!$inRaw && !$inUrl && s/(http|https):\/\/(.+[0-9a-zA-Z=\/])/<a href="$1:\/\/$2" rel="nofollow">/)
    {
      # Parse automatic links
      $length += 4;
      if ($length <= $maxLength)
      {
        $lit = 'link';

        # ROT-13 of 'link'
        $lit = 'yvax' if $inSpoiler;

        $result .= $_ . $lit . '</a>';
      }
    }
    elsif (!$inRaw && !$inUrl && (s/^(.*[^\w]|)([tdvpr][1-9][0-9]*)\.([1-9][0-9]*)([^\w].*|)$/"$1<a href=\"\/$2.$3\">". ($inSpoiler?rot13("$2.$3"):"$2.$3") ."<\/a>$4"/e ||
        s/^(.*[^\w]|)([tduvpr][1-9][0-9]*)([^\w].*|)$/"$1<a href=\"\/$2\">". ($inSpoiler?rot13($2):$2) ."<\/a>$3"/e))
    {
      # Parse VNDBID
      $length += length $lit;
      if ($length <= $maxLength)
      {
        $result .= $_;
      }
    }
    else
    {
      # Normal text processing
      $length += length $_;
      if ($length <= $maxLength)
      {
        # ROT-13
        tr/A-Za-z/N-ZA-Mn-za-m/ if $inSpoiler;

        # Character escaping
        s/\&/&amp;/g;
        s/>/&gt;/g;
        s/</&lt;/g;

        $result .= $_;
      }
    }

    # End if we've reached the maximum length/string end
    if ($length >= $maxLength)
    {
      # Tidy up the end of the string
      $result =~ s/\s+$//;
      $result .= '...';
      last;
    }
  }

  # Close any un-terminated url tags
  $result .= '</a>' if $inUrl;

  return $result;
}
 
# Performs a ROT-13 cypher (used by bb2html)
sub rot13 {
  return tr/A-Za-z/N-ZA-Mn-za-m/;
}


1;

