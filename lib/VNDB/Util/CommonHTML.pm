
package VNDB::Util::CommonHTML;

use strict;
use warnings;
use YAWF ':html';
use Exporter 'import';

our @EXPORT = qw|htmlMainTabs htmlDenied htmlBrowse|;


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

   if($type eq 'u' && ($obj->{id} == $self->authInfo->{id} || $self->authCan('usermod'))) {
     li $sel eq 'edit' ? (class => 'tabselected') : ();
      a href => "/$id/edit", 'edit';
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
#  sorturl  => base URL to append the sort options to
#  pageurl  => base URL to append the page option to
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

  $opt{sorturl} .= $opt{sorturl} =~ /\?/ ? '&' : '?';
  $opt{pageurl} .= $opt{pageurl} =~ /\?/ ? '&p=' : '?p=';

  # top navigation
  if($opt{options}{p} > 1 || $opt{nextpage}) {
    ul class => 'maintabs notfirst';
     if($opt{options}{p} > 1) {
       li class => 'left';
        a href => $opt{pageurl}.($opt{options}{p}-1), '<- previous';
       end;
     }
     if($opt{nextpage}) {
       li;
        a href => $opt{pageurl}.($opt{options}{p}+1), 'next ->';
       end;
     }
    end;
  }

  div class => 'mainbox browse';
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
  if($opt{options}{p} > 1 || $opt{nextpage}) {
    ul class => 'maintabs bottom';
     if($opt{options}{p} > 1) {
       li class => 'left';
        a href => $opt{pageurl}.($opt{options}{p}-1), '<- previous';
       end;
     }
     if($opt{nextpage}) {
       li;
        a href => $opt{pageurl}.($opt{options}{p}+1), 'next ->';
       end;
     }
    end;
  } 
}


1;
