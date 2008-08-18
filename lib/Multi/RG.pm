
#
#  Multi::RG  -  Relation graph generator
#

package Multi::RG;

use strict;
use warnings;
use POE 'Wheel::Run', 'Filter::Stream';
use Encode 'encode_utf8';


sub spawn {
  my $p = shift;
  POE::Session->create(
    package_states => [
      $p => [qw|
        _start cmd_relgraph
        creategraph getrel builddot buildgraph savegraph completegraph
        proc_stdin proc_stdout proc_stderr proc_closed proc_child
      |],
    ],
    heap => {
      font => 'Arial',
      fsize => [ 9, 7, 10 ], # nodes, edges, node_title
      imgdir => '/www/vndb/static/rg',
      datdir => '/www/vndb/data/rg',
      moy => [qw| Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec |],
      dot => '/usr/bin/dot',
      @_,
    }
  );
}


sub _start {
  $_[KERNEL]->alias_set('rg');
  $_[KERNEL]->sig(CHLD => 'proc_child');
  $_[KERNEL]->call(core => register => qr/^relgraph ((?:[0-9]+)(?:\s+[0-9]+)*|all)$/, 'cmd_relgraph');

 # regenerate all relation graphs once a month
  $_[KERNEL]->post(core => addcron => '0 3 1 * *', 'relgraph all');
}


sub cmd_relgraph {
  $_[HEAP]{curcmd} = $_[ARG0];

 # determine vns to generate graphs for 
  if($_[ARG1] ne 'all') {
    $_[HEAP]{todo} = [ split /\s/, $_[ARG1] ];
  } else {
    my $q = $Multi::SQL->prepare('SELECT id FROM vn WHERE hidden = FALSE');
    $q->execute;
    $_[HEAP]{todo} = [ map { $_->[0] } @{$q->fetchall_arrayref([])} ];
  }

 # generate first graph
  $_[KERNEL]->yield(creategraph => $_[HEAP]{todo}[0]);
}


sub creategraph { # id
  # Function order:
  #   creategraph      (inits vars and initates getrel)
  #   getrel           (recursive - fetches relation and vn data)
  #   if !rels
  #     completegraph  (checks for other vids in the queue, exits otherwise)
  #   else
  #     builddot       (creates input for graphviz)
  #     buildgraph     (fetches graph ID and calls grapviz)
  #     savegraph      (writes cmap, chmods files, updates database entries)
  #     completegraph

  $_[KERNEL]->call(core => log => 3, 'Processing graph for v%d', $_[ARG0]);

  $_[HEAP]{rels} = {}; # relations (key=vid1-vid2, value=relation)
  $_[HEAP]{nodes} = {}; # nodes (key=vid, value=[ vid, title, date, lang, processed ])
  $_[HEAP]{vid} = $_[ARG0];
  $_[KERNEL]->yield(getrel => $_[ARG0]);
}


sub getrel { # vid
  $_[KERNEL]->call(core => log => 3, 'Fetching relations for v%d', $_[ARG0]);

  my $s = $Multi::SQL->prepare(q|
    SELECT vr1.vid AS vid1, r.vid2, r.relation, vr1.title AS title1, vr2.title AS title2,
      v1.c_released AS date1, v2.c_released AS date2, v1.c_languages AS lang1, v2.c_languages AS lang2
    FROM vn_relations r
    JOIN vn_rev vr1 ON r.vid1 = vr1.id
    JOIN vn v1 ON v1.latest = vr1.id
    JOIN vn v2 ON r.vid2 = v2.id
    JOIN vn_rev vr2 ON v2.latest = vr2.id
    WHERE (r.vid2 = ? OR vr1.vid = ?)|
  );
  $s->execute($_[ARG0], $_[ARG0]);
  while(my $r = $s->fetchrow_hashref) {
    $_[HEAP]{rels}{$r->{vid1}.'-'.$r->{vid2}} = reverserel($r->{relation}) if $r->{vid1} < $r->{vid2};
    $_[HEAP]{rels}{$r->{vid2}.'-'.$r->{vid1}} = $r->{relation}             if $r->{vid1} > $r->{vid2};
    
    for (1,2) {
      my($vid, $title, $date, $lang) = @$r{ "vid$_", "title$_", "date$_", "lang$_" };
      if(!$_[HEAP]{nodes}{$vid}) {
        $_[HEAP]{nodes}{$vid} = [ $vid, $title, $date, $lang, 0 ]; 
        $_[KERNEL]->yield(getrel => $vid) if $vid != $_[ARG0];
      }
    }
    $_[HEAP]{nodes}{$_[ARG0]}[4]++;
  }

  if(!grep !$_->[4], values %{$_[HEAP]{nodes}}) {
    if(!keys %{$_[HEAP]{nodes}}) {
      $_[KERNEL]->call(core => log => 3, 'No relation graph for v%d', $_[HEAP]{vid});
      $Multi::SQL->do('UPDATE vn SET rgraph = NULL WHERE id = ?', undef, $_[HEAP]{vid});
      $_[HEAP]{nodes}{$_[HEAP]{vid}} = [];
      $_[KERNEL]->yield('completegraph');
      return;
    }
    $_[KERNEL]->call(core => log => 3, 'Fetched all relation data');
    $_[KERNEL]->yield('builddot') 
  }
}


