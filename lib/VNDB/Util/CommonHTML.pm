
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
   if($type =~ /[uvrpc]/) {
     li $sel eq 'hist' ? (class => 'tabselected') : ();
      a href => "/$id/hist", mt '_mtabs_hist';
     end;
   }

   if($type =~ /[uvp]/) {
     my $cnt = $self->dbThreadCount($type, $obj->{id});
     li $sel eq 'disc' ? (class => 'tabselected') : ();
      a href => "/t/$id", mt '_mtabs_discuss', $cnt;
     end;
   }

   if($type eq 'u') {
     li $sel eq 'posts' ? (class => 'tabselected') : ();
      a href => "/$id/posts", mt '_mtabs_posts';
     end;
   }

   if($type eq 'u' && (!($obj->{hide_list} || $obj->{prefs}{hide_list}) || ($self->authInfo->{id} && $self->authInfo->{id} == $obj->{id}) || $self->authCan('usermod'))) {
     li $sel eq 'wish' ? (class => 'tabselected') : ();
      a href => "/$id/wish", mt '_mtabs_wishlist';
     end;

     li $sel eq 'votes' ? (class => 'tabselected') : ();
      a href => "/$id/votes", mt '_mtabs_votes';
     end;

     li $sel eq 'list' ? (class => 'tabselected') : ();
      a href => "/$id/list", mt '_mtabs_list';
     end;
   }

   if($type eq 'v' && $self->authCan('tag') && !$obj->{hidden}) {
     li $sel eq 'tagmod' ? (class => 'tabselected') : ();
      a href => "/$id/tagmod", mt '_mtabs_tagmod';
     end;
   }

   if($type eq 'r' && $self->authCan('edit') || $type eq 'c' && $self->authCan('charedit')) {
     li $sel eq 'copy' ? (class => 'tabselected') : ();
      a href => "/$id/copy", mt '_mtabs_copy';
     end;
   }

   if(   $type eq 'u'     && ($self->authInfo->{id} && $obj->{id} == $self->authInfo->{id} || $self->authCan('usermod'))
      || $type =~ /[vrp]/ && $self->authCan('edit') && ((!$obj->{locked} && !$obj->{hidden}) || $self->authCan('dbmod'))
      || $type eq 'c'     && $self->authCan('charedit') && ((!$obj->{locked} && !$obj->{hidden}) || $self->authCan('dbmod'))
      || $type =~ /[gi]/  && $self->authCan('tagmod')
   ) {
     li $sel eq 'edit' ? (class => 'tabselected') : ();
      a href => "/$id/edit", mt '_mtabs_edit';
     end;
   }

   if($type eq 'u' && $self->authCan('usermod')) {
     li $sel eq 'del' ? (class => 'tabselected') : ();
      a href => "/$id/del", mt '_js_remove';
     end;
   }

   if($type =~ /[vp]/ && $obj->{rgraph}) {
     li $sel eq 'rg' ? (class => 'tabselected') : ();
      a href => "/$id/rg", mt '_mtabs_relations';
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
  $self->htmlHeader(title => mt '_denied_title');
  div class => 'mainbox';
   h1 mt '_denied_title';
   div class => 'warning';
    if(!$self->authInfo->{id}) {
      h2 mt '_denied_needlogin_title';
      p; lit mt '_denied_needlogin_msg'; end;
    } else {
      h2 mt '_denied_noaccess_title';
      p mt '_denied_noaccess_msg';
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
  my $board = $type eq 'c' ? 'db' : $type eq 'r' ? 'v'.$obj->{vn}[0]{vid} : $type.$obj->{id};
  # fetch edit summary (not present in $obj because the changes aren't fetched)
  my $editsum = $type eq 'v' ? $self->dbVNGet(id => $obj->{id}, what => 'changes')->[0]{comments}
              : $type eq 'r' ? $self->dbReleaseGet(id => $obj->{id}, what => 'changes')->[0]{comments}
              : $type eq 'c' ? $self->dbCharGet(id => $obj->{id}, what => 'changes')->[0]{comments}
                             : $self->dbProducerGet(id => $obj->{id}, what => 'changes')->[0]{comments};
  div class => 'mainbox';
   h1 $obj->{title}||$obj->{name};
   div class => 'warning';
    h2 mt '_hiddenmsg_title';
    p;
     lit mt '_hiddenmsg_msg', "/t/$board";
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
   h1 mt '_revision_title', $new->{rev};

   # character information may be rather spoilerous
   if($type eq 'c') {
     div class => 'warning';
      h2 mt '_revision_spoil_title';
      lit mt '_revision_spoil_msg', "/c$new->{id}";
     end;
     br;br;
   }

   # previous/next revision links
   a class => 'prev', href => sprintf('/%s%d.%d', $type, $new->{id}, $new->{rev}-1), '<- '.mt '_revision_previous'
     if $new->{rev} > 1;
   a class => 'next', href => sprintf('/%s%d.%d', $type, $new->{id}, $new->{rev}+1), mt('_revision_next').' ->'
     if $new->{cid} != $new->{latest};
   p class => 'center';
    a href => "/$type$new->{id}", "$type$new->{id}";
   end;

   # no previous revision, just show info about the revision itself
   if(!$old) {
     div class => 'rev';
      revheader($self, $type, $new);
      br;
      b mt '_revision_new_summary';
      br; br;
      lit bb2html($new->{comments})||'-';
     end;
   }

   # otherwise, compare the two revisions
   else {
     table class => 'stripe';
      thead;
       Tr;
        td; lit '&nbsp;'; end;
        td; revheader($self, $type, $old); end;
        td; revheader($self, $type, $new); end;
       end;
       Tr;
        td; lit '&nbsp;'; end;
        td colspan => 2;
         b mt '_revision_edit_summary', $new->{rev};
         br; br;
         lit bb2html($new->{comments})||'-';
        end;
       end;
      end;
      revdiff($type, $old, $new, @$_) for (
        [ ihid   => serialize => sub { mt $_[0] ? '_revision_yes' : '_revision_no' } ],
        [ ilock  => serialize => sub { mt $_[0] ? '_revision_yes' : '_revision_no' } ],
        @fields
      );
     end 'table';
   }
  end 'div';
}

sub revheader { # type, obj
  my($self, $type, $obj) = @_;
  b mt '_revision_title', $obj->{rev};
  txt ' (';
  a href => "/$type$obj->{id}.$obj->{rev}/edit", mt '_mtabs_edit';
  txt ')';
  br;
  lit mt '_revision_user_date', $obj, $obj->{added};
}

sub revdiff {
  my($type, $old, $new, $short, %o) = @_;

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

  $ser1 = mt '_revision_empty' if !$ser1 && $ser1 ne '0';
  $ser2 = mt '_revision_empty' if !$ser2 && $ser2 ne '0';

  Tr;
   td mt $short eq 'ihid' || $short eq 'ilock' ? "_revfield_$short" : "_revfield_${type}_$short";
   td class => 'tcval'; lit $ser1; end;
   td class => 'tcval'; lit $ser2; end;
  end;
}


# Generates a generic message to show as the header of the edit forms
# Arguments: v/r/p, obj
sub htmlEditMessage {
  my($self, $type, $obj, $title, $copy) = @_;
  my $num        = {v => 0, r => 1, p => 2, c => 3}->{$type};
  my $guidelines = {v => 2, r => 3, p => 4, c => 12}->{$type};

  div class => 'mainbox';
   h1 $title;
   if($copy) {
     div class => 'warning';
      h2 mt '_editmsg_copy_title';
      p;
       lit mt '_editmsg_copy_msg', sprintf '<a href="/%s%d">%s</a>', $type, $obj->{id}, xml_escape $obj->{title}||$obj->{name};
      end;
     end;
   }
   div class => 'notice';
    h2 mt '_editmsg_msg_title';
    ul;
     li; lit mt '_editmsg_msg_guidelines', "/d$guidelines"; end;
     if($obj) {
       li; lit mt '_editmsg_msg_discuss', $type eq 'c' ? '/t/db' : $type eq 'r' ? "/t/v$obj->{vn}[0]{vid}" : "/t/$type$obj->{id}"; end;
       li; lit mt '_editmsg_msg_history', "/$type$obj->{id}/hist"; end;
     } elsif($type ne 'r') {
       li; lit mt '_editmsg_msg_search', "/$type/all", $num; end;
     }
    end;
   end;
   if($obj && $obj->{latest} != $obj->{cid}) {
     div class => 'warning';
      h2 mt '_editmsg_revert_title';
      p mt '_editmsg_revert_msg', $num;
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
    p class => 'locked', mt '_itemmsg_locked';
  } elsif(!$self->authInfo->{id}) {
    p class => 'locked';
     lit mt '_itemmsg_login', '/u/login';
    end;
  } elsif(!$self->authCan($type eq 'c' ? 'charedit' : 'edit')) {
    p class => 'locked', mt '_itemmsg_denied';
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
     td colspan => 2, mt '_votestats_title';
    end; end;
    tfoot; Tr;
     td colspan => 2, mt('_votestats_sum', $count, sprintf('%.2f', $total/$count/10))
       .($type eq 'v' ? ' ('.mt('_vote_'.(ceil($total/$count/10-1)||1)).')' : '');
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
        txt mt '_votestats_recent';
        b;
         txt '(';
         a href => "/$type$obj->{id}/votes", mt '_votestats_allvotes';
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
         td $self->{l10n}->date($_->{date});
        end;
      }
     end 'table';
   }

   clearfloat;
   if($type eq 'v' && $obj->{c_votecount}) {
     div;
      h3 mt '_votestats_rank_title';
      p mt '_votestats_rank_pop', $obj->{p_ranking}, sprintf '%.2f', ($obj->{c_popularity}||0)*100;
      p mt '_votestats_rank_rat', $obj->{r_ranking}, sprintf '%.2f', $obj->{c_rating}/10;
     end;
   }
  end 'div';
}


