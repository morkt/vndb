
package VNDB::Handler::Search;

use strict;
use warnings;
use Exporter 'import';
use TUWF qw(:html uri_escape);
use VNDB::Func;
use List::Util qw(first);


TUWF::register(
  qr{t/search}          => \&search,
);


sub to_tsquery {
  my($search, $weight) = @_;
  $search =~ s{[!|&:*()="',.;?\\/]}{ }g;
  $weight = $weight ? ":$weight" : '';
  my $min_length = 3;
  my(@and, @or, @not);
  for(split ' ', $search) {
    if    (/^\+(.+)/) { push @and, $1.$weight if length $1 >= $min_length }
    elsif (/^-(.+)/)  { push @not, '! '.$1.$weight if length $1 >= $min_length }
    else              { push @or, $_.$weight  if length >= $min_length }
  }
  push @or, $and[0] if @or && @and;
  my $or = join(' | ', @or);
  $or = "( $or )" if @or > 1 && (@and || @not);
  return join(' & ', $or||(), @and, @not);
}


sub search {
  my $self = shift;

  my $frm = $self->formValidate(
    { get => 'q', required => 0, maxlength => 100 },
    { get => 'u', required => 0, maxlength => 100 },
    { get => 'b', required => 0, multi => 1, enum => [ @{$self->{discussion_boards}} ] },
    { get => 't', required => 0 },
    { get => 'p', required => 0, default => 1, template => 'int' }
  );
  $frm->{b} = undef if !$frm->{_err} && (!@{$frm->{b}} || grep { !$_ } @{$frm->{b}});

  my @users;
  if(!$frm->{_err} && $frm->{u}) {
    @users = split /[ ,]+/, $frm->{u};
    @users = map $_->{id}, @{ $self->dbUserGet(username => \@users) } if @users;
    push @{$frm->{_err}}, 'users' unless @users;
  }

  my ($posts, $np, $tsq);
  if(!$frm->{_err} && $frm->{q}) {
    $tsq = to_tsquery($frm->{q}, $frm->{t} ? 'A' : '');
    push @{$frm->{_err}}, 'shortsearch' unless $tsq;
    if($tsq) {
      ($posts, $np) = $self->dbPostSearch(
        search => $tsq,
        @users ? (uid => \@users) : (),
        $frm->{t} ? (what => 'thread') : (),
        $frm->{b} ? (type => $frm->{b}) : (),
        results => 20,
        page => $frm->{p},
        headline => { StartSel => '[b]', StopSel => '[/b]', MinWords => 10 },
      );
    }
  } elsif(!$frm->{_err} && @users) {
    ($posts, $np) = $self->dbPostGet(
      uid => \@users,
      $frm->{t} ? (num => 1) : (),
      $frm->{b} ? (type => $frm->{b}) : (),
      hide => 1,
      what => 'user thread',
      sort => 'date',
      reverse => 1,
      results => 20,
      page => $frm->{p},
    );
  }
  my $lastq = $self->{_TUWF}{DB}{queries}[-1] if $posts && $self->debug; # XXX remove in production

  my $title = 'Discussion board search'; #mt '_dbsearch_title';
  $self->htmlHeader(title => $title, noindex => 1);

  form action => '/t/search', method => 'get', 'accept-charset' => 'utf-8';
   div class => 'mainbox';
    h1 $title;
    if($posts && !@$posts) {
      div class => 'warning';
       h2 'Nothing found'; #mt '_dbsearch_notfound';
       p;
        lit 'No messages found matching your criteria. Try to refine your query.'; #mt '_dbsearch_nomsg';
       end;
      end;
    } else {
      $self->htmlFormError($frm);
    }
    fieldset class => 'dbsearch';
     table class => 'formtable';
      tbody;
       Tr;
        td colspan => 2, style => 'height: 10px', '';
        td rowspan => 4, style => 'padding-left: 20px';
         label for => 'b', 'Search in the following boards only'; #mt '_dbsearch_boards';
         br;
         Select name => 'b', id => 'b', multiple => 'multiple', size => (1+@{$self->{discussion_boards}}), style => 'width: 160px';
          option value => '', !$frm->{b} ? (selected => 'selected') : (), 'All boards'; #mt '_dboard_all';
          for my $b (@{$self->{discussion_boards}}) {
            my $sel = first { $_ eq $b } @{$frm->{b}} if $frm->{b};
            option value => $b, $sel ? (selected => 'selected') : (), mt("_dboard_$b");
          }
         end;
        end;
       end;
       Tr class => 'newfield';
        td class => 'label', style => 'height: 100%; text-align: right; padding-right: 10px';
         label for => 'q', 'Keywords'; #mt '_dbsearch_keywords';
        end;
        td class => 'field';
         input type => 'text', name => 'q', id => 'q', class => 'text', value => $frm->{q}//'',
           style => 'width: 200px';
        end;
       end;
       Tr class => 'newfield';
        td class => 'label', style => 'height: 100%; text-align: right; padding-right: 10px';
         label for => 'u', 'From users (optional)'; #mt '_dbsearch_authors';
        end;
        td class => 'field';
         input type => 'text', name => 'u', id => 'u', class => 'text', value => $frm->{u}//'';
        end;
       end;
       Tr class => 'newfield';
        td class => 'label'; lit '&nbsp;'; end;
        td class => 'field';
         input type => 'checkbox', name => 't', id => 't', class => 'check', value => 1,
           $frm->{t} ? (checked => 'checked') : ();
         label for => 't', 'Search in thread titles only'; #mt '_dbsearch_thread';
        end;
       end;
       Tr;
        td class => 'label'; lit '&nbsp;'; end;
        td class => 'field', colspan => 2, style => 'vertical-align: bottom';
         input type => 'submit', class => 'submit', style => 'width: 150px', value => 'Search'; #mt('_dbsearch_submit');
        end;
       end;
      end;
     end;
    end 'fieldset';
    if($frm->{q} && $posts && first { $_->{msg} =~ /\[spoiler\]/ } @$posts) {
      div class => 'warning';
       h2 mt '_revision_spoil_title';
       lit 'Search results may contain spoilers.'; #mt '_dbsearch_spoilers'
      end;
    }
    p sprintf('[SQL time: %6.2fms] %s', $lastq->[1]*1000, $tsq ? "[ts_query: $tsq]" : '') if $lastq; # XXX remove in production
   end 'div';
  end 'form';

  if($posts && @$posts) {
    my $url = '/'.$self->reqPath.'?'.join(';',
      $frm->{q} ? 'q='.uri_escape($frm->{q}) : (),
      $frm->{u} ? 'u='.uri_escape($frm->{u}) : (),
      $frm->{b} ? map("b=$_", @{$frm->{b}}) : (),
      $frm->{t} ? 't=1' : ());

    $self->htmlBrowse(
      items    => $posts,
      class    => 'searchres',
      options  => $frm,
      nextpage => $np,
      pageurl  => $url,
      header   => [
        [ '' ],
        [ '' ],
        [ 'User' ], #mt '_search_col_user'
        [ 'Date' ], #mt '_search_col_date'
        [ 'Message' ], #mt '_search_col_msg'
      ],
      row      => sub {
        my($s, $n, $l) = @_;
        my $link = "t$l->{tid}.$l->{num}";
        Tr;
         td class => 'tc1'; a href => "/$link", 't'.$l->{tid}; end;
         td class => 'tc2'; a href => "/$link", '.'.$l->{num}; end;
         td class => 'tc3'; a href => "/u$l->{uid}", $l->{username}; end;
         td class => 'tc4', $self->{l10n}->date($l->{date});
         td class => 'tc5';
          div class => 'title';
           a href => "/$link";
            lit bb2html $l->{title};
           end;
          end;
          div class => 'thread';
           if(exists $l->{headline}) {
             my $msg = bb2html($l->{headline}, 300);
             $msg .= ' ...' unless $msg =~ /\.\.\.$/;
             lit $msg;
           } else {
             lit bb2html($l->{msg}, 300);
           }
           b class => 'grayedout', style => 'float: right; font-style: italic; margin-right: 8px',
             'Rank: '.$l->{rank} if defined $l->{rank} && $self->debug; # XXX remove in production
          end;
         end;
        end;
      }
    );
  }
  $self->htmlFooter;
}


1;

