
package VNDB::Util::BrowseHTML;

use strict;
use warnings;
use TUWF ':html', 'xml_escape';
use Exporter 'import';
use VNDB::Func;
use POSIX 'ceil';


our @EXPORT = qw| htmlBrowse htmlBrowseNavigate htmlBrowseHist htmlBrowseVN |;


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
  $self->htmlBrowseNavigate($opt{pageurl}, $opt{options}{p}, $opt{nextpage}, 't') if $opt{pageurl};

  div class => 'mainbox browse'.($opt{class} ? ' '.$opt{class} : '');
   table class => 'stripe';

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
            td class => $opt{header}[$_][3]||'tc'.($_+1), $opt{header}[$_][2] ? (colspan => $opt{header}[$_][2]) : ();
             lit $opt{header}[$_][0];
             if($opt{header}[$_][1]) {
               lit ' ';
               $opt{options}{s} eq $opt{header}[$_][1] && $opt{options}{o} eq 'a' ? lit "\x{25B4}" : a href => "$opt{sorturl}o=a;s=$opt{header}[$_][1]", "\x{25B4}";
               $opt{options}{s} eq $opt{header}[$_][1] && $opt{options}{o} eq 'd' ? lit "\x{25BE}" : a href => "$opt{sorturl}o=d;s=$opt{header}[$_][1]", "\x{25BE}";
             }
            end;
          }
        }
      }
     end;
    end 'thead';

   # footer
    if($opt{footer}) {
      tfoot;
       $opt{footer}->($self);
      end;
    }

   # rows
    $opt{row}->($self, $_+1, $opt{items}[$_])
      for 0..$#{$opt{items}};

   end 'table';
  end 'div';

  # bottom navigation
  $self->htmlBrowseNavigate($opt{pageurl}, $opt{options}{p}, $opt{nextpage}, 'b') if $opt{pageurl};
}


# creates next/previous buttons (tabs), if needed
# Arguments: page url, current page (1..n), nextpage (0/1 or [$total, $perpage]), alignment (t/b), noappend (0/1)
sub htmlBrowseNavigate {
  my($self, $url, $p, $np, $al, $na) = @_;
  my($cnt, $pp) = ref($np) ? @$np : ($p+$np, 1);
  return if $p == 1 && $cnt <= $pp;

  $url .= $url =~ /\?/ ? ';p=' : '?p=' unless $na;

  my $tab = sub {
    my($left, $page, $label) = @_;
    li $left ? (class => 'left') : ();
     a href => $url.$page; lit $label; end;
    end;
  };
  my $ell = sub {
    use utf8;
    li class => 'ellipsis'.(shift() ? ' left' : '');
     b '⋯';
    end;
  };
  my $nc = 5; # max. number of buttons on each side

  ul class => 'maintabs browsetabs ' . ($al eq 't' ? 'notfirst' : 'bottom');
   $p > 2     and ref $np and $tab->(1, 1, '&laquo; '.mt '_browse_first');
   $p > $nc+1 and ref $np and $ell->(1);
   $p > $_    and ref $np and $tab->(1, $p-$_, $p-$_) for (reverse 2..($nc>$p-2?$p-2:$nc-1));
   $p > 1                 and $tab->(1, $p-1, '&lsaquo; '.mt '_browse_previous');

   my $l = ceil($cnt/$pp)-$p+1;
   $l > 2     and $tab->(0, $l+$p-1, mt('_browse_last').' &raquo;');
   $l > $nc+1 and $ell->(0);
   $l > $_    and $tab->(0, $p+$_, $p+$_) for (reverse 2..($nc>$l-2?$l-2:$nc-1));
   $l > 1     and $tab->(0, $p+1, mt('_browse_next').' &rsaquo;');
  end 'ul';
}


