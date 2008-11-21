
package VNDB::Util::CommonHTML;

use strict;
use warnings;
use YAWF ':html', 'xml_escape';
use Exporter 'import';
use Algorithm::Diff::XS 'compact_diff';
use VNDB::Func;
use Encode 'encode_utf8', 'decode_utf8';

our @EXPORT = qw|htmlMainTabs htmlDenied htmlHiddenMessage htmlBrowse htmlBrowseNavigate htmlRevision|;


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
# Arguments: page url, current page (1..n), nextpage (0/1), alignment (t/b), noappend (0/1)
sub htmlBrowseNavigate {
  my($self, $url, $p, $np, $al, $na) = @_;
  return if $p == 1 && !$np;

  $url .= $url =~ /\?/ ? '&p=' : '?p=' unless $na;
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


1;
