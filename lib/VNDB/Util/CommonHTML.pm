
package VNDB::Util::CommonHTML;

use strict;
use warnings;
use TUWF ':html', 'xml_escape', 'html_escape';
use Exporter 'import';
use Algorithm::Diff::XS 'compact_diff';
use Encode 'encode_utf8', 'decode_utf8';
use VNDB::Func;
use POSIX 'ceil';

our @EXPORT = qw|
  htmlMainTabs htmlDenied htmlHiddenMessage htmlRevision
  htmlEditMessage htmlItemMessage htmlVoteStats htmlSearchBox htmlRGHeader
|;


# generates the "main tabs". These are the commonly used tabs for
# 'objects', i.e. VN/producer/release entries and users
# Arguments: u/v/r/p/g/i/c, object, currently selected item (empty=main)
sub htmlMainTabs {
  my($self, $type, $obj, $sel) = @_;
  $sel ||= '';
  my $id = $type.$obj->{id};

  return if $type eq 'g' && !$self->authCan('tagmod');

  ul class => 'maintabs';
   if($type =~ /[uvrpcs]/) {
     li $sel eq 'hist' ? (class => 'tabselected') : ();
      a href => "/$id/hist", 'history';
     end;
   }

   if($type =~ /[uvp]/) {
     my $cnt = $self->dbThreadCount($type, $obj->{id});
     li $sel eq 'disc' ? (class => 'tabselected') : ();
      a href => "/t/$id", "discussions ($cnt)";
     end;
   }

   if($type eq 'u') {
     li $sel eq 'posts' ? (class => 'tabselected') : ();
      a href => "/$id/posts", 'posts';
     end;
   }

   if($type eq 'u' && (!($obj->{hide_list} || $obj->{prefs}{hide_list}) || ($self->authInfo->{id} && $self->authInfo->{id} == $obj->{id}) || $self->authCan('usermod'))) {
     li $sel eq 'wish' ? (class => 'tabselected') : ();
      a href => "/$id/wish", 'wishlist';
     end;

     li $sel eq 'votes' ? (class => 'tabselected') : ();
      a href => "/$id/votes", 'votes';
     end;

     li $sel eq 'list' ? (class => 'tabselected') : ();
      a href => "/$id/list", 'list';
     end;
   }

   if($type eq 'v' && $self->authCan('tag') && !$obj->{hidden}) {
     li $sel eq 'tagmod' ? (class => 'tabselected') : ();
      a href => "/$id/tagmod", 'modify tags';
     end;
   }

   if(($type =~ /[rc]/ && $self->authCan('edit')) && $self->authInfo->{c_changes} > 0) {
     li $sel eq 'copy' ? (class => 'tabselected') : ();
      a href => "/$id/copy", 'copy';
     end;
   }

   if(   $type eq 'u'      && ($self->authInfo->{id} && $obj->{id} == $self->authInfo->{id} || $self->authCan('usermod'))
      || $type =~ /[vrpcs]/ && $self->authCan('edit') && ((!$obj->{locked} && !$obj->{hidden}) || $self->authCan('dbmod'))
      || $type =~ /[gi]/   && $self->authCan('tagmod')
   ) {
     li $sel eq 'edit' ? (class => 'tabselected') : ();
      a href => "/$id/edit", 'edit';
     end;
   }

   if($type eq 'u' && $self->authCan('usermod')) {
     li $sel eq 'del' ? (class => 'tabselected') : ();
      a href => "/$id/del", 'remove';
     end;
   }

   if($type eq 'v') {
    li $sel eq 'releases' ? (class => 'tabselected') : ();
    a href => "/$id/releases", 'releases';
    end;
   }

   if($type =~ /[vp]/ && $obj->{rgraph}) {
     li $sel eq 'rg' ? (class => 'tabselected') : ();
      a href => "/$id/rg", 'relations';
     end;
   }

   li !$sel ? (class => 'tabselected') : ();
    a href => "/$id", $id;
   end;
  end 'ul';
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
      p; lit 'Please <a href="/u/login">login</a>, or <a href="/u/register">create an account</a> if you don\'t have one yet.'; end;
    } else {
      h2 'You are not allowed to perform this action.';
      p 'It seems you don\'t have the proper rights to perform the action you wanted to perform...';
    }
   end;
  end 'div';
  $self->htmlFooter;
}


