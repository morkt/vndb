
#
#  Multi::RG  -  Relation graph generator
#

package Multi::RG;

use strict;
use warnings;
use POE 'Wheel::Run', 'Filter::Stream';
use Encode 'encode_utf8';
use XML::Parser;
use XML::Writer;
use Time::HiRes 'time';


sub spawn {
  my $p = shift;
  POE::Session->create(
    package_states => [
      $p => [qw|
        _start shutdown check_rg creategraph getrel builddot savegraph finish
        proc_stdin proc_stdout proc_stderr proc_closed proc_child
      |],
    ],
    heap => {
      font => 'Arial',
      fsize => [ 9, 7, 10 ], # nodes, edges, node_title
      dot => '/usr/bin/dot',
      check_delay => 3600,
      @_,
    }
  );
}


sub _start {
  $_[KERNEL]->alias_set('rg');
  $_[KERNEL]->sig(CHLD => 'proc_child');
  $_[KERNEL]->sig(shutdown => 'shutdown');
  $_[KERNEL]->post(pg => listen => relgraph => 'check_rg');
  $_[KERNEL]->yield('check_rg');
}


sub shutdown {
  $_[KERNEL]->delay('check_rg');
  $_[KERNEL]->post(pg => unlisten => 'relgraph');
  $_[KERNEL]->alias_remove('rg');
}


sub check_rg {
  return if $_[HEAP]{id};
  $_[KERNEL]->call(pg => query => q|
      SELECT 'v' AS type, v.id FROM vn v JOIN vn_relations vr ON vr.vid1 = v.latest WHERE rgraph IS NULL AND hidden = FALSE
    UNION
      SELECT 'p', p.id FROM producers p JOIN producers_relations pr ON pr.pid1 = p.latest WHERE rgraph IS NULL AND hidden = FALSE
    LIMIT 1|, undef, 'creategraph');
}


sub creategraph { # num, res
  return $_[KERNEL]->delay('check_rg', $_[HEAP]{check_delay}) if $_[ARG0] == 0;

  $_[HEAP]{start} = time;
  $_[HEAP]{id} = $_[ARG1][0]{id};
  $_[HEAP]{type} = $_[ARG1][0]{type};
  $_[HEAP]{rels} = {};  # relations (key=id1-id2, value=[relation,official])
  $_[HEAP]{nodes} = {}; # nodes (key=id, value= 0:found, 1:processed)

  $_[KERNEL]->post(pg => query => $_[HEAP]{type} eq 'v'
    ? 'SELECT vid2 AS id, relation, official FROM vn v JOIN vn_relations vr ON vr.vid1 = v.latest WHERE v.id = ?'
    : 'SELECT pid2 AS id, relation FROM producers p JOIN producers_relations pr ON pr.pid1 = p.latest WHERE p.id = ?',
    [ $_[HEAP]{id} ], 'getrel', $_[HEAP]{id});
}


sub getrel { # num, res, id
  my $id = $_[ARG2];
  $_[HEAP]{nodes}{$id} = 1;

  for($_[ARG0] > 0 ? @{$_[ARG1]} : ()) {
    $_[HEAP]{rels}{$id.'-'.$_->{id}} = [ $VNDB::S{ $_[HEAP]{type} eq 'v' ? 'vn_relations' : 'prod_relations' }{$_->{relation}}[1], $_->{official} ] if $id < $_->{id};
    $_[HEAP]{rels}{$_->{id}.'-'.$id} = [ $_->{relation}, $_->{official} ] if $id > $_->{id};

    if(!exists $_[HEAP]{nodes}{$_->{id}}) {
      $_[HEAP]{nodes}{$_->{id}} = 0;
      $_[KERNEL]->post(pg => query => $_[HEAP]{type} eq 'v'
        ? 'SELECT vid2 AS id, relation, official FROM vn v JOIN vn_relations vr ON vr.vid1 = v.latest WHERE v.id = ?'
        : 'SELECT pid2 AS id, relation FROM producers p JOIN producers_relations pr ON pr.pid1 = p.latest WHERE p.id = ?',
        [ $_->{id} ], 'getrel', $_->{id});
    }
  }

  # do we have all relations now? get node info
  if(!grep !$_, values %{$_[HEAP]{nodes}}) {
    my $ids = join(', ', map '?', keys %{$_[HEAP]{nodes}});
    $_[KERNEL]->post(pg => query => $_[HEAP]{type} eq 'v'
      ? "SELECT v.id, vr.title, v.c_released AS date, v.c_languages::text[] AS lang FROM vn v JOIN vn_rev vr ON vr.id = v.latest WHERE v.id IN($ids) ORDER BY v.c_released"
      : "SELECT p.id, pr.name, pr.lang, pr.type FROM producers p JOIN producers_rev pr ON pr.id = p.latest WHERE p.id IN($ids) ORDER BY pr.name",
      [ keys %{$_[HEAP]{nodes}} ], 'builddot');
  }
}


