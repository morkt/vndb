
package VNDB::DB::Search;

use strict;
use warnings;
use Exporter 'import';
use TUWF qw(sqlprint);

our @EXPORT = qw|dbPostSearch|;


# Options: search uid type headline weight phrase results page what
# What: thread
sub dbPostSearch {
  my($self, %o) = @_;
  $o{results} ||= 10;
  $o{page}    ||= 1;
  $o{what}    ||= '';
  $o{phrase}  =~ s/[%_\\]/\\$&/g if $o{phrase};

  # highlight options, see
  # http://www.postgresql.org/docs/9.1/static/textsearch-controls.html#TEXTSEARCH-HEADLINE
  my %h = ( MaxFragments => 1, $o{headline} ? %{$o{headline}} : () );
  my $msg_hl = join(',', map("$_=$h{$_}", keys %h));
  # headline settings for thread titles
  $h{MaxFragments} = 0;
  $h{ShortWord} = 0;
  $h{MinWords} = 15;
  $h{MaxWords} = 40;
  my $title_hl = join(',', map("$_=$h{$_}", keys %h));

  # default weight values
  # note: setting weight to zero would still include matching entries, albeit
  # with a zero rank.  to exclude keywords labeled with a certain weight
  # completely, tsquery string should be modified accordingly. see
  # http://www.postgresql.org/docs/9.1/static/textsearch-controls.html#TEXTSEARCH-PARSING-QUERIES
  # alternatively: add 'WHERE rank > 0' clause?
  my %w = ( A => 1.0, B => 0.1, C => 0.4, D => 0.5, $o{weight} ? %{$o{weight}} : () );
  my $weight = '{'.join(',', @w{qw(D C B A)}).'}';
  # suggested weights allocation:
  # A: thread title
  # B: quoted text
  # C: spoiler
  # D: message text
  # weights are assigned to a message by database trigger 'update_board_ts()'
  # whenever message is being indexed.

  my %where = (
    'NOT hidden' => 1,
    'tsmsg @@ q' => 1,
    $o{what} =~ /thread/ ?
      ( 'num = 1' => 1 ) : (),
    $o{uid} ? ref $o{uid} ?
      ( 'uid IN(!l)' => [$o{uid}] ) :
      ( 'uid = ?' => $o{uid} ) : (),
    $o{type} ? ref $o{type} ?
      ( 'tid IN(SELECT tid FROM threads_boards WHERE type IN(!l))' => [$o{type}] ) :
      ( 'tid IN(SELECT tid FROM threads_boards WHERE type = ?)' => $o{type} ) : (),
  );

  # filter applied to the set of rows selected by the subquery
  my %filter = (
    $o{phrase} ? $o{what} =~ /thread/ ?
      ('t.title ILIKE ?' => '%'.$o{phrase}.'%') :
      ('msg ILIKE ?' => '%'.$o{phrase}.'%') : (),
  );

  my @select = (
    qw|tid num uid u.username rank msg|,
    q|extract('epoch' FROM tp.date) AS date|,
  );
  my $order = 'ORDER BY rank DESC';

  my($subquery, @sqp) = sqlprint(q|
    SELECT tid, num, msg, uid, date, q, ts_rank_cd(?, tsmsg, q) AS rank
      FROM threads_posts, to_tsquery(?) q
      !W
      !s
      LIMIT ? OFFSET ?|,
    $weight, $o{search}, \%where, $order, $o{results}+1, $o{results}*($o{page}-1));

  # offset/limit are specified within subquery, so can't use dbPage function
  # here.  ts_headline is rather expensive and shouldn't be used on every row,
  # hence a subquery.
  # order clause should be applied twice, to both subquery and an outer query.
  my $r = $self->dbAll(qq|
    SELECT !s,
        CASE num
        WHEN 1 THEN ts_headline(t.title, q, ?)
               ELSE t.title END AS title,
        ts_headline(strip_bb_tags(msg), q, ?) AS headline
      FROM ($subquery) tp
      JOIN threads t ON t.id = tid
      JOIN users u ON u.id = tp.uid
      !W
      !s|,
    join(', ', @select), $title_hl, $msg_hl, @sqp, \%filter, $order);
  my $np = $#$r == $o{results};
  pop @$r if $np;

  return wantarray ? ($r, $np) : $r;
}


1;

