
package VNDB::Util::BrowseHTML;

use strict;
use warnings;
use YAWF ':html', 'xml_escape';
use Exporter 'import';
use VNDB::Func;


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
            td class => $opt{header}[$_][3]||'tc'.($_+1), $opt{header}[$_][2] ? (colspan => $opt{header}[$_][2]) : ();
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

   # footer
    if($opt{footer}) {
      tfoot;
       $opt{footer}->($self);
      end;
    }

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

  $url .= $url =~ /\?/ ? ';p=' : '?p=' unless $na;
  ul class => 'maintabs ' . ($al eq 't' ? 'notfirst' : 'bottom');
   if($p > 1) {
     li class => 'left';
      a href => $url.($p-1), '<- '.mt '_browse_previous';
     end;
   }
   if($np) {
     li;
      a href => $url.($p+1), mt('_browse_next').' ->';
     end;
   }
  end;
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
      sub { td colspan => 2, class => 'tc1', mt '_hist_col_rev' },
      [ mt '_hist_col_date' ],
      [ mt '_hist_col_user' ],
      sub { td; a href => '#', id => 'expandlist', mt '_js_expand'; txt mt '_hist_col_page'; end; }
    ],
    row      => sub {
      my($s, $n, $i) = @_;
      my $revurl = "/$i->{type}$i->{iid}.$i->{rev}";

      Tr $n % 2 ? ( class => 'odd' ) : ();
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
       td;
        a href => $revurl, title => $i->{ioriginal}, shorten $i->{ititle}, 80;
       end;
      end;
      if($i->{comments}) {
        Tr class => $n % 2 ? 'collapse msgsum odd hidden' : 'collapse msgsum hidden';
         td colspan => 5;
          lit bb2html $i->{comments}, 150;
         end;
        end;
      }
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
      [ '',                              0,       undef, 'tc2' ],
      [ '',                              0,       undef, 'tc3' ],
      [ mt('_vnbrowse_col_released'),    'rel',   undef, 'tc4' ],
      [ mt('_vnbrowse_col_popularity'),  'pop',   undef, 'tc5' ],
      [ mt('_vnbrowse_col_rating'),      'rating', undef, 'tc6' ],
    ],
    row     => sub {
      my($s, $n, $l) = @_;
      Tr $n % 2 ? (class => 'odd') : ();
       if($tagscore) {
         td class => 'tc_s';
          tagscore $l->{tagscore}, 0;
         end;
       }
       td class => $tagscore ? 'tc_t' : 'tc1';
        a href => '/v'.$l->{id}, title => $l->{original}||$l->{title}, shorten $l->{title}, 100;
       end;
       td class => 'tc2';
        $_ ne 'oth' && cssicon $_, mt "_plat_$_"
          for (sort split /\//, $l->{c_platforms});
       end;
       td class => 'tc3';
        cssicon "lang $_", mt "_lang_$_"
          for (reverse sort split /\//, $l->{c_languages});
       end;
       td class => 'tc4';
        lit $self->{l10n}->datestr($l->{c_released});
       end;
       td class => 'tc5', sprintf '%.2f', ($l->{c_popularity}||0)*100;
       td class => 'tc6';
        txt sprintf '%.2f', $l->{c_rating}||0;
        b class => 'grayedout', sprintf ' (%d)', $l->{c_votecount};
       end;
      end;
    },
  );
}


1;