sub htmlBrowseHist {
  my($self, $list, $f, $np, $url) = @_;
  $self->htmlBrowse(
    items    => $list,
    options  => $f,
    nextpage => $np,
    pageurl  => $url,
    class    => 'history',
    header   => [
      sub { td class => 'tc1_1', mt '_hist_col_rev'; td class => 'tc1_2', ''; },
      [ mt '_hist_col_date' ],
      [ mt '_hist_col_user' ],
      [ mt '_hist_col_page' ],
    ],
    row      => sub {
      my($s, $n, $i) = @_;
      my $revurl = "/$i->{type}$i->{iid}.$i->{rev}";

      Tr;
       td class => 'tc1_1';
        a href => $revurl, "$i->{type}$i->{iid}";
       end;
       td class => 'tc1_2';
        a href => $revurl, ".$i->{rev}";
       end;
       td class => 'tc2', $self->{l10n}->date($i->{added});
       td class => 'tc3';
        lit $self->{l10n}->userstr($i);
       end;
       td class => 'tc4';
        a href => $revurl, title => $i->{ioriginal}, shorten $i->{ititle}, 80;
        b class => 'grayedout'; lit bb2html $i->{comments}, 150; end;
       end;
      end 'tr';
    },
  );
}


sub htmlBrowseVN {
  my($self, $list, $f, $np, $url, $tagscore) = @_;
  $self->htmlBrowse(
    class    => 'vnbrowse',
    items    => $list,
    options  => $f,
    nextpage => $np,
    pageurl  => "$url;o=$f->{o};s=$f->{s}",
    sorturl  => $url,
    header   => [
      $tagscore ? [ mt('_vnbrowse_col_score'), 'tagscore', undef, 'tc_s' ] : (),
      [ mt('_vnbrowse_col_title'),       'title', undef, $tagscore ? 'tc_t' : 'tc1' ],
      $f->{vnlist} ? [ '',               0,       undef, 'tc7' ] : (),
      $f->{wish}   ? [ '',               0,       undef, 'tc8' ] : (),
      [ '',                              0,       undef, 'tc2' ],
      [ '',                              0,       undef, 'tc3' ],
      [ mt('_vnbrowse_col_released'),    'rel',   undef, 'tc4' ],
      [ mt('_vnbrowse_col_popularity'),  'pop',   undef, 'tc5' ],
      [ mt('_vnbrowse_col_rating'),      'rating', undef, 'tc6' ],
    ],
    row     => sub {
      my($s, $n, $l) = @_;
      Tr;
       if($tagscore) {
         td class => 'tc_s';
          tagscore $l->{tagscore}, 0;
         end;
       }
       td class => $tagscore ? 'tc_t' : 'tc1';
        a href => '/v'.$l->{id}, title => $l->{original}||$l->{title}, shorten $l->{title}, 100;
       end;
       if($f->{vnlist}) {
         td class => 'tc7';
          lit sprintf '<b class="%s">%d/%d</b>', $l->{userlist_obtained} == $l->{userlist_all} ? 'done' : 'todo', $l->{userlist_obtained}, $l->{userlist_all} if $l->{userlist_all};
         end 'td';
       }
       td class => 'tc8', defined($l->{wstat}) ? mt "_wish_$l->{wstat}" : '' if $f->{wish};
       td class => 'tc2';
        $_ ne 'oth' && cssicon $_, mt "_plat_$_"
          for (sort @{$l->{c_platforms}});
       end;
       td class => 'tc3';
        cssicon "lang $_", mt "_lang_$_"
          for (reverse sort @{$l->{c_languages}});
       end;
       td class => 'tc4';
        lit $self->{l10n}->datestr($l->{c_released});
       end;
       td class => 'tc5', sprintf '%.2f', ($l->{c_popularity}||0)*100;
       td class => 'tc6';
        txt sprintf '%.2f', ($l->{c_rating}||0)/10;
        b class => 'grayedout', sprintf ' (%d)', $l->{c_votecount};
       end;
      end 'tr';
    },
  );
}


1;

