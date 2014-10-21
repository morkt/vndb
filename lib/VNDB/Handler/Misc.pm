
package VNDB::Handler::Misc;


use strict;
use warnings;
use TUWF ':html', ':xml', 'xml_escape', 'uri_escape';
use VNDB::Func;
use POSIX 'strftime';


TUWF::register(
  qr{},                              \&homepage,
  qr{(?:([upvrc])([1-9]\d*)/)?hist}, \&history,
  qr{d([1-9]\d*)},                   \&docpage,
  qr{setlang},                       \&setlang,
  qr{nospam},                        \&nospam,
  qr{xml/prefs\.xml},                \&prefs,
  qr{opensearch\.xml},               \&opensearch,

  # redirects for old URLs
  qr{u([1-9]\d*)/tags}, sub { $_[0]->resRedirect("/g/links?u=$_[1]", 'perm') },
  qr{(.*[^/]+)/+}, sub { $_[0]->resRedirect("/$_[1]", 'perm') },
  qr{([pv])},      sub { $_[0]->resRedirect("/$_[1]/all", 'perm') },
  qr{v/search},    sub { $_[0]->resRedirect("/v/all?q=".uri_escape($_[0]->reqGet('q')||''), 'perm') },
  qr{notes},       sub { $_[0]->resRedirect('/d8', 'perm') },
  qr{faq},         sub { $_[0]->resRedirect('/d6', 'perm') },
  qr{v([1-9]\d*)/(?:stats|scr)},
    sub { $_[0]->resRedirect("/v$_[1]", 'perm') },
  qr{u/list(/[a-z0]|/all)?},
    sub { my $l = defined $_[1] ? $_[1] : '/all'; $_[0]->resRedirect("/u$l", 'perm') },
  qr{d([1-9]\d*)\.([1-9]\d*)},
    sub { $_[0]->resRedirect("/d$_[1]#$_[2]", 'perm') }
);