# Generates message saying that the current item has been deleted,
# Arguments: [pvrc], obj
# Returns 1 if the use doesn't have access to the page, 0 otherwise
sub htmlHiddenMessage {
  my($self, $type, $obj) = @_;
  return 0 if !$obj->{hidden};
  my $board = $type =~ /[cs]/ ? 'db' : $type eq 'r' ? 'v'.$obj->{vn}[0]{vid} : $type.$obj->{id};
  # fetch edit summary (not present in $obj, requires the db*GetRev() methods)
  my $editsum = $type eq 'v' ? $self->dbVNGetRev(id => $obj->{id})->[0]{comments}
              : $type eq 'r' ? $self->dbReleaseGetRev(id => $obj->{id})->[0]{comments}
              : $type eq 'c' ? $self->dbCharGetRev(id => $obj->{id})->[0]{comments}
              : $type eq 's' ? $self->dbStaffGetRev(id => $obj->{id})->[0]{comments}
                             : $self->dbProducerGetRev(id => $obj->{id})->[0]{comments};
  div class => 'mainbox';
   h1 $obj->{title}||$obj->{name};
   div class => 'warning';
    h2 'Item deleted';
    p;
     lit 'This item has been deleted from the database. File a request on the <a href="/t/'.$board.'">discussion board</a> to undelete this page.';
     br; br;
     lit bb2html $editsum;
    end;
   end;
  end 'div';
  return $self->htmlFooter() || 1 if !$self->authCan('dbmod');
  return 0;
}


# Shows a revision, including diff if there is a previous revision.
# Arguments: v|p|r|c, old revision, new revision, @fields
# Where @fields is a list of fields as arrayrefs with:
#  [ shortname, displayname, %options ],
#  Where %options:
#   diff      => 1/0/regex, whether to show a diff on this field, and what to split it with (1 = character-level diff)
#   serialize => coderef, should convert the field into a readable string, no HTML allowed
#   htmlize   => same as serialize, but HTML is allowed and this can't be diff'ed
#   split     => coderef, should return an array of HTML strings that can be diff'ed. (implies diff => 1)
#   join      => used in combination with split, specifies the string used for joining the HTML strings
sub htmlRevision {
  my($self, $type, $old, $new, @fields) = @_;
  div class => 'mainbox revision';
   h1 "Revision $new->{rev}";

   # character information may be rather spoilerous
   if($type eq 'c') {
     div class => 'warning';
      h2 'SPOILER WARNING!';
      lit 'This revision page may contain major spoilers. You may want to view the <a href="/c'.$new->{id}.'">final page</a> instead.';
     end;
     br;br;
   }

   # previous/next revision links
   a class => 'prev', href => sprintf('/%s%d.%d', $type, $new->{id}, $new->{rev}-1), '<- earlier revision' if $new->{rev} > 1;
   a class => 'next', href => sprintf('/%s%d.%d', $type, $new->{id}, $new->{rev}+1), 'later revision ->' if !$new->{lastrev};
   p class => 'center';
    a href => "/$type$new->{id}", "$type$new->{id}";
   end;

   # no previous revision, just show info about the revision itself
   if(!$old) {
     div class => 'rev';
      revheader($self, $type, $new);
      br;
      b 'Edit summary';
      br; br;
      lit bb2html($new->{comments})||'-';
     end;
   }

   # otherwise, compare the two revisions
   else {
     table class => 'stripe';
      thead;
       Tr;
        td; lit '&#xa0;'; end;
        td; revheader($self, $type, $old); end;
        td; revheader($self, $type, $new); end;
       end;
       Tr;
        td; lit '&#xa0;'; end;
        td colspan => 2;
         b "Edit summary of revision $new->{rev}:";
         br; br;
         lit bb2html($new->{comments})||'-';
        end;
       end;
      end;
      revdiff($type, $old, $new, @$_) for (
        [ ihid   => 'Deleted', serialize => sub { $_[0] ? 'Yes' : 'No' } ],
        [ ilock  => 'Locked',  serialize => sub { $_[0] ? 'Yes' : 'No' } ],
        @fields
      );
     end 'table';
   }
  end 'div';
}

sub revheader { # type, obj
  my($self, $type, $obj) = @_;
  b "Revision $obj->{rev}";
  txt ' (';
  a href => "/$type$obj->{id}.$obj->{rev}/edit", 'edit';
  txt ')';
  br;
  txt 'By ';
  lit fmtuser $obj;
  txt ' on ';
  txt fmtdate $obj->{added}, 'full';
}

