
use strict;
use warnings;

{
  package VNDB::L10N;
  use base 'Locale::Maketext';

  sub fallback_languages { ('en') };

  # used for the language switch interface, language tags must
  # be the same as in the languages hash in global.pl
  sub languages { ('en', 'ru') }

  sub maketext {
    my $r = eval { shift->SUPER::maketext(@_) };
    return $r if defined $r;
    warn "maketext failed for '@_': $@\n";
    return $_[0]||''; # not quite sure we want this
  }

  # can be called as either a subroutine or a method
  sub loadfile {
    my %lang = (
      en => \%VNDB::L10N::en::Lexicon,
      ru => \%VNDB::L10N::ru::Lexicon,
    );

    open my $F, '<:utf8', $VNDB::ROOT.'/data/lang.txt' or die "Opening language file: $!\n";
    my($empty, $line, $key, $lang) = (0, 0);
    while(<$F>) {
      chomp;
      $line++;

      # ignore intro
      if(!defined $key) {
        $key = 0 if /^\/intro$/;
        next;
      }
      # ignore comments
      next if /^#/;
      # key
      if(/^:(.+)$/) {
        $key = $1;
        $lang = undef;
        $empty = 0;
        next;
      }
      # locale string
      if(/^([a-z_-]{2,7})[ *]: (.+)$/) {
        $lang = $1;
        die "Unknown language on #$line: $lang\n" if !$lang{$lang};
        die "Unknown key for locale on #$line\n" if !$key;
        $lang{$lang}{$key} = $2;
        $empty = 0;
        next;
      }
      # multi-line locale string
      if($lang && /^\s+([^\s].*)$/) {
        $lang{$lang}{$key} .= ''.("\n"x$empty)."\n$1";
        $empty = 0;
        next;
      }
      # empty string (count them in case they're part of a multi-line locale string)
      if(/^\s*$/) {
        $empty++;
        next;
      }
      # something we didn't expect
      die "Don't know what to do with line $line\n" unless /^([a-z_-]{2,7})[ *]:/;
    }
    close $F;

    # dev.
    use Data::Dumper 'Dumper';
    warn Dumper \%lang;
  }
}


{
  package VNDB::L10N::en;
  use base 'VNDB::L10N';
  use POSIX 'strftime';
  our %Lexicon;

  # Argument: unix timestamp
  # Returns: age
  sub age {
    my $a = time-$_[1];
    return sprintf '%d %s ago',
      $a > 60*60*24*365*2       ? ( $a/60/60/24/365,      'years'  ) :
      $a > 60*60*24*(365/12)*2  ? ( $a/60/60/24/(365/12), 'months' ) :
      $a > 60*60*24*7*2         ? ( $a/60/60/24/7,        'weeks'  ) :
      $a > 60*60*24*2           ? ( $a/60/60/24,          'days'   ) :
      $a > 60*60*2              ? ( $a/60/60,             'hours'  ) :
      $a > 60*2                 ? ( $a/60,                'min'    ) :
                                  ( $a,                   'sec'    );
  }

  # argument: unix timestamp and optional format (compact/full)
  # return value: yyyy-mm-dd
  # (maybe an idea to use cgit-style ages for recent timestamps)
  sub date {
    my($s, $t, $f) = @_;
    return strftime '%Y-%m-%d', gmtime $t if !$f || $f eq 'compact';
    return strftime '%Y-%m-%d at %R', gmtime $t;
  }

  # argument: database release date format (yyyymmdd)
  #  y = 0000 -> unknown
  #  y = 9999 -> TBA
  #  m = 99   -> month+day unknown
  #  d = 99   -> day unknown
  # return value: (unknown|TBA|yyyy|yyyy-mm|yyyy-mm-dd)
  #  if date > now: <b class="future">str</b>
  sub datestr {
    my $self = shift;
    my $date = sprintf '%08d', shift||0;
    my $future = $date > strftime '%Y%m%d', gmtime;
    my($y, $m, $d) = ($1, $2, $3) if $date =~ /^([0-9]{4})([0-9]{2})([0-9]{2})$/;

    my $str = $y == 0 ? 'unknown' : $y == 9999 ? 'TBA' :
      $m == 99 ? sprintf('%04d', $y) :
      $d == 99 ? sprintf('%04d-%02d', $y, $m) :
                 sprintf('%04d-%02d-%02d', $y, $m, $d);

    return $str if !$future;
    return qq|<b class="future">$str</b>|;
  }

  # same as datestr(), but different output format:
  #  e.g.: 'Jan 2009', '2009', 'unknown', 'TBA'
  sub monthstr {
    my $self = shift;
    my $date = sprintf '%08d', shift||0;
    my($y, $m, $d) = ($1, $2, $3) if $date =~ /^([0-9]{4})([0-9]{2})([0-9]{2})/;
    return 'TBA' if $y == 9999;
    return 'unknown' if $y == 0;
    return $y if $m == 99;
    my $r = sprintf '%s %d', [qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec)]->[$m-1], $y;
    return $d == 99 ? "<i>$r</i>" : $r;
  }

  # Arguments: (uid, username), or a hashref containing that info
  sub userstr {
    my $self = shift;
    my($id,$n) = ref($_[0])eq'HASH'?($_[0]{uid}||$_[0]{requester}, $_[0]{username}):@_;
    return !$id ? '[deleted]' : '<a href="/u'.$id.'">'.$n.'</a>';
  }

  # Arguments: index, @list. returns $list[index]
  sub index {
    shift;
    return $_[shift];
  }
}



{
  package VNDB::L10N::ru;
  use base 'VNDB::L10N::en';
  our %Lexicon;

  sub quant {
    my($self, $num, $single, $couple, $lots) = @_;
    return $single if ($num % 10) == 1 && ($num % 100) != 11;
    return $couple if ($num % 10) >= 2 && ($num % 10) <= 4 && !(($num % 100) >= 12 && ($num % 100) <= 14);
    return $lots;
  }

  sub age {
    my $self = shift;
    my $a = time-shift;
    use utf8;
    my @l = (
      $a > 60*60*24*365*2       ? ( $a/60/60/24/365,      'год',     'года',    'лет'     ) :
      $a > 60*60*24*(365/12)*2  ? ( $a/60/60/24/(365/12), 'месяц',   'месяца',  'месяцев' ) :
      $a > 60*60*24*7*2         ? ( $a/60/60/24/7,        'неделя',  'недели',  'недель'  ) :
      $a > 60*60*24*2           ? ( $a/60/60/24,          'день',    'дня',     'дней'    ) :
      $a > 60*60*2              ? ( $a/60/60,             'час',     'часа',    'часов'   ) :
      $a > 60*2                 ? ( $a/60,                'минута',  'минуты',  'минут'   ) :
                                  ( $a,                   'секунда', 'секунды', 'секунд'  )
    );
    return sprintf '%d %s назад', $l[0], $self->quant(@l);
  }

}


1;

