
package VNDB::Util::CommonHTML;

use strict;
use warnings;
use YAWF ':html', 'xml_escape';
use Exporter 'import';
use Algorithm::Diff 'sdiff';
use VNDB::Func;

our @EXPORT = qw|htmlMainTabs htmlDenied htmlBrowse htmlBrowseNavigate htmlRevision|;


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
     li $sel eq 'disc' ? (class => 'tabselected') : ();
      a href => "/t/$id", 'discussions';
     end;
   }
   
   if($type eq 'u') {
     li $sel eq 'wish' ? (class => 'tabselected') : ();
      a href => "/$id/wish", 'wishlist';
     end;

     li $sel eq 'list' ? (class => 'tabselected') : ();
      a href => "/$id/list", 'list';
     end;
   }

   if($type eq 'u' && ($obj->{id} == $self->authInfo->{id} || $self->authCan('usermod'))
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
sub htmlBrowse {
  my($self, %opt) = @_;

  $opt{sorturl} .= $opt{sorturl} =~ /\?/ ? '&' : '?' if $opt{sorturl};

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
            td class => 'tc'.($_+1);
             lit $opt{header}[$_][0];
             if($opt{header}[$_][1]) {
               lit ' ';
               lit $opt{options}{s} eq $opt{header}[$_][1] && $opt{options}{o} eq 'a' ? "\x{25B4}" : qq|<a href="$opt{sorturl}o=a&s=$opt{header}[$_][1]">\x{25B4}</a>|;
               lit $opt{options}{s} eq $opt{header}[$_][1] && $opt{options}{o} eq 'd' ? "\x{25BE}" : qq|<a href="$opt{sorturl}o=d&s=$opt{header}[$_][1]">\x{25BE}</a>|;
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

   end;
  end;

  # bottom navigation
  $self->htmlBrowseNavigate($opt{pageurl}, $opt{options}{p}, $opt{nextpage}, 'b');
}


# creates next/previous buttons (tabs), if needed
# Arguments: page url, current page (1..n), nextpage (0/1), alignment (t/b)
sub htmlBrowseNavigate {
  my($self, $url, $p, $np, $al) = @_;
  return if $p == 1 && !$np;

  $url .= $url =~ /\?/ ? '&p=' : '?p=';
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
  a href => "/u$obj->{requester}", $obj->{username};
  txt ' on ';
  lit date $obj->{added}, 'full';
}

sub revdiff {
  my($i, $old, $new, $short, $name, %o) = @_;

  my $ser1 = $o{serialize} ? $o{serialize}->($old->{$short}) : $old->{$short};
  my $ser2 = $o{serialize} ? $o{serialize}->($new->{$short}) : $new->{$short};
  return if $ser1 eq $ser2;

  if($o{diff} && $ser1 && $ser2) {
    my($r1,$r2,$ch) = ('','','u');
    for (sdiff([ split //, $ser1 ], [ split //, $ser2 ])) {
      if($ch ne $_->[0]) {
        if($ch ne 'u') {
          $r1 .= '</b>';
          $r2 .= '</b>';
        }
        $r1 .= '<b class="diff_del">' if $_->[0] eq '-' || $_->[0] eq 'c';
        $r2 .= '<b class="diff_add">' if $_->[0] eq '+' || $_->[0] eq 'c';
      }
      $ch = $_->[0];
      $r1 .= xml_escape $_->[1] if $ch ne '+';
      $r2 .= xml_escape $_->[2] if $ch ne '-';
    }
    $r1 .= '</b>' if $ch eq '-' || $ch eq 'c';
    $r2 .= '</b>' if $ch eq '+' || $ch eq 'c';
    $ser1 = $r1;
    $ser2 = $r2;
  } else {
    $ser1 = xml_escape $ser1;
    $ser2 = xml_escape $ser2;
  }

  $ser1 = '[empty]' if !$ser1 && $ser1 ne '0';
  $ser2 = '[empty]' if !$ser2 && $ser2 ne '0';

  Tr $$i++ % 2 ? (class => 'odd') : ();
   td class => 'tcname', $name;
   td; lit $ser1; end;
   td; lit $ser2; end;
  end;
}


1;
