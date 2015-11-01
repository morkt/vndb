
#
#  Multi::RG  -  Relation graph generator
#

package Multi::RG;

use strict;
use warnings;
use Multi::Core;
use AnyEvent::Util;
use Encode 'encode_utf8';
use XML::Parser;
use TUWF::XML;


my %O = (
  font => 'Arial',
  fsize => [ 9, 7, 10 ], # nodes, edges, node_title
  dot => '/usr/bin/dot',
  check_delay => 3600,
);


my %C;


sub run {
  shift;
  %O = (%O, @_);
  push_watcher schedule 0, $O{check_delay}, \&check_rg;
  push_watcher pg->listen(relgraph => on_notify => \&check_rg);
}


sub check_rg {
  # Only process one at a time, we don't know how many other entries the
  # current graph will affect.
  return if $C{id};

  AE::log debug => 'Checking for new graphs to create.';
  pg_cmd q|
      SELECT 'v', v.id FROM vn v JOIN vn_relations vr ON vr.id = v.id WHERE v.rgraph IS NULL AND v.hidden = FALSE
    UNION
      SELECT 'p', p.id FROM producers p JOIN producers_relations pr ON pr.id = p.id WHERE p.rgraph IS NULL AND p.hidden = FALSE
    LIMIT 1|, undef, \&creategraph;
}


sub creategraph {
  my($res, $time) = @_;
  return if pg_expect $res, 1 or !$res->rows;

  %C = (
    start => scalar AE::time(),
    type  => scalar $res->value(0, 0),
    id    => scalar $res->value(0, 1),
    sqlt  => $time,
    rels  => {}, # relations (key=id1-id2, value=[relation,official])
    nodes => {}, # nodes (key=id, value= 0:found, 1:processed)
  );

  AE::log debug => "Generating graph for $C{type}$C{id}";
  getrelid($C{id});
}


sub getrelid {
  my $id = shift;
  AE::log debug => "Fetching relations for $C{type}$id";
  pg_cmd $C{type} eq 'v'
    ? 'SELECT vid, relation, official FROM vn_relations WHERE id = $1'
    : 'SELECT pid, relation FROM producers_relations WHERE id = $1',
    [ $id ], sub { getrel($id, @_) };
}


sub getrel { # id, res, time
  my($id, $res, $time) = @_;
  return if pg_expect $res, 1, $id;

  $C{sqlt} += $time;
  $C{nodes}{$id} = 1;

  for($res->rows) {
    my($xid, $xrel, $xoff) = @$_;
    $xoff = 0 if $xoff && $xoff =~ /^f/;

    $C{rels}{$id.'-'.$xid} = [ $VNDB::S{ $C{type} eq 'v' ? 'vn_relations' : 'prod_relations' }{$xrel}[1], $xoff ] if $id < $xid;
    $C{rels}{$xid.'-'.$id} = [ $xrel, $xoff ] if $id > $xid;

    # New node? Get its relations too.
    if(!exists $C{nodes}{$xid}) {
      $C{nodes}{$xid} = 0;
      getrelid $xid;
    }
  }

  # Wait for other node relations to come in.
  return if grep !$_, values %{$C{nodes}};

  # do we have all relations now? get node info
  my @ids = keys %{$C{nodes}};
  my $ids = join(', ', map '$'.$_, 1..@ids);
  AE::log debug => "Fetching node information for $C{type}:".join ', ', @ids;
  pg_cmd $C{type} eq 'v'
    ? "SELECT id, title, c_released AS date, array_to_string(c_languages, '/') AS lang FROM vn WHERE id IN($ids) ORDER BY c_released"
    : "SELECT id, name, lang, type FROM producers WHERE id IN($ids) ORDER BY name",
    [ @ids ], \&builddot;
}


