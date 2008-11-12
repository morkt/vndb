
package VNDB::Func;

use strict;
use warnings;
use Exporter 'import';
use POSIX 'strftime';
our @EXPORT = qw| shorten date datestr |;


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


