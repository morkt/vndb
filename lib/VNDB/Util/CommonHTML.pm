
package VNDB::Util::CommonHTML;

use strict;
use warnings;
use YAWF ':html', 'xml_escape';
use Exporter 'import';
use Algorithm::Diff::XS 'compact_diff';
use VNDB::Func;
use Encode 'encode_utf8', 'decode_utf8';

our @EXPORT = qw|
  htmlMainTabs htmlDenied htmlHiddenMessage htmlBrowse htmlBrowseNavigate
  htmlRevision htmlEditMessage htmlItemMessage htmlVoteStats htmlHistory
|;


# generates the "main tabs". These are the commonly used tabs for
# 'objects', i.e. VN/producer/release entries and users
# Arguments: u/v/r/p, object, currently selected item (empty=main)
sub htmlMainTabs {
  my($self, $type, $obj, $sel) = @_;
  $sel ||= '';
  my $id = $type.$obj->{id};

  ul class => 'maintabs';
   li $sel eq 'hist' ? (class => 'tabselected') : ();
    a href => "/$id/hist", 'history';
   end;

   if($type ne 'r') {
     my $cnt = $self->dbThreadCount($type, $obj->{id});
     li $sel eq 'disc' ? (class => 'tabselected') : ();
      a href => "/t/$id", "discussions ($cnt)";
     end;
   }

   if($type eq 'u' && $obj->{show_list}) {
     li $sel eq 'wish' ? (class => 'tabselected') : ();
      a href => "/$id/wish", 'wishlist';
     end;

     li $sel eq 'list' ? (class => 'tabselected') : ();
      a href => "/$id/list", 'list';
     end;
   }

   if($type eq 'u' && ($self->authInfo->{id} && $obj->{id} == $self->authInfo->{id} || $self->authCan('usermod'))
    || $type ne 'u' && $self->authCan('edit') && (!$obj->{locked} || $self->authCan('lock')) && (!$obj->{hidden} || $self->authCan('del'))) {
     li $sel eq 'edit' ? (class => 'tabselected') : ();
      a href => "/$id/edit", 'edit';
     end;
   }

   if($type ne 'u' && $self->authCan('del')) {
     li;
      a href => "/$id/hide", $obj->{hidden} ? 'unhide' : 'hide';
     end;
   }

   if($type ne 'u' && $self->authCan('lock')) {
     li;
      a href => "/$id/lock", $obj->{locked} ? 'unlock' : 'lock';
     end;
   }

   if($type eq 'u' && $self->authCan('usermod')) {
     li $sel eq 'del' ? (class => 'tabselected') : ();
      a href => "/$id/del", 'del';
     end;
   }

   if($type eq 'v' && $obj->{rgraph}) {
     li $sel eq 'rg' ? (class => 'tabselected') : ();
      a href => "/$id/rg", 'relations';
     end;
   }

   li !$sel ? (class => 'tabselected') : ();
    a href => "/$id", $id;
   end;
  end;
}


# generates a full error page, including header and footer
sub htmlDenied {
  my $self = shift;
  $self->htmlHeader(title => 'Access Denied');
  div class => 'mainbox';
   h1 'Access Denied';
   div class => 'warning';
    if(!$self->authInfo->{id}) {
      h2 'You need to be logged in to perform this action.';
      p;
       lit 'Please <a href="/u/login">login</a>, or <a href="/u/register">create an account</a> '
          .'if you don\'t have one yet.';
      end;
    } else {
      h2 "You are not allowed to perform this action.";
      p 'It seems you don\'t have the proper rights to perform the action you wanted to perform...';
    }
   end;
  end;
  $self->htmlFooter;
}


# Generates message saying that the current item has been deleted,
# Arguments: [pvr], obj
# Returns 1 if the use doesn't have access to the page, 0 otherwise
sub htmlHiddenMessage {
  my($self, $type, $obj) = @_;
  return 0 if !$obj->{hidden};
  div class => 'mainbox';
   h1 $obj->{title}||$obj->{name};
   div class => 'warning';
    h2 'Item deleted';
    p;
     lit qq|This item has been deleted from the database, File a request on the|
        .qq| <a href="/t/$type$obj->{id}">discussion board</a> to undelete this page.|;
    end;
   end;
  end;
  return $self->htmlFooter() || 1 if !$self->authCan('del');
  return 0;
}