sub homepage {
  my $self = shift;
  $self->htmlHeader(title => mt('_site_title'), feeds => [ keys %{$self->{atom_feeds}} ]);

  div class => 'mainbox';
   h1 mt '_site_title';
   p class => 'description';
    lit mt '_home_intro';
   end;

   # with filters applied it's signifcantly slower, so special-code the situations with and without filters
   my @vns;
   if($self->authPref('filter_vn')) {
     my $r = $self->filFetchDB(vn => undef, undef, {hasshot => 1, results => 4, sort => 'rand'});
     @vns = map $_->{id}, @$r;
   }
   my $scr = $self->dbScreenshotRandom(@vns);
   p class => 'screenshots';
    for (@$scr) {
      my($w, $h) = imgsize($_->{width}, $_->{height}, @{$self->{scr_size}});
      a href => "/v$_->{vid}", title => $_->{title};
       img src => imgurl(st => $_->{scr}), alt => $_->{title}, width => $w, height => $h;
      end;
    }
   end;
  end 'div';

  table class => 'mainbox threelayout';
   Tr;

    # Recent changes
    td;
     h1;
      a href => '/hist', mt '_home_recentchanges'; txt ' ';
      a href => '/feeds/changes.atom'; cssicon 'feed', mt '_atom_feed'; end;
     end;
     my $changes = $self->dbRevisionGet(what => 'item user', results => 10, auto => 1);
     ul;
      for (@$changes) {
        li;
         lit mt '_home_recentchanges_item', $_->{type},
          sprintf('<a href="%s" title="%s">%s</a>', "/$_->{type}$_->{iid}.$_->{rev}",
            xml_escape($_->{ioriginal}||$_->{ititle}), xml_escape shorten $_->{ititle}, 33),
          $_;
        end;
      }
     end;
    end 'td';

    # Announcements
    td;
     my $an = $self->dbThreadGet(type => 'an', sort => 'id', reverse => 1, results => 2);
     h1;
      a href => '/t/an', mt '_home_announcements'; txt ' ';
      a href => '/feeds/announcements.atom'; cssicon 'feed', mt '_atom_feed'; end;
     end;
     for (@$an) {
       my $post = $self->dbPostGet(tid => $_->{id}, num => 1)->[0];
       h2;
        a href => "/t$_->{id}", $_->{title};
       end;
       p;
        lit bb2html $post->{msg}, 150;
       end;
     }
    end 'td';

    # Recent posts
    td;
     h1;
      a href => '/t/all', mt '_home_recentposts'; txt ' ';
      a href => '/feeds/posts.atom'; cssicon 'feed', mt '_atom_feed'; end;
     end;
     my $posts = $self->dbThreadGet(what => 'lastpost boardtitles', results => 10, sort => 'lastpost', reverse => 1, notusers => 1);
     ul;
      for (@$posts) {
        my $boards = join ', ', map mt("_dboard_$_->{type}").($_->{iid}?' > '.$_->{title}:''), @{$_->{boards}};
        li;
         lit mt '_home_recentposts_item', $_->{ldate},
          sprintf('<a href="%s" title="%s">%s</a>', "/t$_->{id}.$_->{count}",
            xml_escape("Posted in $boards"), xml_escape shorten $_->{title}, 25),
          {uid => $_->{luid}, username => $_->{lusername}};
        end;
      }
     end;
    end 'td';

   end 'tr';
   Tr;

    # Random visual novels
    td;
     h1;
      a href => '/v/rand', mt '_home_randomvn';
     end;
     my $random = $self->filFetchDB(vn => undef, undef, {results => 10, sort => 'rand'});
     ul;
      for (@$random) {
        li;
         a href => "/v$_->{id}", title => $_->{original}||$_->{title}, shorten $_->{title}, 40;
        end;
      }
     end;
    end 'td';

    # Upcoming releases
    td;
     h1;
      a href => '/r?fil=released-0;o=a;s=released', mt '_home_upcoming';
     end;
     my $upcoming = $self->filFetchDB(release => undef, undef, {results => 10, released => 0, what => 'platforms'});
     ul;
      for (@$upcoming) {
        li;
         lit $self->{l10n}->datestr($_->{released});
         txt ' ';
         cssicon $_, mt "_plat_$_" for (@{$_->{platforms}});
         cssicon "lang $_", mt "_lang_$_" for (@{$_->{languages}});
         txt ' ';
         a href => "/r$_->{id}", title => $_->{original}||$_->{title}, shorten $_->{title}, 30;
        end;
      }
     end;
    end 'td';

    # Just released
    td;
     h1;
      a href => '/r?fil=released-1;o=d;s=released', mt '_home_justreleased';
     end;
     my $justrel = $self->filFetchDB(release => undef, undef, {results => 10, sort => 'released', reverse => 1, released => 1, what => 'platforms'});
     ul;
      for (@$justrel) {
        li;
         lit $self->{l10n}->datestr($_->{released});
         txt ' ';
         cssicon $_, mt "_plat_$_" for (@{$_->{platforms}});
         cssicon "lang $_", mt "_lang_$_" for (@{$_->{languages}});
         txt ' ';
         a href => "/r$_->{id}", title => $_->{original}||$_->{title}, shorten $_->{title}, 30;
        end;
      }
     end;
    end 'td';

   end 'tr';
  end 'table';

  $self->htmlFooter;
}


