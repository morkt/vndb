
package VNDB::DB::Discussions;

use strict;
use warnings;
use Exporter 'import';

our @EXPORT = qw|dbThreadGet dbThreadEdit dbThreadAdd dbPostGet dbPostEdit dbPostAdd|;


# Options: id, type, iid, results, page, what
# What: tags, tagtitles, firstpost, lastpost
sub dbThreadGet {
  my($self, %o) = @_;
  $o{results} ||= 50;
  $o{page} ||= 1;
  $o{what} ||= '';
  $o{order} ||= 't.id DESC';

  my %where = (
    $o{id} ? (
      't.id = ?' => $o{id} ) : (),
    !$o{id} ? (
      't.hidden = FALSE' => 0 ) : (),
    $o{type} && !$o{iid} ? (
      't.id IN(SELECT tid FROM threads_tags WHERE type = ?)' => $o{type} ) : (),
    $o{type} && $o{iid} ? (
      'tt.type = ?' => $o{type}, 'tt.iid = ?' => $o{iid} ) : (),
  );

  my @select = (
    qw|t.id t.title t.count t.locked t.hidden|,
    $o{what} =~ /firstpost/ ? ('tpf.uid AS fuid', 'tpf.date AS fdate', 'uf.username AS fusername') : (),
    $o{what} =~ /lastpost/  ? ('tpl.uid AS luid', 'tpl.date AS ldate', 'ul.username AS lusername') : (),
  );

  my @join = (
    $o{what} =~ /firstpost/ ? (
      'JOIN threads_posts tpf ON tpf.tid = t.id AND tpf.num = 1',
      'JOIN users uf ON uf.id = tpf.uid'
    ) : (),
    $o{what} =~ /lastpost/ ? (
      'JOIN threads_posts tpl ON tpl.tid = t.id AND tpl.num = t.count',
      'JOIN users ul ON ul.id = tpl.uid'
    ) : (),
    $o{type} && $o{iid} ?
      'JOIN threads_tags tt ON tt.tid = t.id' : (),
  );

  my($r, $np) = $self->dbPage(\%o, q|
    SELECT !s
      FROM threads t
      !s
      !W
      ORDER BY !s|,
    join(', ', @select), join(' ', @join), \%where, $o{order}
  );

  if($o{what} =~ /(tags|tagtitles)/ && $#$r >= 0) {
    my %r = map {
      $r->[$_]{tags} = [];
      ($r->[$_]{id}, $_)
    } 0..$#$r;

    if($o{what} =~ /tags/) {
      ($_->{type}=~s/ +//||1) && push(@{$r->[$r{$_->{tid}}]{tags}}, [ $_->{type}, $_->{iid} ]) for (@{$self->dbAll(q|
        SELECT tid, type, iid
          FROM threads_tags
          WHERE tid IN(!l)|,
        [ keys %r ]
      )});
    }
    if($o{what} =~ /tagtitles/) {
      ($_->{type}=~s/ +//||1) && push(@{$r->[$r{$_->{tid}}]{tags}}, $_) for (@{$self->dbAll(q|
        SELECT tt.tid, tt.type, tt.iid, COALESCE(u.username, vr.title, pr.name) AS title, COALESCE(u.username, vr.original, pr.original) AS original
          FROM threads_tags tt
          LEFT JOIN vn v ON tt.type = 'v' AND v.id = tt.iid
          LEFT JOIN vn_rev vr ON vr.id = v.latest
          LEFT JOIN producers p ON tt.type = 'p' AND p.id = tt.iid
          LEFT JOIN producers_rev pr ON pr.id = p.latest
          LEFT JOIN users u ON tt.type = 'u' AND u.id = tt.iid
          WHERE tt.tid IN(!l)|,
        [ keys %r ]
      )});
    }
  }

  return wantarray ? ($r, $np) : $r;
}


# id, %options->( title locked hidden tags }
sub dbThreadEdit {
  my($self, $id, %o) = @_;

  my %set = (
    'title = ?' => $o{title},
    'locked = ?' => $o{locked}?1:0,
    'hidden = ?' => $o{hidden}?1:0,
  );

  $self->dbExec(q|
    UPDATE threads
      !H
      WHERE id = ?|,
    \%set, $id);

  if($o{tags}) {
    $self->dbExec('DELETE FROM threads_tags WHERE tid = ?', $id);
    $self->dbExec(q|
      INSERT INTO threads_tags (tid, type, iid)
        VALUES (?, ?, ?)|,
      $id, $_->[0], $_->[1]||0
    ) for (@{$o{tags}});
  }
}


# %options->{ title hidden locked tags }
sub dbThreadAdd { 
  my($self, %o) = @_;

  my $id = $self->dbRow(q|
    INSERT INTO threads (title, hidden, locked)
      VALUES (?, ?, ?)
      RETURNING id|,
    $o{title}, $o{hidden}?1:0, $o{locked}?1:0
  )->{id};

  $self->dbExec(q|
    INSERT INTO threads_tags (tid, type, iid)
      VALUES (?, ?, ?)|,
    $id, $_->[0], $_->[1]||0
  ) for (@{$o{tags}});

  return $id;
}


# Options: tid, num, what, page, results
sub dbPostGet {
  my($self, %o) = @_;
  $o{results} ||= 50;
  $o{page} ||= 1;

  my %where = (
    'tp.tid = ?' => $o{tid},
    $o{num} ? (
      'tp.num = ?' => $o{num} ) : (),
  );

  my($r, $np) = $self->dbPage(\%o, q|
    SELECT tp.num, tp.date, tp.edited, tp.msg, tp.hidden, tp.uid, u.username
      FROM threads_posts tp
      JOIN users u ON u.id = tp.uid
      !W
      ORDER BY tp.num ASC|,
    \%where,
  );

  return wantarray ? ($r, $np) : $r;
}


# tid, num, %options->{ num msg hidden lastmod }
sub dbPostEdit { 
  my($self, $tid, $num, %o) = @_;

  my %set = (
    'msg = ?' => $o{msg},
    'edited = ?' => $o{lastmod},
    'hidden = ?' => $o{hidden}?1:0,
  );

  $self->dbExec(q|
    UPDATE threads_posts
      !H
      WHERE tid = ?
      AND num = ?|,
    \%set, $tid, $num
  );
}


# tid, %options->{ uid msg }
sub dbPostAdd {
  my($self, $tid, %o) = @_;

  my $num ||= $self->dbRow('SELECT num FROM threads_posts WHERE tid = ? ORDER BY num DESC LIMIT 1', $tid)->{num}+1;
  $o{uid} ||= $self->authInfo->{id};

  $self->dbExec(q|
    INSERT INTO threads_posts (tid, num, uid, msg)
      VALUES(?, ?, ?, ?)|,
    $tid, $num, @o{qw| uid msg |}
  );
  $self->dbExec(q|
    UPDATE threads
      SET count = count+1
      WHERE id = ?|,
    $tid);

  return $num;
}


1;