# generates a browse box, arguments:
#  items    => arrayref with the list items
#  options  => hashref containing at least the keys s (sort key), o (order) and p (page)
#  nextpage => whether there's a next page or not
#  sorturl  => base URL to append the sort options to (if there are any sortable columns)
#  pageurl  => base URL to append the page option to
#  class    => classname of the mainbox
#  header   =>
#   can be either an arrayref or subroutine reference,
#   in the case of a subroutine, it will be called when the header should be written,
#   in the case of an arrayref, the array should contain the header items. Each item
#   can again be either an arrayref or subroutine ref. The arrayref would consist of
#   two elements: the name of the header, and the name of the sorting column if it can
#   be sorted
#  row      => subroutine ref, which is called for each item in $list, arguments will be
#   $self, $item_number (starting from 0), $item_value
#  footer   => subroutine ref, called after all rows have been processed
sub htmlBrowse {
  my($self, %opt) = @_;

  $opt{sorturl} .= $opt{sorturl} =~ /\?/ ? ';' : '?' if $opt{sorturl};

  # top navigation
  $self->htmlBrowseNavigate($opt{pageurl}, $opt{options}{p}, $opt{nextpage}, 't');

  div class => 'mainbox browse'.($opt{class} ? ' '.$opt{class} : '');
   table;

   # header
    thead;
     Tr;
      if(ref $opt{header} eq 'CODE') {
        $opt{header}->($self);
      } else {
        for(0..$#{$opt{header}}) {
          if(ref $opt{header}[$_] eq 'CODE') {
            $opt{header}[$_]->($self, $_+1);
          } else {
            td class => 'tc'.($_+1), $opt{header}[$_][2] ? (colspan => $opt{header}[$_][2]) : ();
             lit $opt{header}[$_][0];
             if($opt{header}[$_][1]) {
               lit ' ';
               lit $opt{options}{s} eq $opt{header}[$_][1] && $opt{options}{o} eq 'a' ? "\x{25B4}" : qq|<a href="$opt{sorturl}o=a;s=$opt{header}[$_][1]">\x{25B4}</a>|;
               lit $opt{options}{s} eq $opt{header}[$_][1] && $opt{options}{o} eq 'd' ? "\x{25BE}" : qq|<a href="$opt{sorturl}o=d;s=$opt{header}[$_][1]">\x{25BE}</a>|;
             }
            end;
          }
        }
      }
     end;
    end;

   # rows
    $opt{row}->($self, $_+1, $opt{items}[$_])
      for 0..$#{$opt{items}};

   # footer
    if($opt{footer}) {
      tfoot;
       $opt{footer}->($self);
      end;
    }

   end;
  end;

  # bottom navigation
  $self->htmlBrowseNavigate($opt{pageurl}, $opt{options}{p}, $opt{nextpage}, 'b');
}


# creates next/previous buttons (tabs), if needed
# Arguments: page url, current page (1..n), nextpage (0/1), alignment (t/b), noappend (0/1)
sub htmlBrowseNavigate {
  my($self, $url, $p, $np, $al, $na) = @_;
  return if $p == 1 && !$np;

  $url .= $url =~ /\?/ ? ';p=' : '?p=' unless $na;
  ul class => 'maintabs ' . ($al eq 't' ? 'notfirst' : 'bottom');
   if($p > 1) {
     li class => 'left';
      a href => $url.($p-1), '<- previous';
     end;
   }
   if($np) {
     li;
      a href => $url.($p+1), 'next ->';
     end;
   }
  end;
}


# Shows a revision, including diff if there is a previous revision.
# Arguments: v|p|r, old revision, new revision, @fields
# Where @fields is a list of fields as arrayrefs with:
#  [ shortname, displayname, %options ],
#  Where %options:
#   diff      => 1/0, whether do show a diff on this field
#   serialize => coderef, should convert the field into a readable string, no HTML allowed
#   htmlize   => same as serialize, but HTML is allowed and this can't be diff'ed
#   split     => coderef, should return an array of HTML strings that can be diff'ed. (implies diff => 1)
#   join      => used in combination with split, specifies the string used for joining the HTML strings
sub htmlRevision {
  my($self, $type, $old, $new, @fields) = @_;
  div class => 'mainbox revision';
   h1 'Revision '.$new->{rev};

   # previous/next revision links
   a class => 'prev', href => sprintf('/%s%d.%d', $type, $new->{id}, $new->{rev}-1), '<- earlier revision'
     if $new->{rev} > 1;
   a class => 'next', href => sprintf('/%s%d.%d', $type, $new->{id}, $new->{rev}+1), 'later revision ->'
     if $new->{cid} != $new->{latest};
   p class => 'center';
    a href => "/$type$new->{id}", "$type$new->{id}";
   end;

   # no previous revision, just show info about the revision itself
   if(!$old) {
     div;
      revheader($type, $new);
      br;
      b 'Edit summary:';
      br; br;
      lit bb2html($new->{comments})||'[no summary]';
     end;
   }

   # otherwise, compare the two revisions
   else {
     table;
      thead;
       Tr;
        td; lit '&nbsp;'; end;
        td; revheader($type, $old); end;
        td; revheader($type, $new); end;
       end;
       Tr;
        td; lit '&nbsp;'; end;
        td colspan => 2;
         b 'Edit summary of revision '.$new->{rev}.':';
         br; br;
         lit bb2html($new->{comments})||'[no summary]';
        end;
       end;
      end;
      my $i = 1;
      revdiff(\$i, $old, $new, @$_) for (@fields);
     end;
   }
  end;
}

