
package VNDB::DB::Producers;

use strict;
use warnings;
use Exporter 'import';

our @EXPORT = qw|dbProducerGet dbProducerEdit dbProducerAdd|;


# options: results, page, id, search, char, rev
# what: extended changes vn relations relgraph
sub dbProducerGet {
  my $self = shift;
  my %o = (
    results => 10,
    page => 1,
    what => '',
    @_
  );

  $o{search} =~ s/%//g if $o{search};

  my %where = (
    !$o{id} && !$o{rev} ? (
      'p.hidden = FALSE' => 1 ) : (),
    $o{id} ? (
      'p.id = ?' => $o{id} ) : (),
    $o{search} ? (
      '(pr.name ILIKE ? OR pr.original ILIKE ? OR pr.alias ILIKE ?)', [ map '%%'.$o{search}.'%%', 1..3 ] ) : (),
    $o{char} ? (
      'LOWER(SUBSTR(pr.name, 1, 1)) = ?' => $o{char} ) : (),
    defined $o{char} && !$o{char} ? (
      '(ASCII(pr.name) < 97 OR ASCII(pr.name) > 122) AND (ASCII(pr.name) < 65 OR ASCII(pr.name) > 90)' => 1 ) : (),
    $o{rev} ? (
      'c.rev = ?' => $o{rev} ) : (),
  );

  my @join;
  push @join, $o{rev} ? 'JOIN producers p ON p.id = pr.pid' : 'JOIN producers p ON pr.id = p.latest';
  push @join, 'JOIN changes c ON c.id = pr.id' if $o{what} =~ /changes/ || $o{rev};
  push @join, 'JOIN users u ON u.id = c.requester' if $o{what} =~ /changes/;
  push @join, 'JOIN relgraphs pg ON pg.id = p.rgraph' if $o{what} =~ /relgraph/;

  my $select = 'p.id, pr.type, pr.name, pr.original, pr.lang, pr.id AS cid, p.rgraph';
  $select .= ', pr.desc, pr.alias, pr.website, p.hidden, p.locked' if $o{what} =~ /extended/;
  $select .= q|, extract('epoch' from c.added) as added, c.requester, c.comments, p.latest, pr.id AS cid, u.username, c.rev| if $o{what} =~ /changes/;
  $select .= ', pg.svg' if $o{what} =~ /relgraph/;

  my($r, $np) = $self->dbPage(\%o, q|
    SELECT !s
      FROM producers_rev pr
      !s
      !W
      ORDER BY pr.name ASC|,
    $select, join(' ', @join), \%where,
  );

  if(@$r && $o{what} =~ /vn/) {
    my %r = map {
      $r->[$_]{vn} = [];
      ($r->[$_]{id}, $_)
    } 0..$#$r;

    push @{$r->[$r{$_->{pid}}]{vn}}, $_ for (@{$self->dbAll(q|
      SELECT MAX(vp.pid) AS pid, v.id, MAX(vr.title) AS title, MAX(vr.original) AS original, MIN(rr.released) AS date,
          MAX(CASE WHEN vp.developer = true THEN 1 ELSE 0 END) AS developer, MAX(CASE WHEN vp.publisher = true THEN 1 ELSE 0 END) AS publisher
        FROM releases_producers vp
        JOIN releases_rev rr ON rr.id = vp.rid
        JOIN releases r ON r.latest = rr.id
        JOIN releases_vn rv ON rv.rid = rr.id
        JOIN vn v ON v.id = rv.vid
        JOIN vn_rev vr ON vr.id = v.latest
        WHERE vp.pid IN(!l)
          AND v.hidden = FALSE
          AND r.hidden = FALSE
        GROUP BY v.id
        ORDER BY date|,
      [ keys %r ]
    )});
  }

  if(@$r && $o{what} =~ /relations/) {
    my %r = map {
      $r->[$_]{relations} = [];
      ($r->[$_]{cid}, $_)
    } 0..$#$r;

    push @{$r->[$r{$_->{pid1}}]{relations}}, $_ for(@{$self->dbAll(q|
      SELECT rel.pid1, rel.pid2 AS id, rel.relation, pr.name, pr.original
        FROM producers_relations rel
        JOIN producers p ON rel.pid2 = p.id
        JOIN producers_rev pr ON p.latest = pr.id
        WHERE rel.pid1 IN(!l)|,
      [ keys %r ]
    )});
  }

  return wantarray ? ($r, $np) : $r;
}


# arguments: id, %options ->( editsum uid + insert_rev )
# returns: ( local revision, global revision )
sub dbProducerEdit {
  my($self, $pid, %o) = @_;
  my($rev, $cid) = $self->dbRevisionInsert('p', $pid, $o{editsum}, $o{uid});
  insert_rev($self, $cid, $pid, \%o);
  return ($rev, $cid);
}


# arguments: %options ->( editsum uid + insert_rev )
# returns: ( item id, global revision )
sub dbProducerAdd {
  my($self, %o) = @_;
  my($pid, $cid) = $self->dbItemInsert('p', $o{editsum}, $o{uid});
  insert_rev($self, $cid, $pid, \%o);
  return ($pid, $cid);
}


# helper function, inserts a producer revision
# Arguments: global revision, item id, { columns in producers_rev }, relations
sub insert_rev {
  my($self, $cid, $pid, $o) = @_;
  $self->dbExec(q|
    INSERT INTO producers_rev (id, pid, name, original, website, type, lang, "desc", alias)
      VALUES (!l)|,
    [ $cid, $pid, @$o{qw| name original website type lang desc alias|} ]
  );

  $self->dbExec(q|
    INSERT INTO producers_relations (pid1, pid2, relation)
      VALUES (?, ?, ?)|,
    $cid, $_->[1], $_->[0]
  ) for (@{$o->{relations}});
}


1;
