
package VNDB::DB::Discussions;

use strict;
use warnings;
use Exporter 'import';

our @EXPORT = qw|dbThreadGet dbThreadEdit dbThreadAdd dbPostGet dbPostEdit dbPostAdd dbThreadCount dbPollStats dbPollVote|;


# Options: id, type, iid, results, page, what, notusers, search, sort, reverse
# What: boards, boardtitles, firstpost, lastpost, poll
# Sort: id lastpost
sub dbThreadGet {
  my($self, %o) = @_;
  $o{results} ||= 50;
  $o{page} ||= 1;
  $o{what} ||= '';

  my @where = (
    $o{id} ? (
      't.id = ?' => $o{id} ) : (),
    !$o{id} ? (
      't.hidden = FALSE' => 0 ) : (),
    $o{type} && !$o{iid} ? (
      'EXISTS(SELECT 1 FROM threads_boards WHERE tid = t.id AND type IN(!l))' => [ ref $o{type} ? $o{type} : [ $o{type} ] ] ) : (),
    $o{type} && $o{iid} ? (
      'tb.type = ?' => $o{type}, 'tb.iid = ?' => $o{iid} ) : (),
    $o{notusers} ? (
      'NOT EXISTS(SELECT 1 FROM threads_boards WHERE type = \'u\' AND tid = t.id)' => 1) : (),
  );

  if($o{search}) {
    for (split /[ -,._]/, $o{search}) {
      s/%//g;
      push @where, 't.title ilike ?', "%$_%" if length($_) > 0;
    }
  }

  my @select = (
    qw|t.id t.title t.count t.locked t.hidden|, 't.poll_question IS NOT NULL AS haspoll',
    $o{what} =~ /lastpost/  ? ('tpl.uid AS luid', q|EXTRACT('epoch' from tpl.date) AS ldate|, 'ul.username AS lusername') : (),
    $o{what} =~ /poll/      ? (qw|t.poll_question t.poll_max_options t.poll_preview t.poll_recast|) : (),
  );

  my @join = (
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
    join(', ', @select), join(' ', @join), \@where, $order
  );

  if($o{what} =~ /(boards|boardtitles|poll)/ && $#$r >= 0) {
    my %r = map {
      $r->[$_]{boards} = [];
      $r->[$_]{poll_options} = [];
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

    if($o{what} =~ /poll/) {
      push(@{$r->[$r{$_->{tid}}]{poll_options}}, [ $_->{id}, $_->{option} ]) for (@{$self->dbAll(q|
        SELECT tid, id, option
          FROM threads_poll_options
          WHERE tid IN(!l)|,
        [ keys %r ]
      )});
    }

    if($o{what} =~ /firstpost/) {
      do { my $x = $r->[$r{$_->{tid}}]; $x->{fuid} = $_->{uid}; $x->{fdate} = $_->{date}; $x->{fusername} = $_->{username} } for (@{$self->dbAll(q|
        SELECT tpf.tid, tpf.uid, EXTRACT('epoch' from tpf.date) AS date, uf.username
          FROM threads_posts tpf
          JOIN users uf ON tpf.uid = uf.id
          WHERE tpf.num = 1 AND tpf.tid IN(!l)|,
        [ keys %r ]
      )});
    }

    if($o{what} =~ /boardtitles/) {
      push(@{$r->[$r{$_->{tid}}]{boards}}, $_) for (@{$self->dbAll(q|
        SELECT tb.tid, tb.type, tb.iid, COALESCE(u.username, v.title, p.name) AS title, COALESCE(u.username, v.original, p.original) AS original
          FROM threads_boards tb
          LEFT JOIN vn v ON tb.type = 'v' AND v.id = tb.iid
          LEFT JOIN producers p ON tb.type = 'p' AND p.id = tb.iid
          LEFT JOIN users u ON tb.type = 'u' AND u.id = tb.iid
          WHERE tb.tid IN(!l)|,
        [ keys %r ]
      )});
    }
  }

  return wantarray ? ($r, $np) : $r;
}


# id, %options->( title locked hidden boards poll_question poll_max_options poll_preview poll_recast poll_options }
# The poll_{question,options,max_options} fields should not be set when there
# are no changes to the poll info. Either all or none of these fields should be
# set.
sub dbThreadEdit {
  my($self, $id, %o) = @_;

  my %set = (
    'title = ?' => $o{title},
    'locked = ?' => $o{locked}?1:0,
    'hidden = ?' => $o{hidden}?1:0,
    'poll_preview = ?' => $o{poll_preview}?1:0,
    'poll_recast = ?' => $o{poll_recast}?1:0,
    exists $o{poll_question} ? (
      'poll_question = ?' => $o{poll_question}||undef,
      'poll_max_options = ?' => $o{poll_max_options}||1,
    ) : (),
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

  if(exists $o{poll_question}) {
    $self->dbExec('DELETE FROM threads_poll_options WHERE tid = ?', $id);
    $self->dbExec(q|
      INSERT INTO threads_poll_options (tid, option)
        VALUES (?, ?)|,
      $id, $_
    ) for (@{$o{poll_options}});
  }
}


# %options->{ title hidden locked boards poll_stuff }
sub dbThreadAdd {
  my($self, %o) = @_;

  my $id = $self->dbRow(q|
    INSERT INTO threads (title, hidden, locked, poll_question, poll_max_options, poll_preview, poll_recast)
      VALUES (?, ?, ?, ?, ?, ?, ?)
      RETURNING id|,
    $o{title}, $o{hidden}?1:0, $o{locked}?1:0, $o{poll_question}||undef, $o{poll_max_options}||1, $o{poll_preview}?1:0, $o{poll_recast}?1:0
  )->{id};

  $self->dbExec(q|
    INSERT INTO threads_boards (tid, type, iid)
      VALUES (?, ?, ?)|,
    $id, $_->[0], $_->[1]||0
  ) for (@{$o{boards}});

  $self->dbExec(q|
    INSERT INTO threads_poll_options (tid, option)
      VALUES (?, ?)|,
    $id, $_
  ) for ($o{poll_question} ? @{$o{poll_options}} : ());

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


# Options: tid, num, what, uid, mindate, hide, search, type, page, results, sort, reverse
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
    $o{search} ? (
      'bb_tsvector(msg) @@ to_tsquery(?)' => $o{search}) : (),
    $o{type} ? (
      'tp.tid IN(SELECT tid FROM threads_boards WHERE type IN(!l))' => [ ref $o{type} ? $o{type} : [ $o{type} ] ] ) : (),
  );

  my @select = (
    qw|tp.tid tp.num tp.hidden|, q|extract('epoch' from tp.date) as date|, q|extract('epoch' from tp.edited) as edited|,
    $o{search} ? () : 'tp.msg',
    $o{what} =~ /user/ ? qw|tp.uid u.username| : (),
    $o{what} =~ /thread/ ? ('t.title', 't.hidden AS thread_hidden') : (),
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

  # Get headlines in a separate query
  if($o{search} && @$r) {
    my %r = map {
      ($r->[$_]{tid}.'.'.$r->[$_]{num}, $_)
    } 0..$#$r;
    my $where = join ' or ', ('(tid = ? and num = ?)')x@$r;
    my @where = map +($_->{tid},$_->{num}), @$r;
    my $h = join ',', map "$_=$o{headline}{$_}", $o{headline} ? keys %{$o{headline}} : ();

    $r->[$r{$_->{tid}.'.'.$_->{num}}]{headline} = $_->{headline} for (@{$self->dbAll(qq|
      SELECT tid, num, ts_headline('english', strip_bb_tags(strip_spoilers(msg)), to_tsquery(?), ?) as headline
        FROM threads_posts
        WHERE $where|,
      $o{search}, $h, @where
    )});
  }

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


# Args: tid
# Returns: num_users, poll_stats, user_voted_options
sub dbPollStats {
  my($self, $tid) = @_;
  my $uid = $self->authInfo->{id};

  my $num_users = $self->dbRow('SELECT COUNT(DISTINCT uid) AS votes FROM threads_poll_votes WHERE tid = ?', $tid)->{votes} || 0;

  my $stats = !$num_users ? {} : { map +($_->{optid}, $_->{votes}), @{$self->dbAll(
    'SELECT optid, COUNT(optid) AS votes FROM threads_poll_votes WHERE tid = ? GROUP BY optid', $tid
  )} };

  my $user = !$num_users || !$uid ? [] : [
    map $_->{optid}, @{$self->dbAll('SELECT optid FROM threads_poll_votes WHERE tid = ? AND uid = ?', $tid, $uid)}
  ];

  return $num_users, $stats, $user;
}


sub dbPollVote {
  my($self, $tid, $uid, @opts) = @_;

  $self->dbExec('DELETE FROM threads_poll_votes WHERE tid = ? AND uid = ?', $tid, $uid);
  $self->dbExec('INSERT INTO threads_poll_votes (tid, uid, optid) VALUES (?, ?, ?)',
    $tid, $uid, $_) for @opts;
}

1;
