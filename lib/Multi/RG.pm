
#
#  Multi::RG  -  Relation graph generator
#

package Multi::RG;

use strict;
use warnings;
use POE;
use Text::Unidecode;
use GraphViz;


sub spawn {
  my $p = shift;
  POE::Session->create(
    package_states => [
      $p => [qw| _start cmd_relgraph creategraph getrel relscomplete buildgraph graphcomplete |],
    ],
    heap => {
      font => 's',
      fsize => [ 9, 7, 10 ], # nodes, edges, node_title
      imgdir => '/www/vndb/static/rg',
      datdir => '/www/vndb/data/rg',
      moy => [qw| Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec |],
      @_,
    }
  );
}


sub _start {
  $_[KERNEL]->alias_set('rg');
  $_[KERNEL]->call(core => register => qr/^relgraph ((?:[0-9]+)(?:\s+[0-9]+)*|all)$/, 'cmd_relgraph');
}


sub cmd_relgraph {
  $_[HEAP]{curcmd} = $_[ARG0];

 # determine vns to generate graphs for 
  if($_[ARG1] ne 'all') {
    $_[HEAP]{todo} = [ split /\s/, $_[ARG1] ];
  } else {
    my $q = $Multi::SQL->prepare('SELECT id FROM vn WHERE hidden = 0');
    $q->execute;
    $_[HEAP]{todo} = [ map { $_->[0] } @{$q->fetchall_arrayref([])} ];
  }

 # generate first graph
  $_[KERNEL]->yield(creategraph => $_[HEAP]{todo}[0]);
}


sub creategraph { # id
  # Function order:
  #   creategraph
  #   getrel (recursive)
  #   relscomplete
  #   if !rels
  #     graphcomplete
  #   else
  #     buildgraph
  #     graphcomplete

  $_[KERNEL]->call(core => log => 3, 'Processing graph for v%d', $_[ARG0]);
  $_[HEAP]{gv} = GraphViz->new(
   #width => 700/96,
    height => 2000/96,
    ratio => 'compress',
  );

  $_[HEAP]{rels} = {}; # relations (key=vid1-vid2, value=relation)
  $_[HEAP]{nodes} = {}; # nodes (key=vid, value=[ vid, title, date, lang, processed ])
  $_[HEAP]{vid} = $_[ARG0];
  $_[KERNEL]->yield(getrel => $_[ARG0]);
}


sub getrel { # vid
  #return if $_[HEAP]{nodes}{$_[ARG0]} && $_[HEAP]{nodes}{$_[ARG0]}[4];
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
    if($r->{vid1} < $r->{vid2}) {
      $_[HEAP]{rels}{$r->{vid1}.'-'.$r->{vid2}} = reverserel($r->{relation});
    } else { 
      $_[HEAP]{rels}{$r->{vid2}.'-'.$r->{vid1}} = $r->{relation} if $r->{vid1} < $r->{vid2};
    }
    
    for (1,2) {
      my($vid, $title, $date, $lang) = @$r{ "vid$_", "title$_", "date$_", "lang$_" };
      if(!$_[HEAP]{nodes}{$vid}) {
        $_[HEAP]{nodes}{$vid} = [ $vid, $title, $date, $lang, 0 ]; 
        $_[KERNEL]->yield(getrel => $vid) if $vid != $_[ARG0];
      }
    }
    $_[HEAP]{nodes}{$_[ARG0]}[4]++;
  }

  $_[KERNEL]->yield('relscomplete') if !grep { !$_->[4] } values %{$_[HEAP]{nodes}};
}