sub revdiff {
  my($type, $old, $new, $short, $display, %o) = @_;

  $o{serialize} ||= $o{htmlize};
  $o{diff} = 1 if $o{split};
  $o{join} ||= '';

  my $ser1 = $o{serialize} ? $o{serialize}->($old->{$short}, $old) : $old->{$short};
  my $ser2 = $o{serialize} ? $o{serialize}->($new->{$short}, $new) : $new->{$short};
  return if $ser1 eq $ser2;

  if($o{diff} && $ser1 && $ser2) {
    my $sep = ref $o{diff} ? qr/($o{diff})/ : qr//;
    my @ser1 = map encode_utf8($_), $o{split} ? $o{split}->($ser1) : map html_escape($_), split $sep, $ser1;
    my @ser2 = map encode_utf8($_), $o{split} ? $o{split}->($ser2) : map html_escape($_), split $sep, $ser2;
    return if $o{split} && $#ser1 == $#ser2 && !grep $ser1[$_] ne $ser2[$_], 0..$#ser1;

    $ser1 = $ser2 = '';
    my @d = compact_diff(\@ser1, \@ser2);
    for my $i (0..($#d-2)/2) {
      # $i % 2 == 0  -> equal, otherwise it's different
      my $a = join($o{join}, @ser1[ $d[$i*2]   .. $d[$i*2+2]-1 ]);
      my $b = join($o{join}, @ser2[ $d[$i*2+1] .. $d[$i*2+3]-1 ]);
      $ser1 .= ($ser1?$o{join}:'').($i % 2 ? qq|<b class="diff_del">$a</b>| : $a) if $a ne '';
      $ser2 .= ($ser2?$o{join}:'').($i % 2 ? qq|<b class="diff_add">$b</b>| : $b) if $b ne '';
    }
    $ser1 = decode_utf8($ser1);
    $ser2 = decode_utf8($ser2);
  } elsif(!$o{htmlize}) {
    $ser1 = html_escape $ser1;
    $ser2 = html_escape $ser2;
  }

  $ser1 = '[empty]' if !$ser1 && $ser1 ne '0';
  $ser2 = '[empty]' if !$ser2 && $ser2 ne '0';

  Tr;
   td $display;
   td class => 'tcval'; lit $ser1; end;
   td class => 'tcval'; lit $ser2; end;
  end;
}


# Generates a generic message to show as the header of the edit forms
# Arguments: v/r/p, obj
sub htmlEditMessage {
  my($self, $type, $obj, $title, $copy) = @_;
  my $typename   = {v => 'visual novel', r => 'release', p => 'producer', c => 'character', s => 'person'}->{$type};
  my $guidelines = {v => 2, r => 3, p => 4, c => 12, 's' => 16}->{$type};

  div class => 'mainbox';
   h1 $title;
   if($copy) {
     div class => 'warning';
      h2 'You\'re not editing an entry!';
      p;
       txt 'You\'re about to insert a new entry into the database with information based on ';
       a href => "/$type$obj->{id}", $obj->{title}||$obj->{name};
       txt '.';
       br;
       txt 'Hit the \'edit\' tab on the right-top if you intended to edit the entry instead of creating a new one.';
      end;
     end;
   }
   div class => 'notice';
    h2 'Before editing:';
    ul;
     li;
      txt "Read the ";
      a href=> "/d$guidelines", 'guidelines';
      txt '!';
     end;
     if($obj) {
       li;
        txt 'Check for any existing discussions on the ';
        a href => $type =~ /[cs]/ ? '/t/db' : $type eq 'r' ? "/t/v$obj->{vn}[0]{vid}" : "/t/$type$obj->{id}", 'discussion board';
       end;
       li;
        txt 'Browse the ';
        a href => "/$type$obj->{id}/hist", 'edit history';
        txt ' for any recent changes related to what you want to change.';
       end;
     } elsif($type ne 'r') {
       li;
        a href => "/$type/all", 'Search the database';
        txt " to see if we already have information about this $typename.";
       end;
     }
    end;
   end;
   if($obj && !$obj->{lastrev}) {
     div class => 'warning';
      h2 'Reverting';
      p "You are editing an old revision of this $typename. If you save it, all changes made after this revision will be reverted!";
     end;
   }
  end 'div';
}


# Generates a small message when the user can't edit the item,
# or the item is locked.
# Arguments: v/r/p/c, obj
sub htmlItemMessage {
  my($self, $type, $obj) = @_;
  # $type isn't being used at all... oh well.

  if($obj->{locked}) {
    p class => 'locked', 'Locked for editing';
  } elsif($self->authInfo->{id} && !$self->authCan('edit')) {
    p class => 'locked', 'You are not allowed to edit this page';
  }
}


# generates two tables, one with a vote graph, other with recent votes
sub htmlVoteStats {
  my($self, $type, $obj, $stats) = @_;

  my($max, $count, $total) = (0, 0, 0);
  for (0..$#$stats) {
    $max = $stats->[$_][0] if $stats->[$_][0] > $max;
    $count += $stats->[$_][0];
    $total += $stats->[$_][1];
  }
  div class => 'votestats';
   table class => 'votegraph';
    thead; Tr;
     td colspan => 2, 'Vote stats';
    end; end;
    tfoot; Tr;
     td colspan => 2, sprintf '%d vote%s total, average %.2f%s', $count, $count == 1 ? '' : 's', $total/$count/10,
       $type eq 'v' ? ' ('.fmtrating(ceil($total/$count/10-1)||1).')' : '';
    end; end;
    for (reverse 0..$#$stats) {
      Tr;
      td class => 'number', $_+1;
       td class => 'graph';
        div style => 'width: '.($stats->[$_][0]/$max*250).'px', ' ';
        txt $stats->[$_][0];
       end;
      end;
    }
   end 'table';

   my $recent = $self->dbVoteGet(
     $type.'id' => $obj->{id},
     results => 8,
     what => $type eq 'v' ? 'user' : 'vn',
     hide => $type eq 'v',
     hide_ign => $type eq 'v',
   );
   if(@$recent) {
     table class => 'recentvotes stripe';
      thead; Tr;
       td colspan => 3;
        txt 'Recent votes';
        b;
         txt '(';
         a href => "/$type$obj->{id}/votes", 'show all';
         txt ')';
        end;
       end;
      end; end;
      for (@$recent) {
        Tr;
         td;
          if($type eq 'u') {
            a href => "/v$_->{vid}", title => $_->{original}||$_->{title}, shorten $_->{title}, 40;
          } else {
            a href => "/u$_->{uid}", $_->{username};
          }
         end;
         td fmtvote $_->{vote};
         td fmtdate $_->{date};
        end;
      }
     end 'table';
   }

   clearfloat;
   if($type eq 'v' && $obj->{c_votecount}) {
     div;
      h3 'Ranking';
      p sprintf 'Popularity: ranked #%d with a score of %.2f', $obj->{p_ranking}, ($obj->{c_popularity}||0)*100;
      p sprintf 'Bayesian rating: ranked #%d with a rating of %.2f', $obj->{r_ranking}, $obj->{c_rating}/10;
     end;
   }
  end 'div';
}


sub htmlSearchBox {
  my($self, $sel, $v) = @_;

  fieldset class => 'search';
   p id => 'searchtabs';
    a href => '/v/all', $sel eq 'v' ? (class => 'sel') : (), 'Visual novels';
    a href => '/r',     $sel eq 'r' ? (class => 'sel') : (), 'Releases';
    a href => '/p/all', $sel eq 'p' ? (class => 'sel') : (), 'Producers';
    a href => '/s/all', $sel eq 's' ? (class => 'sel') : (), 'Staff';
    a href => '/c/all', $sel eq 'c' ? (class => 'sel') : (), 'Characters';
    a href => '/g',     $sel eq 'g' ? (class => 'sel') : (), 'Tags';
    a href => '/i',     $sel eq 'i' ? (class => 'sel') : (), 'Traits';
    a href => '/u/all', $sel eq 'u' ? (class => 'sel') : (), 'Users';
   end;
   input type => 'text', name => 'q', id => 'q', class => 'text', value => $v;
   input type => 'submit', class => 'submit', value => 'Search!';
  end 'fieldset';
}


sub htmlRGHeader {
  my($self, $title, $type, $obj) = @_;

  # This used to be a good test for inline SVG support, but I'm not sure it is nowadays.
  if(($self->reqHeader('Accept')||'') !~ /application\/xhtml\+xml/) {
    $self->htmlHeader(title => $title);
    $self->htmlMainTabs($type, $obj, 'rg');
    div class => 'mainbox';
     h1 $title;
     div class => 'warning';
      h2 'Not supported';
      p 'Your browser sucks, it doesn\'t have the functionality to render our nice relation graphs.';
     end;
    end;
    $self->htmlFooter;
    return 1;
  }
  $self->htmlHeader(title => $title);
  $self->htmlMainTabs($type, $obj, 'rg');
  return 0;
}


1;