sub builddot { # num, res
  my $nodes = $_[ARG1];

  my $gv =
    qq|graph rgraph {\n|.
    qq|\tnode [ fontname = "$_[HEAP]{font}", shape = "plaintext",|.
      qq| fontsize = $_[HEAP]{fsize}[0], fontcolor = "#333333", color = "#111111" ]\n|.
    qq|\tedge [ labeldistance = 2.5, labelangle = -20, labeljust = 1, minlen = 2, dir = "both",|.
      qq| fontname = $_[HEAP]{font}, fontsize = $_[HEAP]{fsize}[1], arrowsize = 0.7, color = "#111111", fontcolor = "#333333" ]\n|;

  # insert all nodes
  $gv .= $_[HEAP]{type} eq 'v' ? _vnnode($_, $_[HEAP]) : _prodnode($_, $_[HEAP]) for @$nodes;

  # ...and relations
  $gv .= $_[HEAP]{type} eq 'v' ? _vnrels($_[HEAP]{rels}, $nodes) : _prodrels($_[HEAP]{rels}, $nodes);

  $gv .= "}\n";

  # Pass our dot file to graphviz
  $_[HEAP]{svg} = '';
  $_[HEAP]{proc} = POE::Wheel::Run->new(
    Program => $_[HEAP]{dot},
    ProgramArgs => [ '-Tsvg' ],
    StdioFilter => POE::Filter::Stream->new(),
    StdinEvent => 'proc_stdin',
    StdoutEvent => 'proc_stdout',
    StderrEvent => 'proc_stderr',
    CloseEvent => 'proc_closed',
  );
  $_[HEAP]{proc}->put($gv);
}


sub savegraph {
  # Before saving the SVG output, we'll modify it a little:
  # - Remove comments
  # - Add svg: prefix to all tags
  # - Remove xmlns declarations (this is set in the html)
  # - Remove <title> elements (unused)
  # - Remove id attributes (unused)
  # - Remove first <polygon> element (emulates the background color)
  # - Replace stroke and fill attributes with classes (so that coloring is done in CSS)
  my $svg = '';
  my $w = XML::Writer->new(OUTPUT => \$svg);
  my $p = XML::Parser->new;
  $p->setHandlers(
    Start => sub {
      my($expat, $el, %attr) = @_;
      return if $el eq 'title' || $expat->in_element('title');
      return if $el eq 'polygon' && $expat->depth == 2;

      $attr{class} = 'border' if $attr{stroke} && $attr{stroke} eq '#111111';
      $attr{class} = 'nodebg' if $attr{fill} && $attr{fill} eq '#222222';

      delete @attr{qw|stroke fill xmlns xmlns:xlink|};
      delete $attr{id} if $attr{id} && $attr{id} !~ /^node_[vp]\d+$/;
      $el eq 'path' || $el eq 'polygon'
        ? $w->emptyTag("svg:$el", %attr)
        : $w->startTag("svg:$el", %attr);
    },
    End => sub {
      my($expat, $el) = @_;
      return if $el eq 'title' || $expat->in_element('title');
      return if $el eq 'polygon' && $expat->depth == 2;
      $w->endTag("svg:$el") if $el ne 'path' && $el ne 'polygon';
    },
    Char => sub {
      my($expat, $str) = @_;
      return if $expat->in_element('title');
      $w->characters($str) if $str !~ /^[\s\t\r\n]*$/s;
    }
  );
  $p->parsestring($_[HEAP]{svg});
  $w->end();

  # save the processed SVG in the database and fetch graph ID
  $_[KERNEL]->post(pg => query => 'INSERT INTO relgraphs (svg) VALUES (?) RETURNING id', [ $svg ], 'finish');
}


sub finish { # num, res
  my $id = $_[ARG1][0]{id};
  my $ids = join ',', sort map int, keys %{$_[HEAP]{nodes}};
  my $table = $_[HEAP]{type} eq 'v' ? 'vn' : 'producers';

  # update the table
  $_[KERNEL]->post(pg => do => "UPDATE $table SET rgraph = ? WHERE id IN($ids)", [ $id ]);

  # log
  $_[KERNEL]->call(core => log => 'Generated relation graph #%d in %.2fs, %s: %s', $id, time-$_[HEAP]{start}, uc $_[HEAP]{type}, $ids);

  # clean up
  delete @{$_[HEAP]}{qw| start id type nodes rels svg proc |};

  # check for more things to do
  $_[KERNEL]->yield('check_rg');
}



# POE handlers for communication with GraphViz
sub proc_stdin {
  $_[HEAP]{proc}->shutdown_stdin;
}
sub proc_stdout {
  $_[HEAP]{svg} .= $_[ARG0];
}
sub proc_stderr {
  $_[KERNEL]->call(core => log => 'GraphViz STDERR: %s', $_[ARG0]);
}
sub proc_closed {
  $_[KERNEL]->yield('savegraph');
}
sub proc_child {
  1; # do nothing, just make sure SIGCHLD is handled to reap the process
}



# non-POE helper functions

sub _vnnode {
  my($n, $heap) = @_;

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
    $_->{id}, encode_utf8($tooltip), $heap->{fsize}[2], encode_utf8($title), $date, join('/', @{$n->{lang}})||'N/A';
}


sub _vnrels {
  my($rels, $vns) = @_;
  my $r = '';

  # @rels = ([ vid1, vid2, relation, official, date1, date2 ], ..), for easier processing
  my @rels = map {
    /^([0-9]+)-([0-9]+)$/;
    my $vn1 = (grep $1 == $_->{id}, @$vns)[0];
    my $vn2 = (grep $2 == $_->{id}, @$vns)[0];
    [ $1, $2, @{$rels->{$_}}, $vn1->{date}, $vn2->{date} ]
  } keys %$rels;

  # insert all edges, ordered by release date again
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
  return $r;
}


sub _prodnode {
  my($n, $heap) = @_;

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
    $_->{id}, encode_utf8($tooltip), $heap->{fsize}[2], encode_utf8($name), $n->{lang}, $n->{type};
}


sub _prodrels {
  my($rels, $prods) = @_;
  my $r = '';

  for (keys %$rels) {
    /^([0-9]+)-([0-9]+)$/;
    my $p1 = (grep $1 == $_->{id}, @$prods)[0];
    my $p2 = (grep $2 == $_->{id}, @$prods)[0];

    my $rev = $VNDB::S{prod_relations}{$rels->{$_}[0]}[1];
    my $label = $rev ne $rels->{$_}[0]
      ? qq|headlabel = "\$____prodrel_${rev}____\$", taillabel = "\$____prodrel_$rels->{$_}[0]____\$"|
      : qq|label = "\$____prodrel_$rels->{$_}[0]____\$"|;
    $r .= qq|\tp$p1->{id} -- p$p2->{id} [ $label ]\n|;
  }
  return $r;
}


1;

