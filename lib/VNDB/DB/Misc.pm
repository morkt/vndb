
package VNDB::DB::Misc;

use strict;
use warnings;
use Exporter 'import';

our @EXPORT = qw|
  dbStats
|;


# Arguments: array of elements to get stats from, options:
#   vn, producers, releases, users, threads, posts
# Returns: hashref, key = element, value = number of entries
# TODO: caching, see http://www.varlena.com/GeneralBits/120.php
sub dbStats { 
  my $s = shift;
  return { map {
    $_ => $s->dbRow('SELECT COUNT(*) as cnt FROM !s !W',
      /posts/ ? 'threads_posts' : $_,
      /producers|vn|releases|threads|posts/ ? { 'hidden = ?' => 0 } : {}
    )->{cnt} - (/users/ ? 1 : 0);
  } @_ };
}

1;