sub builddot {
  my $gv =
    qq|graph rgraph {\n|.
    qq|\tratio = "compress"\n|.
    qq|\tnode [ fontname = "$_[HEAP]{font}", shape = "plaintext",|.
      qq| fontsize = $_[HEAP]{fsize}[0], style = "setlinewidth(0.5)" ]\n|.
    qq|\tedge [ labeldistance = 2.5, labelangle = -20, labeljust = 1, minlen = 2, dir = "both",|.
      qq| fontname = $_[HEAP]{font}, fontsize = $_[HEAP]{fsize}[1], arrowsize = 0.7, color = "#69a89a"  ]\n|;

 # insert all nodes, ordered by release date
  for (sort { $a->[2] <=> $b->[2] } values %{$_[HEAP]{nodes}}) {
    my $date = sprintf '%08d', $_->[2];
    $date =~ s#^([0-9]{4})([0-9]{2}).+#$1==0?'N/A':$1==9999?'TBA':(($2&&$2<13?($_[HEAP]{moy}[$2-1].' '):'').$1)#e;

    my $title = $_->[1];
    $title = substr($title, 0, 27).'...' if length($title) > 30;
    $title =~ s/&/&amp;/g;
    $title =~ s/>/&gt;/g;
    $title =~ s/</&lt;/g;

    my $tooltip = $_->[1];
    $tooltip =~ s/\\/\\\\/g;
    $tooltip =~ s/"/\\"/g;

    $gv .= sprintf
      qq|\tv%d [ URL = "/v%d", tooltip = "%s" label=<|.
        q|<TABLE CELLSPACING="0" CELLPADDING="1" BORDER="0" CELLBORDER="1" BGCOLOR="#f0f0f0">|.
          q|<TR><TD COLSPAN="2" ALIGN="CENTER" CELLPADDING="2"><FONT POINT-SIZE="%d">  %s  </FONT></TD></TR>|.
          q|<TR><TD> %s </TD><TD> %s </TD></TR>|.
        qq|</TABLE>> ]\n|,
      $_->[0], $_->[0], encode_utf8($tooltip), $_[HEAP]{fsize}[2], encode_utf8($title), $date, $_->[3]||'N/A';
  }

 # @rels = ([ vid1, vid2, relation, date1, date2 ], ..), for easier processing
  my @rels = map {
    /^([0-9]+)-([0-9]+)$/;
    [ $1, $2, $_[HEAP]{rels}{$_}, $_[HEAP]{nodes}{$1}[2], $_[HEAP]{nodes}{$2}[2] ]
  } keys %{$_[HEAP]{rels}};

 # insert all edges, ordered by release date again
  for (sort { ($a->[3]>$a->[4]?$a->[4]:$a->[3]) <=> ($b->[3]>$b->[4]?$b->[4]:$b->[3]) } @rels) {
   # [older game] -> [newer game]
    if($_->[4] > $_->[3]) {
      ($_->[0], $_->[1]) = ($_->[1], $_->[0]);
      $_->[2] = reverserel($_->[2]);
    }

    my $label = 
      $VNDB::VRELW->{$_->[2]}   ? qq|headlabel = "$VNDB::VREL->[$_->[2]]", taillabel = "$VNDB::VREL->[$_->[2]-1]"| :
      $VNDB::VRELW->{$_->[2]+1} ? qq|headlabel = "$VNDB::VREL->[$_->[2]]", taillabel = "$VNDB::VREL->[$_->[2]+1]"|
                                : qq|label = " $VNDB::VREL->[$_->[2]]"|;

    $gv .= qq|\tv$$_[1] -- v$$_[0] [ $label ]\n|;
  }

  $gv .= "}\n";
  #print $gv;
  $_[HEAP]{gv} = \$gv;
  $_[KERNEL]->yield('buildgraph');
}


sub buildgraph {
 # get a new ID
  my $gid = $Multi::SQL->prepare("INSERT INTO relgraph (cmap) VALUES ('') RETURNING id");
  $gid->execute;
  $gid = $gid->fetchrow_arrayref->[0];
  $_[HEAP]{gid} = [
    $gid,
    sprintf('%s/%02d/%d.gif', $_[HEAP]{imgdir}, $gid % 100, $gid),
  ];

  # roughly equivalent to:
  #  cat layout.txt | dot -Tgif -o graph.gif -Tcmapx
  $_[HEAP]{proc} = POE::Wheel::Run->new(
    Program => $_[HEAP]{dot},
    ProgramArgs => [ '-Tgif', '-o', $_[HEAP]{gid}[1], '-Tcmapx' ],
    StdioFilter => POE::Filter::Stream->new(),
    StdinEvent => 'proc_stdin',
    StdoutEvent => 'proc_stdout',
    StderrEvent => 'proc_stderr',
    CloseEvent => 'proc_closed',
  );
  $_[HEAP]{proc}->put(${$_[HEAP]{gv}});
  $_[HEAP]{cmap} = '';
}


sub savegraph {
 # save the image map
  $Multi::SQL->do('UPDATE relgraph SET cmap = ? WHERE id = ?', undef,
    '<!-- V:'.join(',',keys %{$_[HEAP]{nodes}})." -->\n$_[HEAP]{cmap}", $_[HEAP]{gid}[0]);

 # proper chmod
  chmod 0666, $_[HEAP]{gid}[1];

 # update the VN table
  $Multi::SQL->do(sprintf q|
    UPDATE vn
      SET rgraph = %d
      WHERE id IN(%s)|,
    $_[HEAP]{gid}[0], join(',', keys %{$_[HEAP]{nodes}}));

  $_[KERNEL]->yield('completegraph');
}


sub completegraph {
  $_[KERNEL]->call(core => log => 3, 'Generated the relation graph for v%d', $_[HEAP]{vid});

 # remove processed vns, and check for other graphs in the queue
  $_[HEAP]{todo} = [ grep { !$_[HEAP]{nodes}{$_} } @{$_[HEAP]{todo}} ];
  if(@{$_[HEAP]{todo}}) {
    $_[KERNEL]->yield(creategraph => $_[HEAP]{todo}[0]);
  } else {
    $_[KERNEL]->post(core => finish => $_[HEAP]{curcmd});
    delete @{$_[HEAP]}{qw| vid nodes rels curcmd gv todo gid cmap |};
  }
}




# POE handlers for communication with GraphViz
sub proc_stdin {
  $_[HEAP]{proc}->shutdown_stdin;
}
sub proc_stdout {
  $_[HEAP]{cmap} .= $_[ARG0];
}
sub proc_stderr {
  $_[KERNEL]->call(core => log => 1, 'GraphViz STDERR: %s', $_[ARG0]);
}
sub proc_closed {
  $_[KERNEL]->yield('savegraph');
  undef $_[HEAP]{proc};
}
sub proc_child {
  1; # do nothing, just make sure SIGCHLD is handled to reap the process
}




# Not a POE handler, just a small macro
sub reverserel { # relation
  return $VNDB::VRELW->{$_[0]} ? $_[0]-1 : $VNDB::VRELW->{$_[0]+1} ? $_[0]+1 : $_[0];
}


1;

