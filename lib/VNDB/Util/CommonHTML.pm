
package VNDB::Util::CommonHTML;

use strict;
use warnings;
use YAWF ':html', 'xml_escape';
use Exporter 'import';
use Algorithm::Diff::XS 'compact_diff';
use VNDB::Func;
use Encode 'encode_utf8', 'decode_utf8';
use POSIX 'ceil';

our @EXPORT = qw|
  htmlMainTabs htmlDenied htmlHiddenMessage htmlRevision
  htmlEditMessage htmlItemMessage htmlVoteStats htmlSearchBox htmlRGHeader
|;


# generates the "main tabs". These are the commonly used tabs for
# 'objects', i.e. VN/producer/release entries and users
# Arguments: u/v/r/p/g, object, currently selected item (empty=main)
sub htmlMainTabs {
  my($self, $type, $obj, $sel) = @_;
  $sel ||= '';
  my $id = $type.$obj->{id};

  return if $type eq 'g' && !$self->authCan('tagmod');

  ul class => 'maintabs';
   if($type =~ /[uvrp]/) {
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

   if($type eq 'u' && ($obj->{show_list} || $self->authCan('usermod'))) {
     li $sel eq 'wish' ? (class => 'tabselected') : ();
      a href => "/$id/wish", mt '_mtabs_wishlist';
     end;

     li $sel eq 'list' ? (class => 'tabselected') : ();
      a href => "/$id/list", mt '_mtabs_list';
     end;
   }

   if($type eq 'u') {
     li $sel eq 'tags' ? (class => 'tabselected') : ();
      a href => "/$id/tags", mt '_mtabs_tags';
     end;
   }

   if($type eq 'v' && $self->authCan('tag') && !$obj->{hidden}) {
     li $sel eq 'tagmod' ? (class => 'tabselected') : ();
      a href => "/$id/tagmod", mt '_mtabs_tagmod';
     end;
   }

   if($type eq 'r' && $self->authCan('edit')) {
     li $sel eq 'copy' ? (class => 'tabselected') : ();
      a href => "/$id/copy", mt '_mtabs_copy';
     end;
   }

   if(   $type eq 'u'     && ($self->authInfo->{id} && $obj->{id} == $self->authInfo->{id} || $self->authCan('usermod'))
      || $type =~ /[vrp]/ && $self->authCan('edit') && (!$obj->{locked} || $self->authCan('lock')) && (!$obj->{hidden} || $self->authCan('del'))
      || $type eq 'g'     && $self->authCan('tagmod')
   ) {
     li $sel eq 'edit' ? (class => 'tabselected') : ();
      a href => "/$id/edit", mt '_mtabs_edit';
     end;
   }

   if($type =~ /[vrp]/ && $self->authCan('del')) {
     li;
      a href => "/$id/hide", mt $obj->{hidden} ? '_mtabs_unhide' : '_mtabs_hide';
     end;
   }

   if($type =~ /[vrp]/ && $self->authCan('lock')) {
     li;
      a href => "/$id/lock", mt $obj->{locked} ? '_mtabs_unlock' : '_mtabs_lock';
     end;
   }

   if($type eq 'u' && $self->authCan('usermod')) {
     li $sel eq 'del' ? (class => 'tabselected') : ();
      a href => "/$id/del", mt '_mtabs_del';
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
  end;
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
  end;
  $self->htmlFooter;
}


# Generates message saying that the current item has been deleted,
# Arguments: [pvr], obj
# Returns 1 if the use doesn't have access to the page, 0 otherwise
sub htmlHiddenMessage {
  my($self, $type, $obj) = @_;
  return 0 if !$obj->{hidden};
  my $board = $type eq 'r' ? 'v'.$obj->{vn}[0]{vid} : $type.$obj->{id};
  div class => 'mainbox';
   h1 $obj->{title}||$obj->{name};
   div class => 'warning';
    h2 mt '_hiddenmsg_title';
    p;
     lit mt '_hiddenmsg_msg', "/t/$board";
    end;
   end;
  end;
  return $self->htmlFooter() || 1 if !$self->authCan('del');
  return 0;
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
   h1 mt '_revision_title', $new->{rev};

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
     div;
      revheader($self, $type, $new);
      br;
      b mt '_revision_new_summary';
      br; br;
      lit bb2html($new->{comments})||'-';
     end;
   }

   # otherwise, compare the two revisions
   else {
     table;
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
      my $i = 1;
      revdiff(\$i, $type, $old, $new, @$_) for (@fields);
     end;
   }
  end;
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
  my($i, $type, $old, $new, $short, %o) = @_;

  $o{serialize} ||= $o{htmlize};
  $o{diff}++ if $o{split};
  $o{join} ||= '';

  my $ser1 = $o{serialize} ? $o{serialize}->($old->{$short}, $old) : $old->{$short};
  my $ser2 = $o{serialize} ? $o{serialize}->($new->{$short}, $new) : $new->{$short};
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
      $ser1 .= ($ser1?$o{join}:'').($i % 2 ? qq|<b class="diff_del">$a</b>| : $a) if $a ne '';
      $ser2 .= ($ser2?$o{join}:'').($i % 2 ? qq|<b class="diff_add">$b</b>| : $b) if $b ne '';
    }
    $ser1 = decode_utf8($ser1);
    $ser2 = decode_utf8($ser2);
  } elsif(!$o{htmlize}) {
    $ser1 = xml_escape $ser1;
    $ser2 = xml_escape $ser2;
  }

  $ser1 = mt '_revision_emptyfield' if !$ser1 && $ser1 ne '0';
  $ser2 = mt '_revision_emptyfield' if !$ser2 && $ser2 ne '0';

  Tr $$i++ % 2 ? (class => 'odd') : ();
   td mt "_revfield_${type}_$short";
   td class => 'tcval'; lit $ser1; end;
   td class => 'tcval'; lit $ser2; end;
  end;
}


