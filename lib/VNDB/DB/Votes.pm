
package VNDB::DB::Votes;

use strict;
use warnings;
use Exporter 'import';


our @EXPORT = qw|dbVoteGet dbVoteStats dbVoteAdd dbVoteDel|;


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
    \%where, $o{order}
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


# Adds a new vote or updates an existing one
# Arguments: vid, uid, vote
sub dbVoteAdd {
  my($self, $vid, $uid, $vote) = @_;
  $self->dbExec(q|
    UPDATE votes
      SET vote = ?
      WHERE vid = ?
      AND uid = ?|,
    $vote, $vid, $uid
  ) || $self->dbExec(q|
    INSERT INTO votes
      (vid, uid, vote, date)
      VALUES (!l)|,
    [ $vid, $uid, $vote, time ]
  );
}


# Arguments: uid, vid
sub dbVoteDel {
  my($self, $uid, $vid) = @_;
  $self->dbExec('DELETE FROM votes !W',
    { 'vid = ?' => $vid, 'uid = ?' => $uid }
  );
}


1;

