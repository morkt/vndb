
use strict;
use warnings;

{
  package VNDB::L10N;
  use base 'Locale::Maketext';
  use LangFile;

  sub fallback_languages { ('en') };

  # used for the language switch interface, language tags must
  # be the same as in the languages hash in global.pl
  sub languages { qw{ en } }

  sub maketext {
    my $r = eval { shift->SUPER::maketext(@_) };
    return $r if defined $r;
    warn "maketext failed for '@_': $@\n";
    return $_[0]||''; # not quite sure we want this
  }

  # can be called as either a subroutine or a method
  sub loadfile {
    my %lang = do {
      no strict 'refs';
      map {
        (my $n = $_) =~ s/-/_/g;
        ($_, \%{"VNDB::L10N::${n}::Lexicon"})
      } languages
    };
    my $r = LangFile->new(read => "$VNDB::ROOT/data/lang.txt");
    my $key;
    while(my $l = $r->read) {
      my($t, @l) = @$l;
      $key = $l[0] if $t eq 'key';
      if($t eq 'tl') {
        my($lang, undef, $text) = @l;
        next if !$text;
        die "Unknown language \"$l->[1]\"\n" if !$lang{$lang};
        die "Unknown key for translation \"$lang: $text\"\n" if !$key;
        $lang{$lang}{$key} = $text;
      }
    }
    $r->close;
  }
}



{
  package VNDB::L10N::en;
  use base 'VNDB::L10N';
  use POSIX 'strftime';
  use TUWF::XML 'xml_escape';
  require VNDB::Func;
  our %Lexicon;

  sub quant {
    return $_[1]==1 ? $_[2] : $_[3];
  }

  sub age     { VNDB::Func::fmtage($_[1]) }
  sub date    { VNDB::Func::fmtdate($_[1], $_[2]) }
  sub datestr { VNDB::Func::fmtdatestr($_[1]) }
  sub userstr { VNDB::Func::fmtuser($_[1], $_[2]) }

  # Arguments: index, @list. returns $list[index]
  sub index {
    shift;
    return $_[shift||0];
  }

  # Shortcut for <a href="arg1">arg2</a>
  sub url {
    return sprintf '<a href="%s">%s</a>', xml_escape($_[1]), xml_escape($_[2]);
  }

  # <br />
  sub br { return '<br />' }
}

1;