sub history {
  my($self, $type, $id) = @_;
  $type ||= '';
  $id ||= 0;

  my $f = $self->formValidate(
    { get => 'p', required => 0, default => 1, template => 'int' },
    { get => 'm', required => 0, default => !$type, enum => [ 0, 1 ] },
    { get => 'h', required => 0, default => 0, enum => [ -1..1 ] },
    { get => 't', required => 0, default => '', enum => [qw|v r p c a|] },
    { get => 'e', required => 0, default => 0, enum => [ -1..1 ] },
    { get => 'r', required => 0, default => 0, enum => [ 0, 1 ] },
  );
  return $self->resNotFound if $f->{_err};

  # get item object and title
  my $obj = $type eq 'u' ? $self->dbUserGet(uid => $id, what => 'hide_list')->[0] :
            $type eq 'p' ? $self->dbProducerGet(id => $id)->[0] :
            $type eq 'r' ? $self->dbReleaseGet(id => $id)->[0] :
            $type eq 'c' ? $self->dbCharGet(id => $id)->[0] :
            $type eq 'v' ? $self->dbVNGet(id => $id)->[0] : undef;
  my $title = mt $type ? ('_hist_title_item', $obj->{title} || $obj->{name} || $obj->{username}) : '_hist_title';
  return $self->resNotFound if $type && !$obj->{id};

  # get the edit history
  my($list, $np) = $self->dbRevisionGet(
    what => 'item user',
    $type && $type ne 'u' ? ( type => $type, iid => $id ) : (),
    $type eq 'u' ? ( uid => $id ) : (),
    $f->{t} ? ( type => $f->{t} eq 'a' ? [qw|v r p|] : $f->{t} ) : (),
    page => $f->{p},
    results => 50,
    auto => $f->{m},
    hidden => $type && $type ne 'u' ? 0 : $f->{h},
    edit => $f->{e},
    releases => $f->{r},
  );

  $self->htmlHeader(title => $title, noindex => 1, feeds => [ 'changes' ]);
  $self->htmlMainTabs($type, $obj, 'hist') if $type;

  # url generator
  my $u = sub {
    my($n, $v) = @_;
    $n ||= '';
    local $_ = ($type ? "/$type$id" : '').'/hist';
    $_ .= '?m='.($n eq 'm' ? $v : $f->{m});
    $_ .= ';h='.($n eq 'h' ? $v : $f->{h});
    $_ .= ';t='.($n eq 't' ? $v : $f->{t});
    $_ .= ';e='.($n eq 'e' ? $v : $f->{e});
    $_ .= ';r='.($n eq 'r' ? $v : $f->{r});
  };

  # filters
  div class => 'mainbox';
   h1 $title;
   if($type ne 'u') {
     p class => 'browseopts';
      a !$f->{m} ? (class => 'optselected') : (), href => $u->(m => 0), mt '_hist_filter_showauto';
      a  $f->{m} ? (class => 'optselected') : (), href => $u->(m => 1), mt '_hist_filter_hideauto';
     end;
   }
   if(!$type || $type eq 'u') {
     if($self->authCan('dbmod')) {
       p class => 'browseopts';
        a $f->{h} == 1  ? (class => 'optselected') : (), href => $u->(h =>  1), mt '_hist_filter_hidedel';
        a $f->{h} == -1 ? (class => 'optselected') : (), href => $u->(h => -1), mt '_hist_filter_showdel';
       end;
     }
     p class => 'browseopts';
      a !$f->{t}        ? (class => 'optselected') : (), href => $u->(t => ''),  mt '_hist_filter_alltypes';
      a  $f->{t} eq 'v' ? (class => 'optselected') : (), href => $u->(t => 'v'), mt '_hist_filter_onlyvn';
      a  $f->{t} eq 'r' ? (class => 'optselected') : (), href => $u->(t => 'r'), mt '_hist_filter_onlyreleases';
      a  $f->{t} eq 'p' ? (class => 'optselected') : (), href => $u->(t => 'p'), mt '_hist_filter_onlyproducers';
      a  $f->{t} eq 'c' ? (class => 'optselected') : (), href => $u->(t => 'c'), mt '_hist_filter_onlychars';
      a  $f->{t} eq 'a' ? (class => 'optselected') : (), href => $u->(t => 'a'), mt '_hist_filter_nochars';
     end;
     p class => 'browseopts';
      a !$f->{e}       ? (class => 'optselected') : (), href => $u->(e =>  0), mt '_hist_filter_allactions';
      a  $f->{e} == 1  ? (class => 'optselected') : (), href => $u->(e =>  1), mt '_hist_filter_onlyedits';
      a  $f->{e} == -1 ? (class => 'optselected') : (), href => $u->(e => -1), mt '_hist_filter_onlynew';
     end;
   }
   if($type eq 'v') {
     p class => 'browseopts';
      a !$f->{r} ? (class => 'optselected') : (), href => $u->(r => 0), mt '_hist_filter_exrel';
      a $f->{r}  ? (class => 'optselected') : (), href => $u->(r => 1), mt '_hist_filter_increl';
     end;
   }
  end 'div';

  $self->htmlBrowseHist($list, $f, $np, $u->());
  $self->htmlFooter;
}