sub htmlSearchBox {
  my($self, $sel, $v) = @_;

  fieldset class => 'search';
   p id => 'searchtabs';
    a href => '/v/all', $sel eq 'v' ? (class => 'sel') : (), mt '_searchbox_vn';
    a href => '/r',     $sel eq 'r' ? (class => 'sel') : (), mt '_searchbox_releases';
    a href => '/p/all', $sel eq 'p' ? (class => 'sel') : (), mt '_searchbox_producers';
    a href => '/c/all', $sel eq 'c' ? (class => 'sel') : (), mt '_searchbox_chars';
    a href => '/g',     $sel eq 'g' ? (class => 'sel') : (), mt '_searchbox_tags';
    a href => '/i',     $sel eq 'i' ? (class => 'sel') : (), mt '_searchbox_traits';
    a href => '/u/all', $sel eq 'u' ? (class => 'sel') : (), mt '_searchbox_users';
   end;
   input type => 'text', name => 'q', id => 'q', class => 'text', value => $v;
   input type => 'submit', class => 'submit', value => mt '_searchbox_submit';
  end 'fieldset';
}


sub htmlRGHeader {
  my($self, $title, $type, $obj) = @_;

  if(($self->reqHeader('Accept')||'') !~ /application\/xhtml\+xml/) {
    $self->htmlHeader(title => $title);
    $self->htmlMainTabs($type, $obj, 'rg');
    div class => 'mainbox';
     h1 $title;
     div class => 'warning';
      h2 mt '_rg_notsupp';
      p mt '_rg_notsupp_msg';
     end;
    end;
    $self->htmlFooter;
    return 1;
  }
  $self->resHeader('Content-Type' => 'application/xhtml+xml; charset=UTF-8');
  $self->htmlHeader(title => $title, svg => 1);
  $self->htmlMainTabs($type, $obj, 'rg');
  return 0;
}


1;