sub builddot {
  my($res, $time) = @_;
  return if pg_expect $res, 1, $C{id};
  $C{sqlt} += $time;

  my $gv =
    qq|graph rgraph {\n|.
    qq|\tnode [ fontname = "$O{font}", shape = "plaintext",|.
      qq| fontsize = $O{fsize}[0], fontcolor = "#333333", color = "#111111" ]\n|.
    qq|\tedge [ labeldistance = 2.5, labelangle = -20, labeljust = 1, minlen = 2, dir = "both",|.
      qq| fontname = $O{font}, fontsize = $O{fsize}[1], arrowsize = 0.7, color = "#111111", fontcolor = "#333333" ]\n|;

  # insert all nodes and relations
  my %nodes = map +($_->{id}, $_), $res->rowsAsHashes;
  $gv .= $C{type} eq 'v' ? gv_vnnode($nodes{$_}) : gv_prodnode($nodes{$_}) for keys %nodes;
  $gv .= $C{type} eq 'v' ? gv_vnrels($C{rels}, \%nodes) : gv_prodrels($C{rels}, \%nodes);

  $gv .= "}\n";

  rundot($gv);
}


sub gv_vnnode {
  my $n = shift;

  my $date = sprintf '%08d', $n->{date};
  $date =~ s{^([0-9]{4})([0-9]{2})([0-9]{2})$}{
      $1 ==    0 ? 'unknown'
    : $1 == 9999 ? 'TBA'
    : $2 ==   99 ? $1
    : $3 ==   99 ? "$1-$2" : "$1-$2-$3"
  }e;

  my $title = $n->{title};
  $title = substr($title, 0, 27).'...' if length($title) > 30;
  $title =~ s/&/&amp;/g;
  $title =~ s/>/&gt;/g;
  $title =~ s/</&lt;/g;

  my $tooltip = $n->{title};
  $tooltip =~ s/\\/\\\\/g;
  $tooltip =~ s/"/\\"/g;

  return sprintf
    qq|\tv%d [ id = "node_v%1\$d", URL = "/v%1\$d", tooltip = "%s", label=<|.
      q|<TABLE CELLSPACING="0" CELLPADDING="1" BORDER="0" CELLBORDER="1" BGCOLOR="#222222">|.
        q|<TR><TD COLSPAN="2" ALIGN="CENTER" CELLPADDING="2"><FONT POINT-SIZE="%d">  %s  </FONT></TD></TR>|.
        q|<TR><TD> %s </TD><TD> %s </TD></TR>|.
      qq|</TABLE>> ]\n|,
    $n->{id}, encode_utf8($tooltip), $O{fsize}[2], encode_utf8($title), $date, $n->{lang}||'N/A';
}


sub gv_vnrels {
  my($rels, $vns) = @_;
  my $r = '';

  # @rels = ([ vid1, vid2, relation, official, date1, date2 ], ..), for easier processing
  my @rels = map {
    /^([0-9]+)-([0-9]+)$/;
    [ $1, $2, @{$rels->{$_}}, $vns->{$1}{date}, $vns->{$2}{date} ]
  } keys %$rels;

  # insert all edges, ordered by release date
  for (sort { ($a->[4]>$a->[5]?$a->[5]:$a->[4]) <=> ($b->[4]>$b->[5]?$b->[5]:$b->[4]) } @rels) {
    # [older game] -> [newer game]
    if($_->[5] > $_->[4]) {
      ($_->[0], $_->[1]) = ($_->[1], $_->[0]);
      $_->[2] = $VNDB::S{vn_relations}{$_->[2]}[1];
    }
    my $rev = $VNDB::S{vn_relations}{$_->[2]}[1];
    my $style = $_->[3] ? '' : ', style="dotted"';
    my $label = $rev ne $_->[2]
      ? qq|headlabel = "\$____vnrel_$_->[2]____\$" taillabel = "\$____vnrel_${rev}____\$" $style|
      : qq|label = "\$____vnrel_$_->[2]____\$" $style|;
    $r .= qq|\tv$$_[1] -- v$$_[0] [ $label ]\n|;
  }
  $r;
}


sub gv_prodnode {
  my $n = shift;

  my $name = $n->{name};
  $name = substr($name, 0, 27).'...' if length($name) > 30;
  $name =~ s/&/&amp;/g;
  $name =~ s/>/&gt;/g;
  $name =~ s/</&lt;/g;

  my $tooltip = $n->{name};
  $tooltip =~ s/\\/\\\\/g;
  $tooltip =~ s/"/\\"/g;

  return sprintf
    qq|\tp%d [ id = "node_p%1\$d", URL = "/p%1\$d", tooltip = "%s", label=<|.
      q|<TABLE CELLSPACING="0" CELLPADDING="1" BORDER="0" CELLBORDER="1" BGCOLOR="#222222">|.
        q|<TR><TD COLSPAN="2" ALIGN="CENTER" CELLPADDING="2"><FONT POINT-SIZE="%d">  %s  </FONT></TD></TR>|.
        q|<TR><TD ALIGN="CENTER"> $_lang_%s_$ </TD><TD ALIGN="CENTER"> $_ptype_%s_$ </TD></TR>|.
      qq|</TABLE>> ]\n|,
    $n->{id}, encode_utf8($tooltip), $O{fsize}[2], encode_utf8($name), $n->{lang}, $n->{type};
}


sub gv_prodrels {
  my($rels, $prods) = @_;
  my $r = '';

  for (keys %$rels) {
    /^([0-9]+)-([0-9]+)$/;
    my $p1 = $prods->{$1};
    my $p2 = $prods->{$2};

    my $rev = $VNDB::S{prod_relations}{$rels->{$_}[0]}[1];
    my $label = $rev ne $rels->{$_}[0]
      ? qq|headlabel = "\$____prodrel_${rev}____\$", taillabel = "\$____prodrel_$rels->{$_}[0]____\$"|
      : qq|label = "\$____prodrel_$rels->{$_}[0]____\$"|;
    $r .= qq|\tp$p1->{id} -- p$p2->{id} [ $label ]\n|;
  }
  $r;
}


sub rundot {
  my $gv = shift;
  AE::log trace => "Running graphviz, dot:\n$gv";

  my $svg;
  my $cv = run_cmd [ $O{dot}, '-Tsvg' ],
    '<', \$gv,
    '>', \$svg,
    '2>', sub { AE::log warn => "STDERR from graphviz: $_[0]" if $_[0]; };

  $cv->cb(sub {
    return AE::log warn => 'graphviz failed' if shift->recv;
    processgraph($svg);
  });
}


sub processgraph {
  my $data = shift;

  # Before saving the SVG output, we'll modify it a little:
  # - Remove comments
  # - Remove <title> elements (unused)
  # - Remove id attributes (unused)
  # - Remove first <polygon> element (emulates the background color)
  # - Replace stroke and fill attributes with classes (so that coloring is done in CSS)
  my $svg = '';
  my $w = TUWF::XML->new(write => sub { $svg .= shift });
  my $p = XML::Parser->new;
  $p->setHandlers(
    Start => sub {
      my($expat, $el, %attr) = @_;
      return if $el eq 'title' || $expat->in_element('title');
      return if $el eq 'polygon' && $expat->depth == 2;

      $attr{class} = 'border' if $attr{stroke} && $attr{stroke} eq '#111111';
      $attr{class} = 'nodebg' if $attr{fill} && $attr{fill} eq '#222222';

      delete @attr{qw|stroke fill|};
      delete $attr{id} if $attr{id} && $attr{id} !~ /^node_[vp]\d+$/;
      $w->tag($el, %attr, $el eq 'path' || $el eq 'polygon' ? undef : ());
    },
    End => sub {
      my($expat, $el) = @_;
      return if $el eq 'title' || $expat->in_element('title');
      return if $el eq 'polygon' && $expat->depth == 2;
      $w->end($el) if $el ne 'path' && $el ne 'polygon';
    },
    Char => sub {
      my($expat, $str) = @_;
      return if $expat->in_element('title');
      $w->txt($str) if $str !~ /^[\s\t\r\n]*$/s;
    }
  );
  $p->parsestring($data);

  # save the processed SVG in the database and fetch graph ID
  AE::log trace => "Processed SVG:\n$svg";
  pg_cmd 'INSERT INTO relgraphs (svg) VALUES ($1) RETURNING id', [ $svg ], \&save_rgraph;
}


sub save_rgraph {
  my($res, $time) = @_;
  return if pg_expect $res, 1;
  $C{sqlt} += $time;

  my $graphid = $res->value(0,0);
  my @ids = sort keys %{$C{nodes}};
  my $ids = join ',', map '$'.$_, 2..@ids+1;
  my $table = $C{type} eq 'v' ? 'vn' : 'producers';

  pg_cmd "UPDATE $table SET rgraph = \$1 WHERE id IN($ids)",
  [ $graphid, @ids ],
  sub {
    my($res, $time) = @_;
    return if pg_expect $res, 0;
    $C{sqlt} += $time;

    AE::log info => sprintf 'Generated relation graph #%d in %.2fs (%.2fs SQL), %s: %s',
      $graphid, AE::time-$C{start}, $C{sqlt}, $C{type}, join ',', @ids;

    %C = ();
    check_rg;
  };
}


1;
