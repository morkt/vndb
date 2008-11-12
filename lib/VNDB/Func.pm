
package VNDB::Func;

use strict;
use warnings;
use Exporter 'import';
use POSIX 'strftime';
our @EXPORT = qw| shorten date |;


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


1;