sub revheader { # type, obj
  my($type, $obj) = @_;
  b 'Revision '.$obj->{rev};
  txt ' (';
  a href => "/$type$obj->{id}.$obj->{rev}/edit", 'edit';
  txt ')';
  br;
  txt 'By ';
  lit userstr($obj);
  txt ' on ';
  lit date $obj->{added}, 'full';
}

sub revdiff {
  my($i, $old, $new, $short, $name, %o) = @_;

  $o{serialize} ||= $o{htmlize};
  $o{diff}++ if $o{split};
  $o{join} ||= '';

  my $ser1 = $o{serialize} ? $o{serialize}->($old->{$short}) : $old->{$short};
  my $ser2 = $o{serialize} ? $o{serialize}->($new->{$short}) : $new->{$short};
  return if $ser1 eq $ser2;

  if($o{diff} && $ser1 && $ser2) {
    # compact_diff doesn't like utf8 encoded strings, so encode input, decode output
    my @ser1 = map encode_utf8($_), $o{split} ? $o{split}->($ser1) : map xml_escape($_), split //, $ser1;
    my @ser2 = map encode_utf8($_), $o{split} ? $o{split}->($ser2) : map xml_escape($_), split //, $ser2;
    return if $o{split} && $#ser1 == $#ser2 && !grep $ser1[$_] ne $ser2[$_], 0..$#ser1;

    $ser1 = $ser2 = '';
    my @d = compact_diff(\@ser1, \@ser2);
    for my $i (0..($#d-2)/2) {
      # $i % 2 == 0  -> equal, otherwise it's different
      my $a = join($o{join}, @ser1[ $d[$i*2]   .. $d[$i*2+2]-1 ]);
      my $b = join($o{join}, @ser2[ $d[$i*2+1] .. $d[$i*2+3]-1 ]);
      $ser1 .= ($ser1?$o{join}:'').($i % 2 ? qq|<b class="diff_del">$a</b>| : $a) if $a;
      $ser2 .= ($ser2?$o{join}:'').($i % 2 ? qq|<b class="diff_add">$b</b>| : $b) if $b;
    }
    $ser1 = decode_utf8($ser1);
    $ser2 = decode_utf8($ser2);
  } elsif(!$o{htmlize}) {
    $ser1 = xml_escape $ser1;
    $ser2 = xml_escape $ser2;
  }

  $ser1 = '[empty]' if !$ser1 && $ser1 ne '0';
  $ser2 = '[empty]' if !$ser2 && $ser2 ne '0';

  Tr $$i++ % 2 ? (class => 'odd') : ();
   td $name;
   td class => 'tcval'; lit $ser1; end;
   td class => 'tcval'; lit $ser2; end;
  end;
}


# Generates a generic message to show as the header of the edit forms
# Arguments: v/r/p, obj
sub htmlEditMessage {
  my($self, $type, $obj) = @_;
  my $full       = {v => 'visual novel', r => 'release', p => 'producer'}->{$type};
  my $guidelines = {v => 2, r => 3, p => 4}->{$type};

  div class => 'mainbox';
   h1 $obj ? 'Edit '.($obj->{name}||$obj->{title}) : "Add new $full";
   div class => 'notice';
    h2 'Before editing:';
    ul;
     li; lit qq|Read the <a href="/d$guidelines">guidelines</a>!|; end;
     if($obj) {
       li; lit qq|Check for any existing discussions on the <a href="/t/$type$obj->{id}">discussion board</a>|; end;
       li; lit qq|Browse the <a href="/$type$obj->{id}/hist">edit history</a> for any recent changes related to what you want to change.|; end;
     } elsif($type ne 'r') {
       li; lit qq|<a href="/$type/all">Search the database</a> to see if we already have information about this $full|; end;
     }
    end;
   end;
   if($obj && $obj->{latest} != $obj->{cid}) {
     div class => 'warning';
      h2 'Reverting';
      p qq|You are editing an old revision of this $full. If you save it, all changes made after this revision will be reverted!|;
     end;
   }
  end;
}


# Generates a small message when the user can't edit the item,
# or the item is locked.
# Arguments: v/r/p, obj
sub htmlItemMessage {
  my($self, $type, $obj) = @_;

  if($obj->{locked}) {
    p class => 'locked', 'Locked for editing'
  } elsif(!$self->authInfo->{id}) {
    p class => 'locked';
     lit 'You need to be <a href="/u/login">logged in</a> to edit this page</a>';
    end;
  } elsif(!$self->authCan('edit')) {
    p class => 'locked', "You're not allowed to edit this page";
  }
}


# generates two tables, one with a vote graph, other with recent votes
sub htmlVoteStats {
  my($self, $type, $obj, $stats) = @_;

  my($max, $count, $total) = (0, 0);
  for (0..$#$stats) {
    $max = $stats->[$_] if $stats->[$_] > $max;
    $count += $stats->[$_];
    $total += $stats->[$_]*($_+1);
  }
  div class => 'votestats';
   table class => 'votegraph';
    thead; Tr;
     td colspan => 2, 'Vote graph';
    end; end;
    for (reverse 0..$#$stats) {
      Tr;
      td class => 'number', $_+1;
       td class => 'graph';
        div style => 'width: '.($stats->[$_] ? $stats->[$_]/$max*250 : 0).'px', ' ';
        txt $stats->[$_];
       end;
      end;
    }
    tfoot; Tr;
     td colspan => 2, sprintf '%d votes total, average %.2f%s', $count, $total/$count,
       $type eq 'v' ? ' ('.$self->{votes}[sprintf '%.0f', $total/$count-1].')' : '';
    end; end;
   end;

   my $recent = $self->dbVoteGet(
     $type.'id' => $obj->{id},
     results => 8,
     order => 'date DESC',
     what => $type eq 'v' ? 'user' : 'vn',
     hide => $type eq 'v',
   );
   if(@$recent) {
     table class => 'recentvotes';
      thead; Tr;
       td colspan => 3, 'Recent votes';
      end; end;
      for (0..$#$recent) {
        Tr $_ % 2 == 0 ? (class => 'odd') : ();
         td;
          if($type eq 'u') {
            a href => "/v$recent->[$_]{vid}", title => $recent->[$_]{original}||$recent->[$_]{title}, shorten $recent->[$_]{title}, 40;
          } else {
            a href => "/u$recent->[$_]{uid}", $recent->[$_]{username};
          }
         end;
         td $recent->[$_]{vote};
         td date $recent->[$_]{date};
        end;
      }
     end;
   }
   clearfloat;
  end;
}


sub htmlHistory {
  my($self, $list, $f, $np, $url) = @_;
  $self->htmlBrowse(
    items    => $list,
    options  => $f,
    nextpage => $np,
    pageurl  => $url,
    class    => 'history',
    header   => [
      sub { td colspan => 2, class => 'tc1', 'Rev.' },
      [ 'Date' ],
      [ 'User' ],
      [ 'Page' ],
    ],
    row      => sub {
      my($s, $n, $i) = @_;
      my $tc = [qw|v r p|]->[$i->{type}];
      my $revurl = "/$tc$i->{iid}.$i->{rev}";

      Tr $n % 2 ? ( class => 'odd' ) : ();
       td class => 'tc1_1';
        a href => $revurl, "$tc$i->{iid}";
       end;
       td class => 'tc1_2';
        a href => $revurl, ".$i->{rev}";
       end;
       td class => 'tc2', date $i->{added};
       td class => 'tc3';
        lit userstr($i);
       end;
       td;
        a href => $revurl, title => $i->{ioriginal}, shorten $i->{ititle}, 80;
       end;
      end;
      if($i->{comments}) {
        Tr $n % 2 ? ( class => 'odd' ) : ();
         td colspan => 5, class => 'editsum';
          lit bb2html $i->{comments}, 150;
         end;
        end;
      }
    },
  );
}


1;
