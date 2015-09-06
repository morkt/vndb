
package VNDB::DB::Discussions;

use strict;
use warnings;
use Exporter 'import';

our @EXPORT = qw|dbThreadGet dbThreadEdit dbThreadAdd dbPostGet dbPostEdit dbPostAdd dbThreadCount|;


# Options: id, type, iid, results, page, what, notusers, sort, reverse
# What: boards, boardtitles, firstpost, lastpost
# Sort: id lastpost
sub dbThreadGet {
  my($self, %o) = @_;
  $o{results} ||= 50;
  $o{page} ||= 1;
  $o{what} ||= '';

  my %where = (
    $o{id} ? (
      't.id = ?' => $o{id} ) : (),
    !$o{id} ? (
      't.hidden = FALSE' => 0 ) : (),
    $o{type} && !$o{iid} ? (
      't.id IN(SELECT tid FROM threads_boards WHERE type = ?)' => $o{type} ) : (),
    $o{type} && $o{iid} ? (
      'tb.type = ?' => $o{type}, 'tb.iid = ?' => $o{iid} ) : (),
    $o{notusers} ? (
      't.id NOT IN(SELECT tid FROM threads_boards WHERE type = \'u\')' => 1) : (),
  );

  my @select = (
    qw|t.id t.title t.count t.locked t.hidden|,
    $o{what} =~ /firstpost/ ? ('tpf.uid AS fuid', q|EXTRACT('epoch' from tpf.date) AS fdate|, 'uf.username AS fusername') : (),
    $o{what} =~ /lastpost/  ? ('tpl.uid AS luid', q|EXTRACT('epoch' from tpl.date) AS ldate|, 'ul.username AS lusername') : (),
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
      'JOIN threads_boards tb ON tb.tid = t.id' : (),
  );

  my $order = sprintf {
    id       => 't.id %s',
    lastpost => 'tpl.date %s',
  }->{ $o{sort}||'id' }, $o{reverse} ? 'DESC' : 'ASC';

  my($r, $np) = $self->dbPage(\%o, q|
    SELECT !s
      FROM threads t
      !s
      !W
      ORDER BY !s|,
    join(', ', @select), join(' ', @join), \%where, $order
  );

  if($o{what} =~ /(boards|boardtitles)/ && $#$r >= 0) {
    my %r = map {
      $r->[$_]{boards} = [];
      ($r->[$_]{id}, $_)
    } 0..$#$r;

    if($o{what} =~ /boards/) {
      push(@{$r->[$r{$_->{tid}}]{boards}}, [ $_->{type}, $_->{iid} ]) for (@{$self->dbAll(q|
        SELECT tid, type, iid
          FROM threads_boards
          WHERE tid IN(!l)|,
        [ keys %r ]
      )});
    }
    if($o{what} =~ /boardtitles/) {
      push(@{$r->[$r{$_->{tid}}]{boards}}, $_) for (@{$self->dbAll(q|
        SELECT tb.tid, tb.type, tb.iid, COALESCE(u.username, vr.title, pr.name) AS title, COALESCE(u.username, vr.original, pr.original) AS original
          FROM threads_boards tb
          LEFT JOIN vn v ON tb.type = 'v' AND v.id = tb.iid
          LEFT JOIN vn_rev vr ON vr.id = v.latest
          LEFT JOIN producers p ON tb.type = 'p' AND p.id = tb.iid
          LEFT JOIN producers_rev pr ON pr.id = p.latest
          LEFT JOIN users u ON tb.type = 'u' AND u.id = tb.iid
          WHERE tb.tid IN(!l)|,
        [ keys %r ]
      )});
    }
  }

  return wantarray ? ($r, $np) : $r;
}


# id, %options->( title locked hidden boards }
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

  if($o{boards}) {
    $self->dbExec('DELETE FROM threads_boards WHERE tid = ?', $id);
    $self->dbExec(q|
      INSERT INTO threads_boards (tid, type, iid)
        VALUES (?, ?, ?)|,
      $id, $_->[0], $_->[1]||0
    ) for (@{$o{boards}});
  }
}


# %options->{ title hidden locked boards }
sub dbThreadAdd {
  my($self, %o) = @_;

  my $id = $self->dbRow(q|
    INSERT INTO threads (title, hidden, locked)
      VALUES (?, ?, ?)
      RETURNING id|,
    $o{title}, $o{hidden}?1:0, $o{locked}?1:0
  )->{id};

  $self->dbExec(q|
    INSERT INTO threads_boards (tid, type, iid)
      VALUES (?, ?, ?)|,
    $id, $_->[0], $_->[1]||0
  ) for (@{$o{boards}});

  return $id;
}


# Returns thread count of a specific item board
# Arguments: type, iid
sub dbThreadCount {
  my($self, $type, $iid) = @_;
  return $self->dbRow(q|
    SELECT COUNT(*) AS cnt
      FROM threads_boards tb
      JOIN threads t ON t.id = tb.tid
      WHERE tb.type = ? AND tb.iid = ?
        AND t.hidden = FALSE|,
    $type, $iid)->{cnt};
}


# Options: tid, num, what, uid, mindate, hide, page, results, sort, reverse
# what: user thread
sub dbPostGet {
  my($self, %o) = @_;
  $o{results} ||= 50;
  $o{page} ||= 1;
  $o{what} ||= '';

  my %where = (
    $o{tid} ? (
      'tp.tid = ?' => $o{tid} ) : (),
    $o{num} ? (
      'tp.num = ?' => $o{num} ) : (),
    $o{uid} ? (
      'tp.uid = ?' => $o{uid} ) : (),
    $o{mindate} ? (
      'tp.date > to_timestamp(?)' => $o{mindate} ) : (),
    $o{hide} ? (
      'tp.hidden = FALSE' => 1 ) : (),
    $o{hide} && $o{what} =~ /thread/ ? (
      't.hidden = FALSE' => 1 ) : (),
  );

  my @select = (
    qw|tp.num tp.msg tp.hidden|, q|extract('epoch' from tp.date) as date|, q|extract('epoch' from tp.edited) as edited|,
    $o{what} =~ /user/ ? qw|tp.uid u.username| : (),
    $o{what} =~ /thread/ ? (qw|tp.tid t.title|, 't.hidden AS thread_hidden') : (),
  );
  my @join = (
    $o{what} =~ /user/ ? 'JOIN users u ON u.id = tp.uid' : (),
    $o{what} =~ /thread/ ? 'JOIN threads t ON t.id = tp.tid' : (),
  );

  my $order = sprintf {
    num  => 'tp.num %s',
    date => 'tp.date %s',
  }->{ $o{sort}||'num' }, $o{reverse} ? 'DESC' : 'ASC';

  my($r, $np) = $self->dbPage(\%o, q|
    SELECT !s
      FROM threads_posts tp
      !s
      !W
      ORDER BY !s|,
    join(', ', @select), join(' ', @join), \%where, $order
  );

  return wantarray ? ($r, $np) : $r;
}


# tid, num, %options->{ num msg hidden lastmod }
sub dbPostEdit {
  my($self, $tid, $num, %o) = @_;

  my %set = (
    'msg = ?' => $o{msg},
    'edited = to_timestamp(?)' => $o{lastmod},
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

  my $num = $self->dbRow('SELECT num FROM threads_posts WHERE tid = ? ORDER BY num DESC LIMIT 1', $tid)->{num};
  $num = $num ? $num+1 : 1;
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

