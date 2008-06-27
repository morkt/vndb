[[!

use Time::CTime ();
use Algorithm::Diff 'sdiff';
use POSIX ('ceil', 'floor');

my %p; # $X->{page}        global page data
my %d; # $X->{page}->{$p}  local page data

# redefine _hchar - usually a bad idea, but who cares
sub _hchar {local$_=shift||return'';s/&/&amp;/g;s/</&lt;/g;s/>/&gt;/g;s/"/&quot;/g;s/\r?\n/ <br \/>\n/g;return$_;}

sub formatdate {return _hchar(Time::CTime::strftime($_[0],gmtime($_[1]||0)))||'';}
sub txt        {local$_=shift||return'';s/&/&amp;/g;s/</&lt;/g;s/>/&gt;/g;return$_;}
sub art2str    {my$r='';$r.=($r?' & ':'').$_->{name}foreach (@{$_[0]->{artists}});return $_[1]?$r:_hchar($r);}
sub calctime   {my$r=shift;return'0:00:00'if!$r;my$x=sprintf'%d:%02d:%02d',int($r/3600),int(($r%3600)/60),($r%3600)%60;return $x;}
sub shorten    {local$_=shift||return'';return length>$_[0]?substr($_,0,$_[0]-3).'...':$_};

# Date string format: yyyy-mm-dd
#   y = 0    -> Unknown
#   y = 9999 -> TBA (To Be Announced)
#   m = 99   -> Month + day unknown, year known
#   d = 99   -> Day unknown, month + year known
sub datestr {
  my $d = sprintf '%08d', $_[0]||0;
  my $b = $d > Time::CTime::strftime("%Y%m%d", gmtime());
  my @d = map int, $1, $2, $3 if $d =~ /^([0-9]{4})([0-9]{2})([0-9]{2})$/;
  return 'unknown' if $d[0] == 0;
  my $r = sprintf $d[1] == 99 ? '%04d' : $d[2] == 99 ? '%04d-%02d' : '%04d-%02d-%02d', @d;
  $r = 'TBA' if $d[0] == 9999;
  return ($b?'<b class="future">':'').$r.($b?'</b>':'');
}
sub mediastr {
  return join(', ', map { 
    $_->{medium} =~ /^(cd|dvd|gdr|blr)$/
       ? sprintf('%d %s%s', $_->{qty}, $VNDB::MED->{$_->{medium}}, $_->{qty}>1?'s':'')
       : $VNDB::MED->{$_->{medium}}
  } @{$_[0]});
}
sub sortbut { # url, col
  my $r=' '; my $u = _hchar($_[0]);
  $u .= $u =~ /\?/ ? ';' : '?';
  for ('a', 'd') {
    my $chr = $_ eq 'd' ? "\x{25BE}" : "\x{25B4}";
    $r .= $d{order}[0] eq $_[1] && $d{order}[1] eq $_ ? $chr : 
      sprintf '<a href="%ss=%s;o=%s">%s</a>', $u, $_[1], $_, $chr;
  }
  return $r;
}
sub pagebut { # url
  my @br; my $ng = $_[0] =~ /\?/ ? ';' : '?';
  push @br, sprintf '<a href="%s">&lt;- previous</a>', $_[0].($d{page}-2 ? $ng.'p='.($d{page}-1) : '') if $d{page} > 1;
  push @br, sprintf '<a href="%s">next -&gt;</a>', $_[0].$ng.'p='.($d{page}+1) if $d{npage};
  return $#br >= 0 ? ('<p class="browse">( '.join(' | ', @br).' )</p>') : '';
}
sub wraplong { # text, margin
  local $_ = $_[0];
  my $m = $_[1]/2;
  s/([^\s\r\n]{$m})([^\s\r\n])/$1 $2/g;
  return $_;
}

 
sub wordsplit { # split a string into an array of words, but make sure to not split HTML tags
#  return [ split //, $_[0] ];
  my @a;
  my $in='';
  for (split /\s+/, $_[0]) {
    my $gt = () = />/g; 
    my $lt = () = /</g;
    if($in && $gt > $lt) {
      push @a, $in.$_;
      $in='';
    } elsif($lt > $gt || $in) {
      $in .= $_.' ';
    } else {
      push @a, $_;
    };
  }
  push @a, $in if $in;
  return \@a;
}

sub cdiff { # obj1, obj2, @items->[ short, name, serialise, diff, [parsed_x, parsed_y] ]
  my($x, $y, @items, @c) = @_;
  # serialise = 0 -> integer, 1 -> string, CODEref -> code

  my $type = defined $$y{minage} ? 'r' : defined $$y{length} ? 'v' : 'p';
  my $pre = '<div id="revbrowse">'.
    ($$y{next} ? qq|<a href="/$type$$y{id}?rev=$$y{next}" id="revnext">later revision -&gt;</a>| : '').
    ($x ? qq|<a href="/$type$$y{id}?rev=$$x{cid}" id="revprev">&lt;- earlier revision</a>| : '').
    qq|<a href="/$type$$y{id}" id="revmain">$type$$y{id}</a>&nbsp;</div>|;

  if(!$x) { # just show info about the revision if there is no previous edit
    return $pre.qq|<div id="tmc"><b>Revision $$y{cid}</b> (<a href="/$type$$y{id}/edit?rev=$$y{cid}">edit</a>)<br />By <a href="/u$$y{requester}">$$y{username}</a> on |.
      formatdate('%Y-%m-%d at %R', $$y{added}).'<br /><b>Edit summary:</b><br /><br />'.
      summary($$y{comments}, 0, '[no summary]').'</div>';
  }
  for (@items) {
    $_->[4] = !$_->[2] ? $x->{$_->[0]}||'0' : !ref($_->[2]) ? _hchar(wraplong($x->{$_->[0]}||'[empty]',60)) : &{$_->[2]}($x->{$_->[0]})||'[empty]';
    $_->[5] = !$_->[2] ? $y->{$_->[0]}||'0' : !ref($_->[2]) ? _hchar(wraplong($y->{$_->[0]}||'[empty]',60)) : &{$_->[2]}($y->{$_->[0]})||'[empty]';
    push(@c, $_) if $_->[4] ne $_->[5];
    if($_->[3] && $_->[4] ne $_->[5]) {
      my($rx,$ry,$ch) = ('','','u');
      for (sdiff(wordsplit($_->[4]), wordsplit($_->[5]))) {
        if($ch ne $_->[0]) {
          if($ch ne 'u') {
            $rx .= '</b>';
            $ry .= '</b>';
          }
          $rx .= '<b class="diff_del">' if $_->[0] eq '-' || $_->[0] eq 'c';
          $ry .= '<b class="diff_add">' if $_->[0] eq '+' || $_->[0] eq 'c';
        }
        $ch = $_->[0];
        $rx .= $_->[1].' ' if $ch ne '+';
        $ry .= $_->[2].' ' if $ch ne '-';
      }
      $_->[4] = $rx;
      $_->[5] = $ry;
    }
  }
  return $pre.'<table id="tmc"><thead><tr><td class="tc1">&nbsp;</td>'.
    qq|<td class="tc2"><b>Revision $$x{cid}</b> (<a href="/$type$$y{id}/edit?rev=$$x{cid}">edit</a>)<br />By <a href="/u$$x{requester}">$$x{username}</a> on |.formatdate('%Y-%m-%d at %R', $$x{added}).'</td>'.
    qq|<td class="tc3"><b>Revision $$y{cid}</b> (<a href="/$type$$y{id}/edit?rev=$$y{cid}">edit</a>)<br />By <a href="/u$$y{requester}">$$y{username}</a> on |.formatdate('%Y-%m-%d at %R', $$y{added}).'</td>'.
    '</tr><tr></tr><tr><td>&nbsp;</td><td colspan="2"><b>Edit summary of revision '.$$y{cid}.'</b><br /><br />'.summary($$y{comments}, 0, '[no summary]').'<br /><br /></td></tr></thead>'.
    join('',map{
      '<tr><td class="tc1">'.$_->[1].'</td><td class="tc2">'.$_->[4].'</td><td class="tc3">'.$_->[5].'</td></tr>'
    } @c).'</table>';
}


sub summary { # cmd, len, def
  return $_[2]||'' if !$_[0];
  my $res = '';
  my $len = 0;
  my $as = 0;
  (my $txt = $_[0]) =~ s/\r?\n/\n /g;
  for (split / /, $txt) {
    next if !defined $_ || $_ eq '';
    my $l = length;
    s/\&/&amp;/g;
    s/>/&gt;/g;
    s/</&lt;/g;
    while(s/\[url=((https?:\/\/|\/)[^\]>]+)\]/<a href="$1" rel="nofollow">/i) {
      $l -= length($1)+6;
      $as++;
    }
    if(!$as && s/(http|https):\/\/(.+[0-9a-zA-Z=\/])/<a href="$1:\/\/$2" rel="nofollow">link<\/a>/) {
      $l = 4;
    } elsif(!$as) {
      s/^(.*[^\w]|)([duvpr][0-9]+)([^\w].*|)$/$1<a href="\/$2">$2<\/a>$3/;
    }
    while(s/\[\/url\]/<\/a>/i) {
      $l -= 6;
      $as--;
    }
    $len += $l + 1;
    last if $_[1] && $len > $_[1];
    $res .= "$_ ";
  }
  $res =~ y/\n/ / if $_[1];
  $res =~ s/\n/<br \/>/g if !$_[1];
  $res =~ s/ +$//;
  $res .= '</a>' x $as if $as;
  $res .= '...' if $_[1] && $len > $_[1];
  return $res;
}


sub ttabs { # [vrp], obj, sel
  my($t, $o, $s) = @_;
  $s||='';
  my @act = (
    !$s?'%s':'<a href="/%s">%1$s</a>',
    $$o{locked} ?
      '<b>locked for editing</b>' : (),
    $p{Authlock} ?
      sprintf('<a href="/%%s/lock">%s</a>', $$o{locked} ? 'unlock' : 'lock') : (),
    $p{Authdel} ? (
      sprintf('<a href="/%%s/hide"%s>%s</a>', $t eq 'v' ? ' id="vhide"' : '', $$o{hidden} ? 'unhide' : 'hide')
    ) : (),
    (!$$o{locked} && !$$o{hidden}) || ($p{Authedit} && $p{Authlock}) ?
      ($s eq 'edit' ? 'edit' : '<a href="'.($p{Authedit}?'/%s/edit':'/u/register?n=1').'" '.($t eq 'v' || $t eq 'r' ? 'class="dropdown" rel="nofollow editDD"':'').'>edit</a>') : (),

    $p{Authhist} ?
      ($s eq 'hist' ? 'history' : '<a href="/%s/hist">history</a>') : (),
  );
  return '<p class="mod">&lt; '.join(' - ', map { sprintf $_, $t.$$o{id} } @act).' &gt;</p>'.(
    !$p{Authedit} ? qq|
<div id="editDD" class="dropdown">
 <ul>
  <li><b>Not logged in</b></li>
  <li><a href="/u/login">Login</a></li>
  <li><a href="/u/register">Register</a></li>
 </ul>
</div>
    | : $t eq 'v' ? qq|
<div id="editDD" class="dropdown">
 <ul>
  <li><a href="/v$$o{id}/edit" rel="nofollow">Edit all</a></li>
  <li><a href="/v$$o{id}/edit?fh=info" rel="nofollow">General info</a></li>
  <li><a href="/v$$o{id}/edit?fh=cat" rel="nofollow">Categories</a></li>
  <li><a href="/v$$o{id}/edit?fh=rel" rel="nofollow">Relations</a></li>
  <li><a href="/v$$o{id}/edit?fh=img" rel="nofollow">Upload image</a></li>
  <li><a href="/v$$o{id}/add" rel="nofollow">Add release</a></li>
 </ul>
</div>| : $t eq 'r' ? qq|
<div id="editDD" class="dropdown">
 <ul>
  <li><a href="/r$$o{id}/edit" rel="nofollow">Edit all</a></li>
  <li><a href="/r$$o{id}/edit?fh=info" rel="nofollow">General info</a></li>
  <li><a href="/r$$o{id}/edit?fh=pnm" rel="nofollow">Platforms &amp; media</a></li>
  <li><a href="/r$$o{id}/edit?fh=prod" rel="nofollow">Producers</a></li>
  <li><a href="/r$$o{id}/edit?fh=rel" rel="nofollow">Relations</a></li>
 </ul>
</div>| : ''
  );
}



my %pagetitles = (
  faq          => 'Frequently Asked Questions',
  userlogin    => 'Login',
  userreg      => 'Register a new account',
  userpass     => 'Forgot your password?',
  home         => 'Visual Novel Database',
  pbrowse      => 'Browse producers',
  userlist     => 'Browse users',
  myvotes      => sub {
    return $p{myvotes}{user}{username} eq $p{AuthUsername} ? 'My votes' : ('Votes by '.$p{myvotes}{user}{username}); },
  userpage     => sub {
    return 'User: '.$p{userpage}{user}{username} },
  vnlist       => sub {
    return $p{vnlist}{user}{username} eq $p{AuthUsername} ? 'My visual novel list' : ($p{vnlist}{user}{username}.'\'s visual novel list'); },
  useredit     => sub {
    return !$p{useredit}{adm} ? 'My account' : 'Edit '.$p{useredit}{form}{username}.'\'s account'; },
  ppage        => sub {
    return $p{ppage}{prod}{name} },
  pedit        => sub {
    return $p{pedit}{id} ? sprintf('Edit %s', $p{pedit}{form}{name}) : 'Add a new producer';  },
  vnedit       => sub {
    return $p{vnedit}{id} ? sprintf('Edit %s', $p{vnedit}{form}{title}) : 'Add a new visual novel';  },
  redit      => sub {
    return $p{redit}{id} ? sprintf('Edit %s', $p{redit}{rel}{title}) : sprintf('Add release to %s', $p{redit}{vn}{title}); },
  vnpage       => sub { return $p{vnpage}{vn}{title};  },
  vnrg         => sub { return 'Relations for '.$p{vnrg}{vn}{title} },
  vnstats      => sub { return 'User statistics for '.$p{vnstats}{vn}{title} },
  vnbrowse     => sub {
    return $p{vnbrowse}{chr} eq 'search' ? 'Visual novel search' :
              $p{vnbrowse}{chr} eq 'mod' ? 'Visual Novels awaiting moderation' :
              $p{vnbrowse}{chr} eq 'all' ? 'Browse all visual novels' :
                $p{vnbrowse}{chr} eq '0' ? 'Browse by char: Other' :
                                           sprintf 'Browse by char: %s', uc $p{vnbrowse}{chr};  },
  rpage       => sub {
    return $p{rpage}{rel}{romaji} || $p{rpage}{rel}{title} },
  hist        => sub {
    return !$p{hist}{id} || !$p{hist}{type} ? 'Recent changes' :
     $p{hist}{type} eq 'u' ? 'Recent changes by '.$p{hist}{title} : 'Edit history of '.$p{hist}{title}; },
  docs        => sub { $p{docs}{title} },
  error       => sub {
    $p{error}{err} eq 'notfound' ? '404 Page Not Found' : 'Error Parsing Form' },
);
sub gettitle{$p{$_}&&($p{PageTitle}=ref($pagetitles{$_}) eq 'CODE' ? &{$pagetitles{$_}} : $pagetitles{$_}) for (keys%pagetitles);}


#
#  F O R M   E R R O R   H A N D L I N G
#
my %formerr_names = (
 # this list is rather incomplete...
  mail        => 'Email',
  username    => 'Username',
  userpass    => 'Password',
  pass1       => 'Password',
  pass2       => 'Password (second)',
  title       => 'Title',
  desc        => 'Description',
  rel         => 'Relation',
  romaji      => 'Romanized title',
  lang        => 'Language',
  web         => 'Website',
  released    => 'Release date',
  platforms   => 'Platforms',
  media       => 'Media',
  name        => 'Name',
  vn          => 'Visual novel relations',
  l_vnn       => 'Visual-novels.net link',
);
my @formerr_msgs = (
  sub { return sprintf 'Field "%s" is required.', @_ },
  sub { return sprintf '%s should have at least %d characters.', @_ },
  sub { return sprintf '%s is too large! Only %d characters allowed.', @_ },
  sub { return
    $_[1] eq 'mail' ? 'Invalid email address' :
    $_[1] eq 'url'  ? 'Invalid URL' :
    $_[1] eq 'pname' ? sprintf('%s can only contain alfanumeric characters!', $_[0]) :
    $_[1] eq 'asciiprint' ? sprintf('Only ASCII characters are allowed at %s', $_[0]) :
    $_[1] eq 'int'  ? sprintf('%s should be a number!', $_[0]) :
    $_[1] eq 'gtin' ? 'Not a valid JAN, UPC or EAN code!' : '';
  },
  sub { return sprintf '%s: invalid item selected', @_ },
  sub { return 'Invalid unicode, are you sure your browser works fine?' },
);
my %formerr_exeptions = (
  loginerr   => 'Invalid username or password',
  badpass    => 'Passwords do not match',
  usrexists  => 'Username already exists, please choose an other one',
  mailexists => 'There already is a user with that email address, please request a new password if you forgot it',
  nomail     => 'No user found with that email address',
  nojpeg     => 'Image is not in JPEG or PNG format!',
  toolarge   => 'Image is too large (in filesize), try to compress it a little',
);
sub formerr {
  my @err = ref $_[0] eq 'ARRAY' ? @{$_[0]} : ();
  return '' if $#err < 0;
  my @msgs;
  my $ret = '<span class="warning">
   Error:<ul>';
  $ret .= sprintf " <li>%s</li>\n", 
     /^([a-z0-9_]+)-([0-9]+)(?:-(.+))?$/ ? &{$formerr_msgs[$2-1]}($formerr_names{$1}||$1, $3||'') : $formerr_exeptions{$_}
    foreach (@err);
  $ret .= "</ul>\n</span>\n";
}

#
#  F O R M   C R E A T I N G
#

# args = [ 
#   {
#     type => $type,
#     %options
#   }, ...
# ], $formobj
#
#  $type      $formobj   %options ( required, [ optional ] )
#   error       X         ( )
#   startform             ( action, [ upload ] )
#   endform               ( )
#   input       X         ( short, name, [ class, default ] )
#   pass                  ( short, name )
#   upload                ( short, name, [ class ] )
#   hidden      X         ( short, [ value ] )
#   textarea    X         ( short, name, [ rows, cols, class ] )
#   select      X         ( short, name, options, [ class ] )        # options = arrayref of hashes with keys: short, name
#   as          X         ( name )
#   trans       X         ( )
#   submit                ( [ text, short ] )
#   sub                   ( title ) 
#   check       X         ( short, name, [ value ] )
#   static                ( text, raw [ name, class ] )
#   date        X         ( short, name )
#
sub cform {
  my $obj = shift;
  my $frm = shift;
  my $ret = '';
  my $csub = '';
  for (@$obj) {
    $_->{class} ||= '';
    $_->{class} .= ' sf_'.$csub if $csub && $_->{class} !~ /nohid/;
    $_->{class} .= ' formhid' if $csub && $frm->{_hid} && !$frm->{_hid}{$csub} && $_->{class} !~ /nohid/;
    $_->{name} = '<i>*</i> '.$_->{name} if $_->{r};

   # error
    if($_->{type} eq 'error') {
      $ret .= formerr($frm->{_err});
   # startform
    } elsif($_->{type} eq 'startform') {
      $ret .= sprintf qq|<form action="/nospam?%s" method="post" accept-charset="utf-8"%s>\n|,
        $_->{action}, $_->{upload} ? ' enctype="multipart/form-data"' : '';
      $ret .= sprintf qq| <input type="hidden" class="hidden" name="fh" id="_hid" value="%s" />\n|,
        $frm->{_hid} ? _hchar(join(',', keys %{$frm->{_hid}})) : '' if $_->{fh};
      $ret .= qq|<p class="formnotice">Items denoted by a red asterisk (<i>*</i>) are required.</p>\n|
        if scalar grep { $_->{r} } @$obj;
      $ret .= "<ul>\n";
   # endform
    } elsif($_->{type} eq 'endform') {
      $ret .= qq|</ul></form>\n|;
   # input
    } elsif($_->{type} eq 'input') {
      $ret .= sprintf qq|<li%s>\n <label for="%s">%s</label>\n %s<input type="text" class="text" name="%2\$s" id="%2\$s" value="%s" />%s\n</li>\n|,
        $_->{class} ? ' class="'.$_->{class}.'"' : '', $_->{short}, $_->{name}, $_->{pre} ? '<i>'.$_->{pre}.'</i>' : '',
        _hchar($frm->{$_->{short}}?$frm->{$_->{short}}:$_->{default}), $_->{post} ? '<i>'.$_->{post}.'</i>' : '';
   # pass
    } elsif($_->{type} eq 'pass') {
      $ret .= sprintf qq|<li%s>\n <label for="%s">%s</label>\n <input type="password" class="text" name="%2\$s" id="%2\$s" />\n</li>\n|,
        $_->{class} ? ' class="'.$_->{class}.'"' : '', $_->{short}, $_->{name};
   # upload
    } elsif($_->{type} eq 'upload') {
      $ret .= sprintf qq|<li%s>\n <label for="%s">%s</label>\n <input type="file" class="text" name="%2\$s" id="%2\$s" />\n</li>\n|,
        $_->{class} ? ' class="'.$_->{class}.'"' : '', $_->{short}, $_->{name};
   # hidden
    } elsif($_->{type} eq 'hidden') {
      $ret .= sprintf qq| <input type="hidden" class="hidden" name="%s" id="%1\$s" value="%s" />\n|,
        $_->{short}, _hchar($_->{value} || $frm->{$_->{short}});
   # textarea
    } elsif($_->{type} eq 'textarea') {
      $ret .= sprintf qq|<li%s>\n <label for="%s">%s</label>\n <textarea name="%2\$s" id="%2\$s" rows="%s" cols="%s">%s</textarea>\n</li>\n|,
        $_->{class} ? ' class="'.$_->{class}.'"' : '', $_->{short}, $_->{name}, $_->{rows}||15, $_->{cols}||70, txt($frm->{$_->{short}});
   # select
    } elsif($_->{type} eq 'select') {
      $ret .= sprintf qq|<li%s>\n <label for="%s">%s</label>\n <select name="%2\$s" id="%2\$s">\n%s</select>\n</li>\n|,
        $_->{class} ? ' class="'.$_->{class}.'"' : '', $_->{short}, $_->{name}, eval {
          my $r='';
          for my $s (@{$_->{options}}) {
            $r .= sprintf qq|  <option value="%s"%s>%s</option>\n|,
              $s->{short}, defined $frm->{$_->{short}} && $frm->{$_->{short}} eq $s->{short} ? ' selected="selected"' : '', $s->{name};
          } 
          return $r;
        };
   # jssel
    } elsif($_->{type} eq 'jssel') {
      (my $oname = $_->{name}) =~ s/^<i>\*<\/i>//;
      $ret .= sprintf
         qq|<li%s>\n|
        .qq| <label for="%s_select">%s</label>\n|
        .qq| <select name="%s_select" id="%s_select" multiple="multiple" size="5" class="multiple">\n|
        .qq|  <option value="0_new" style="font-style: italic">Add %s...</option>\n|
        .qq| </select>\n|
        .qq| <div id="%s_conts">\n|
        .qq|  Loading...\n|
        .qq| </div>\n|
        .qq| <input type="hidden" name="%s" id="%s" class="hidden" value="%s" />\n|
        .qq|</li>\n|,
        $_->{class} ? ' class="'.$_->{class}.'"' : '',
        $_->{sh}, $_->{name}, $_->{sh}, $_->{sh}, $oname, $_->{sh}, $_->{short}, $_->{short}, _hchar($frm->{$_->{short}});
   # submit
    } elsif($_->{type} eq 'submit') {
      $ret .= sprintf qq|<li class="nolabel">\n <br /><input type="submit" class="submit" value="%s"%s />\n </li>\n|,
        $_->{text} || 'Verstuur', $_->{short} ? sprintf(' name="%s" id="%1$s"', $_->{short}) : '';
   # sub
    } elsif($_->{type} eq 'sub') {
      $ret .= sprintf qq|<li class="subform">\n <a href="#" class="s_%s">%s %s</a>\n</li>\n|,
        $_->{short}, $frm->{_hid} && !$frm->{_hid}{$_->{short}} ? '&#9656;' : '&#9662;', $_->{title};
      $csub = $_->{short};
   # check
    } elsif($_->{type} eq 'check') {
      $ret .= sprintf qq|<li class="nolabel%s">\n <input type="checkbox" name="%s" id="%2\$s" value="%s"%s />\n <label for="%2\$s" class="checkbox">%s</label>\n</li>\n|,
        $_->{class} ? ' '.$_->{class} : '',
        $_->{short}, $_->{value} || 'true', $frm->{$_->{short}} ? ' checked="checked"' : '', $_->{name};
   # static
    } elsif($_->{type} eq 'static') {
      $ret .= $_->{name}
        ? sprintf qq|<li%s>\n <label>%s</label>\n <p>%s</p>\n</li>|, $_->{class} ? ' class="'.$_->{class}.'"' : '', $_->{name}, $_->{text}
      : $_->{raw}
        ? sprintf qq|<li%s>\n %s\n</li>|, $_->{class} ? ' class="'.$_->{class}.'"' : '', $_->{text}
        : sprintf qq|<li class="nolabel%s">\n %s\n</li>|, $_->{class} ? ' '.$_->{class} : '', $_->{text};
   # date
    } elsif($_->{type} eq 'date') {
      $ret .= sprintf qq|<li class="date%s">\n <label for="%s">%s</label>\n|,
        $_->{class} ? ' '.$_->{class} : '', $_->{short}, $_->{name};
      $ret .= sprintf qq| <select name="%s" id="%s">\n%s</select>\n|,
        $_->{short}, $_->{short}, eval {
          my $r='';
          for my $s (0, 1990..((localtime())[5]+1905), 9999) {
            $r .= sprintf qq|  <option value="%s"%s>%s</option>\n|,
              $s, $frm->{$_->{short}} && ($frm->{$_->{short}}[0]||0) == $s ? ' selected="selected"' : '',
              !$s ? '-year-' : $s < 9999 ? $s : 'TBA';
          }
          return $r;
        };
      $ret .= sprintf qq| <select name="%s" id="%s_m">\n%s</select>\n|,
        $_->{short}, $_->{short}, eval {
          my $r='';
          for my $s (0..12) {
            $r .= sprintf qq|  <option value="%s"%s>%s</option>\n|,
              $s, $frm->{$_->{short}} && ($frm->{$_->{short}}[1]||0) == $s ? ' selected="selected"' : '',
              $s ? $Time::CTime::MonthOfYear[$s-1] : '-month-';
          }
          return $r;
        };
      $ret .= sprintf qq| <select name="%s" id="%s_d">\n%s</select>\n</li>\n|,
        $_->{short}, $_->{short}, eval {
          my $r='';
          for my $s (0..31) {
            $r .= sprintf qq|  <option value="%s"%s>%s</option>\n|,
              $s, $frm->{$_->{short}} && ($frm->{$_->{short}}[2]||0) == $s ? ' selected="selected"' : '',
              $s ? $s : '-day-';
          }
          return $r;
        };
    }
  }
  return $ret;
}

]]
