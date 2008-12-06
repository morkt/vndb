
package VNDB::DB::Votes;

use strict;
use warnings;
use Exporter 'import';


our @EXPORT = qw|dbVoteGet dbVoteStats|;


# %options->{ uid vid hide order results page }
sub dbVoteGet { 
  my($self, %o) = @_;
  $o{order} ||= 'n.date DESC';
  $o{results} ||= 50;
  $o{page} ||= 1;

  my %where = (
    $o{uid} ? ( 'n.uid = ?' => $o{uid} ) : (),
    $o{vid} ? ( 'n.vid = ?' => $o{vid} ) : (),
    $o{hide} ? ( 'u.show_list = FALSE' => 1 ) : (),
  );

  my($r, $np) = $self->dbPage(\%o, q|
    SELECT n.vid, vr.title, vr.original, n.vote, n.date, n.uid, u.username
      FROM votes n
      JOIN vn v ON v.id = n.vid
      JOIN vn_rev vr ON vr.id = v.latest
      JOIN users u ON u.id = n.uid
      !W
      ORDER BY !s|,      
    \%where
  );

  return wantarray ? ($r, $np) : $r;
}


# Arguments: (uid|vid), id
# Returns an arrayref with 10 elements containing the number of votes for index+1
sub dbVoteStats { 
  my($self, $col, $id) = @_;
  my $r = [ qw| 0 0 0 0 0 0 0 0 0 0 | ];
  $r->[$_->{vote}-1] = $_->{votes} for (@{$self->dbAll(q|
    SELECT vote, COUNT(vote) as votes
      FROM votes
      !W
      GROUP BY vote|,
    $col ? { '!s = ?' => [ $col, $id ] } : {},
  )});
  return $r;
}


1;