sub relscomplete { # heap->nodes and heap->rels are now assumed to contain all necessary data 
  if(!keys %{$_[HEAP]{nodes}}) {
    $_[KERNEL]->call(core => log => 3, 'No relation graph for v%d', $_[HEAP]{vid});
    $Multi::SQL->do('UPDATE vn SET rgraph = 0 WHERE id = ?', undef, $_[HEAP]{vid});
    $_[HEAP]{nodes}{$_[HEAP]{vid}} = [];
    $_[KERNEL]->yield('graphcomplete');
    return;
  }
  $_[KERNEL]->call(core => log => 3, 'Fetched all relation data');

 # insert all nodes, ordered by release date
  for (sort { $a->[2] <=> $b->[2] } values %{$_[HEAP]{nodes}}) {
    my $date = sprintf '%08d', $_->[2];
    $date =~ s#^([0-9]{4})([0-9]{2}).+#$1==0?'N/A':$1==9999?'TBA':(($2&&$2>0?($_[HEAP]{moy}[$2-1].' '):'').$1)#e;

    my $title = unidecode($_->[1]);
    $title = substr($title, 0, 27).'...' if length($title) > 30;
    $title =~ s/&/&amp;/g;

    $_[HEAP]{gv}->add_node($_->[0],
      fontname => $_[HEAP]{font},
      shape => 'plaintext',
      fontsize => $_[HEAP]{fsize}[0],
      style => 'setlinewidth(0.5)',
      URL => '/v'.$_->[0],
      tooltip => $title,
      label => sprintf(
        '<<TABLE CELLSPACING="0" CELLPADDING="1" BORDER="0" CELLBORDER="1" BGCOLOR="#f0f0f0">
           <TR><TD COLSPAN="2" ALIGN="CENTER" CELLPADDING="3"><FONT POINT-SIZE="%d">  %s  </FONT></TD></TR>
           <TR><TD> %s </TD><TD> %s </TD></TR>
        </TABLE>>',
        $_[HEAP]{fsize}[2], $title, $date, $_->[3]||'N/A'
      ),
    );
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
    $_[HEAP]{gv}->add_edge(
      $_->[1] => $_->[0],
      labeldistance => 2.5,
      labelangle => -20,
      labeljust => 'l',
      dir => 'both',
      minlen => 2,
      fontname => $_[HEAP]{font},
      fontsize => $_[HEAP]{fsize}[1],
      arrowsize => 0.7,
      color => '#69a89a',
      $VNDB::VRELW->{$_->[2]} ? (
        headlabel => $VNDB::VREL->[$_->[2]],
        taillabel => $VNDB::VREL->[$_->[2]-1],
      ) : $VNDB::VRELW->{$_->[2]+1} ? (
        headlabel => $VNDB::VREL->[$_->[2]],
        taillabel => $VNDB::VREL->[$_->[2]+1],
      ) : (
        label => ' '.$VNDB::VREL->[$_->[2]],
      ),
    );
  }
 
  $_[KERNEL]->yield('buildgraph');
}


sub buildgraph {
 # get a new ID
  my $gid = $Multi::SQL->prepare("SELECT nextval('relgraph_seq')");
  $gid->execute;
  $gid = $gid->fetchrow_arrayref->[0];
  my $gif = sprintf '%s/%02d/%d.gif', $_[HEAP]{imgdir}, $gid % 50, $gid;
  my $cmap = sprintf '%s/%02d/%d.cmap', $_[HEAP]{datdir}, $gid % 50, $gid;

 # generate the graph
  $_[HEAP]{gv}->as_gif($gif);
  chmod 0666, $gif;

 # generate the image map
  open my $F, '>', $cmap or die $!;
  print $F '<!-- V:'.join(',',keys %{$_[HEAP]{nodes}})." -->\n";
  (my $d = $_[HEAP]{gv}->as_cmapx) =~ s/(id|name)="[^"]+"/$1="rgraph"/g;
  print $F $d;
  close $F;
  chmod 0666, $cmap;

 # update the VN table
  $Multi::SQL->do(sprintf q|
    UPDATE vn
      SET rgraph = %d
      WHERE id IN(%s)|,
    $gid, join(',', keys %{$_[HEAP]{nodes}}));

  $_[KERNEL]->yield('graphcomplete');
}


sub graphcomplete { # all actions to create the graph (after calling creategraph) are now done
  $_[KERNEL]->call(core => log => 3, 'Generated the relation graph for v%d', $_[HEAP]{vid});

 # remove processed vns, and check for other graphs in the queue
  $_[HEAP]{todo} = [ grep { !$_[HEAP]{nodes}{$_} } @{$_[HEAP]{todo}} ];
  if(@{$_[HEAP]{todo}}) {
    $_[KERNEL]->yield(creategraph => $_[HEAP]{todo}[0]);
  } else {
    $_[KERNEL]->post(core => finish => $_[HEAP]{curcmd});
    delete @{$_[HEAP]}{qw| vid nodes rels curcmd gv todo |};
  }
}





# Not a POE handler, just a small macro
sub reverserel { # relation
  return $VNDB::VRELW->{$_[0]} ? $_[0]-1 : $VNDB::VRELW->{$_[0]+1} ? $_[0]+1 : $_[0];
}


1;