# Generates a generic message to show as the header of the edit forms
# Arguments: v/r/p, obj
sub htmlEditMessage {
  my($self, $type, $obj, $title, $copy) = @_;
  my $num        = {v => 0, r => 1, p => 2}->{$type};
  my $guidelines = {v => 2, r => 3, p => 4}->{$type};

  div class => 'mainbox';
   h1 $title;
   if($copy) {
     div class => 'warning';
      h2 mt '_editmsg_copy_title';
      p;
       lit mt '_editmsg_copy_msg', sprintf '<a href="/%s%d">%s</a>', $type, $obj->{id}, xml_escape $obj->{title};
      end;
     end;
   }
   div class => 'notice';
    h2 mt '_editmsg_msg_title';
    ul;
     li; lit mt '_editmsg_msg_guidelines', "/d$guidelines"; end;
     if($obj) {
       li; lit mt '_editmsg_msg_discuss', $type eq 'r' ? "/t/v$obj->{vn}[0]{vid}" : "/t/$type$obj->{id}"; end;
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
  end;
}


# Generates a small message when the user can't edit the item,
# or the item is locked.
# Arguments: v/r/p, obj
sub htmlItemMessage {
  my($self, $type, $obj) = @_;

  if($obj->{locked}) {
    p class => 'locked', mt '_itemmsg_locked';
  } elsif(!$self->authInfo->{id}) {
    p class => 'locked';
     lit mt '_itemmsg_login', '/u/login';
    end;
  } elsif(!$self->authCan('edit')) {
    p class => 'locked', mt '_itemmsg_denied';
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
     td colspan => 2, mt '_votestats_title';
    end; end;
    tfoot; Tr;
     td colspan => 2, mt('_votestats_sum', $count, sprintf('%.2f', $total/$count))
       .($type eq 'v' ? ' ('.mt('_vote_'.(ceil($total/$count-1)||1)).')' : '');
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
   end;

   my $recent = $self->dbVoteGet(
     $type.'id' => $obj->{id},
     results => 8,
     what => $type eq 'v' ? 'user' : 'vn',
     hide => $type eq 'v',
     hide_ign => $type eq 'v',
   );
   if(@$recent) {
     table class => 'recentvotes';
      thead; Tr;
       td colspan => 3, mt '_votestats_recent';
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
         td $self->{l10n}->date($recent->[$_]{date});
        end;
      }
     end;
   }

   clearfloat;
   if($type eq 'v' && $obj->{c_votecount}) {
     div;
      h3 mt '_votestats_rank_title';
      p mt '_votestats_rank_pop', $obj->{p_ranking}, sprintf '%.2f', ($obj->{c_popularity}||0)*100;
      p mt '_votestats_rank_rat', $obj->{r_ranking}, sprintf '%.2f', $obj->{c_rating};
     end;
   }
  end;
}


sub htmlSearchBox {
  my($self, $sel, $v) = @_;

  # escape search query for use as a query string value
  (my $q = $v||'') =~ s/&/%26/g;
  $q =~ s/\?/%3F/g;
  $q =~ s/;/%3B/g;
  $q =~ s/ /%20/g;
  $q = "?q=$q" if $q;

  fieldset class => 'search';
   p class => 'searchtabs';
    a href => "/v/all$q", $sel eq 'v' ? (class => 'sel') : (), mt '_searchbox_vn';
    a href => "/r$q",     $sel eq 'r' ? (class => 'sel') : (), mt '_searchbox_releases';
    a href => "/p/all$q", $sel eq 'p' ? (class => 'sel') : (), mt '_searchbox_producers';
    a href => '/g'.($q?"/list$q":''), $sel eq 'g' ? (class => 'sel') : (), mt '_searchbox_tags';
    a href => "/u/all$q", $sel eq 'u' ? (class => 'sel') : (), mt '_searchbox_users';
   end;
   input type => 'text', name => 'q', id => 'q', class => 'text', value => $v;
   input type => 'submit', class => 'submit', value => mt '_searchbox_submit';
  end;
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

  # This is a REALLY ugly hack, need find a proper solution in YAWF
  no warnings 'redefine';
  my $sub = \&YAWF::XML::html;
  *YAWF::XML::html = sub () {
     lit q|<!DOCTYPE html PUBLIC
         "-//W3C//DTD XHTML 1.1 plus MathML 2.0 plus SVG 1.1//EN"
             "http://www.w3.org/2002/04/xhtml-math-svg/xhtml-math-svg.dtd">|;
     tag 'html',
       xmlns         => "http://www.w3.org/1999/xhtml",
       'xmlns:svg'   => 'http://www.w3.org/2000/svg',
       'xmlns:xlink' => 'http://www.w3.org/1999/xlink';
  };
  $self->htmlHeader(title => $title);
  *YAWF::XML::html = $sub;
  $self->htmlMainTabs($type, $obj, 'rg');
  return 0;
}


1;