sub docpage {
  my($self, $did) = @_;

  my $l = '.'.$self->{l10n}->language_tag();
  my $f = sprintf('%s/data/docs/%d', $VNDB::ROOT, $did);
  my $F;
  open($F, '<:utf8', $f.$l) or open($F, '<:utf8', $f) or return $self->resNotFound;
  my @c = <$F>;
  close $F;

  (my $title = shift @c) =~ s/^:TITLE://;
  chomp $title;

  my($sec, $subsec) = (0,0);
  for (@c) {
    s{^:SUB:(.+)\r?\n$}{
      $sec++;
      $subsec = 0;
      qq|<h3><a href="#$sec" name="$sec">$sec. $1</a></h3>\n|
    }e;
    s{^:SUBSUB:(.+)\r?\n$}{
      $subsec++;
      qq|<h4><a href="#$sec.$subsec" name="$sec.$subsec">$sec.$subsec. $1</a></h4>\n|
    }e;
    s{^:INC:(.+)\r?\n$}{
      $f = sprintf('%s/data/docs/%s', $VNDB::ROOT, $1);
      open($F, '<:utf8', $f.$l) or open($F, '<:utf8', $f) or die $!;
      my $ii = join('', <$F>);
      close $F;
      $ii;
    }e;
    s{^:TOP5CONTRIB:$}{
      my $l = $self->dbUserGet(results => 6, sort => 'changes', reverse => 1);
      '<dl>'.join('', map $_->{id} == 1 ? () :
        sprintf('<dt><a href="/u%d">%s</a></dt><dd>%d</dd>', $_->{id}, $_->{username}, $_->{c_changes}),
      @$l).'</dl>';
    }e;
    s{^:SKINCONTRIB:$}{
      my %users;
      push @{$users{ $self->{skins}{$_}[1] }}, [ $_, $self->{skins}{$_}[0] ]
        for sort { $self->{skins}{$a}[0] cmp $self->{skins}{$b}[0] } keys %{$self->{skins}};
      my $u = $self->dbUserGet(uid => [ keys %users ]);
      '<dl>'.join('', map sprintf('<dt><a href="/u%d">%s</a></dt><dd>%s</dd>',
        $_->{id}, $_->{username}, join(', ', map sprintf('<a href="?skin=%s">%s</a>', $_->[0], $_->[1]), @{$users{$_->{id}}})
      ), @$u).'</dl>';
    }e;
  }

  $self->htmlHeader(title => $title);
  div class => 'mainbox';
   h1 $title;
   div class => 'docs';
    lit join '', @c;
   end;
  end;
  $self->htmlFooter;
}


sub setlang {
  my $self = shift;

  my $lang = $self->formValidate({get => 'lang', required => 1, enum => [ VNDB::L10N::languages ]});
  return $self->resNotFound if $lang->{_err};
  $lang = $lang->{lang};

  my $browser = VNDB::L10N->get_handle()->language_tag();

  my $b = $self->reqBaseURI();
  (my $ref = $self->reqHeader('Referer')||'/') =~ s/^\Q$b//;
  $self->resRedirect($ref, 'post');
  if($lang ne $self->{l10n}->language_tag()) {
    $self->authInfo->{id}
    ? $self->authPref(l10n => $lang eq $browser ? undef : $lang)
    : $self->resCookie(l10n => $lang eq $browser ? undef : $lang, expires => time()+31536000);
  }
}


sub nospam {
  my $self = shift;
  $self->htmlHeader(title => mt '_nospam_title', noindex => 1);

  div class => 'mainbox';
   h1 mt '_nospam_title';
   div class => 'warning';
    h2 mt '_nospam_subtitle';
    p mt '_nospam_msg';
   end;
  end;

  $self->htmlFooter;
}


sub prefs {
  my $self = shift;
  return if !$self->authCheckCode;
  return $self->resNotFound if !$self->authInfo->{id};
  my $f = $self->formValidate(
    { get => 'key',   enum => [qw|filter_vn filter_release|] },
    { get => 'value', required => 0, maxlength => 2000 },
  );
  return $self->resNotFound if $f->{_err};
  $self->authPref($f->{key}, $f->{value});

  # doesn't really matter what we return, as long as it's XML
  $self->resHeader('Content-type' => 'text/xml');
  xml;
  tag 'done', '';
}


sub opensearch {
  my $self = shift;
  my $h = $self->reqBaseURI();
  $self->resHeader('Content-Type' => 'application/opensearchdescription+xml');
  xml;
  tag 'OpenSearchDescription',
    xmlns => 'http://a9.com/-/spec/opensearch/1.1/', 'xmlns:moz' => 'http://www.mozilla.org/2006/browser/search/';
   tag 'ShortName', 'VNDB';
   tag 'LongName', 'VNDB.org visual novel search';
   tag 'Description', 'Search visual vovels on VNDB.org';
   tag 'Image', width => 16, height => 16, type => 'image/x-icon', "$h/favicon.ico"
     if -s "$VNDB::ROOT/www/favicon.ico";
   tag 'Url', type => 'text/html', method => 'get', template => "$h/v/all?q={searchTerms}", undef;
   tag 'Url', type => 'application/opensearchdescription+xml', rel => 'self', template => "$h/opensearch.xml", undef;
   tag 'Query', role => 'example', searchTerms => 'Tsukihime', undef;
   tag 'moz:SearchForm', "$h/v/all";
  end 'OpenSearchDescription';
}


1;

