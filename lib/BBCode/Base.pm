# Discussion board 'bb-tags' parser

package BBCode;

use strict;
use warnings;


# this function ought to be used in derived classes constructors.
sub _define {
  my %o = @_;
  $o{verbatim} = 1 if $o{revert}||$o{discard};
  my %defs = (
    %o,
    # regexp matching links that would be looked up in the database
    dbidre => qr/^([vcpgis])([1-9]\d*)\b/a, # should return (type, id) pair

    # tags definition, see pod documentation for available options
    tags => {
      raw => { noembed => 1, open => '', close => '' },
      spoiler => {
        open  => !$o{charspoil} ?
          '<b class="spoiler">' :
          '<b class="grayedout charspoil charspoil_-1">&lt;hidden by spoiler settings&gt;</b><span class="charspoil charspoil_2 hidden">',
        close => !$o{charspoil} ? '</b>' : '</span>',
      },
      quote => {
        open  => !$o{oneline} ? '<div class="quote">' : '',
        close => !$o{oneline} ? '</div>' : ' ',
        $o{oneline} ? (replace => '...') : (),
        rmnewline => 1,
      },
      code => {
        open  => sub { $_[0]->{rmnewline} = 1; return !$_[0]->{oneline} ? '<pre>' : '' },
        close => !$o{oneline} ? '</pre>' : '',
        noembed => 1,
      },
      url => {
        open => sub {
          if($_[2] =~ m{^(?:(https?)://|/)[^\]>]+$}i) {
            return qq(<a href="$_[2]" rel="nofollow">) if $1;
            return qq(<a href="$_[2]">); # "nofollow" for fully qualified links only
          }
          return undef;
        },
        close => '</a>',
        hasvalue => 1,
      },
    },
    # plaintext urls
    url => $o{verbatim} ? sub { $_[1] } :
      sub { return sprintf('<a href="%s" rel="nofollow">link</a>', $_[1]), 4; },

    # links to database objects
    dblink => $o{verbatim} ? sub { $_[1] } :
      sub {
        (my $link = $_[1]) =~ s/^d(\d+)\.(\d+)\.(\d+)$/d$1#$2.$3/a;
        return sprintf('<a href="/%s">%s</a>', $link, $_[1]), length $_[1];
      },
  );
  if($o{discard}) {
    # discard all tags from parsed text
    while(my($tag, $value) = each %{$defs{tags}}) {
      $value->{open} = '';
      $value->{close} = '' if exists $value->{close};
      delete @{$value}{qw|rmnewline replace|};
    }
  } elsif($o{verbatim}) {
    # all tags (except those with 'reverted' flag') will be output verbatim
    while(my($tag, $value) = each %{$defs{tags}}) {
      next if $value->{reverted};
      $value->{open} = $value->{hasvalue} ? sub { "[$_[1]=$_[2]]" } : '['.$tag.']';
      $value->{close} = '[/'.$tag.']' if exists $value->{close};
      delete @{$value}{qw|rmnewline replace|};
    }
  }
  return \%defs;
}


package BBCode::Base;


sub new {
  my $class = shift;
  my $self = BBCode::_define(@_);
  return bless $self, $class;
}


sub _start { $_[0]->{result} = '' }

sub _finish { return $_[0]->{result} }

sub _escape { return ($_[1], length $_[1]) }

sub _append { $_[0]->{result} .= $_[1] }

sub _append_text { return shift->_append(@_) }

sub _append_escaped {
  my $self = shift;
  return $self->_append_text($self->{verbatim} ? $_[0] : $self->_escape($_[0]));
}


sub parse {
  my($self, $text) = @_;
  $self->_start($text);
  return '' if !length $text;

  # keeps track of the current replaced tag scope
  my $replacing = 0;

  # tags stack, empty string indicates the top
  $self->{open} = [''];
  my $close_tag = sub {
    my $tag = pop @{$self->{open}};
    my $t = $self->{tags}{$tag};
    if(exists $t->{replace}) {
      --$replacing;
      $self->_append_text($t->{replace}) if !$replacing && length $t->{replace};
    }
    my $markup = $replacing ? '' :
                 ref $t->{close} eq 'CODE' ? $t->{close}->($self, $tag) :
                 $t->{close};
    $self->_append($markup) if $markup;
    return $markup;
  };

  while($text =~ m{
    (\bd[1-9]\d*\.[1-9]\d*\.[1-9]\d*\b)         | # 1: longid
    (\b[tdvprcs][1-9]\d*\.[1-9]\d*\b)           | # 2: exid
    (\b[tdvprcugis][1-9]\d*\b)                  | # 3: id
    (?:\[([^\s[\]]+)\])                         | # 4. tag
    (\b(?:https?|ftp)://[^><"\n\s\]\[]+[\w=/-])   # 5: url
  }xa) {
    my($match, $longid, $exid, $id, $tag, $url) = ($&, $1, $2, $3, $4, $5);
    $text = $';
    if(length $` && !$replacing) {
      last if !defined $self->_append_escaped($`);
    }

    my($tag_close, $tag_value);
    if($tag) {
      if(substr($tag, 0, 1) eq '/') {
        ($tag_close, $tag) = $tag =~ m{^(/)(\w+)$}a;
      } else {
        ($tag, $tag_value) = $tag =~ m{^(\w+)(?:=(.+))?$}a;
        # if value is specified, tag should have 'hasvalue' option enabled, and vice versa
        undef $tag if $tag && ($self->{tags}{$tag}{hasvalue} xor defined $tag_value);
      }
      $tag = lc $tag if $tag;
    }

    my $open_tag = $self->{tags}{$self->{open}[-1]};
    # if current opened tag allows embedded tags
    if(!$open_tag || !$open_tag->{noembed}) {
      # handle tags
      if($tag) {
        if(exists $self->{tags}{$tag}) {
          my $markup;
          my $t = $self->{tags}{$tag};
          $self->{rmnewline} = 1 if $t->{rmnewline};
          if(!$tag_close) {
            $markup = $replacing ? '' :
                      ref $t->{open} eq 'CODE' ? $t->{open}->($self, $tag, $tag_value) :
                      $t->{open}//'';
            if(defined $markup && exists $t->{close}) {
              push @{$self->{open}}, $tag;
              ++$replacing if exists $t->{replace};
            }
            $self->_append($markup) if length $markup;
          } elsif(exists $t->{close} && $tag eq $self->{open}[-1]) {
            $markup = &$close_tag;
          }
          next if defined $markup;
        }
      } elsif(!$replacing && !grep(/^url$/, @{$self->{open}})) {
        # handle URLs
        my @a;
        if($url) {
          @a = $self->{url}->($self, $url) if $self->{url};
        } elsif($id || $exid || $longid) {
          @a = $self->{dblink}->($self, $match) if $self->{dblink};
        }
        if(@a) {
          last if !defined $self->_append_text(@a);
          next;
        }
      }
    }
    if($tag_close && $tag eq $self->{open}[-1]) {
      &$close_tag;
      next;
    }
    next if $replacing;

    # We'll only get here when the bbcode input isn't correct or something else
    # didn't work out. In that case, just output whatever we've matched.
    last if !defined $self->_append_escaped($match);
  }

  # the last unmatched part, just escape and output
  $self->_append_escaped($text) if length $text && !$replacing;

  # close open tags
  &$close_tag while $self->{open}[-1];

  return $self->_finish;
}


1;
__END__

=head1 NAME

BBCode - VNDB text markup parser

=head1 SYSNOPSYS

 # simple interface

 use VNDBUtil; # imports bb2html and bbConvert.

 $html = bb2html($text);

 # OO-interface

 use BBCode::Convert;

 $bbcode = BBCode::Convert->new(oneline => 1, maxlength => 150);
 $html = $bbcode->parse($text);

=head1 DESCRIPTION

This is an attempt to implement generic bb-markup parser for VNDB.

=head1 BBCode::_define(option => value, ...)

Returns hashref with default tags definitions, modified according to the supplied options. All boolean options and settings are zero (not set) by default.

=head2 Available options

=over

=item maxlength => INTEGER

Limit output length. [default 0 = do not limit]

=item charspoil => 0|1

Output spoilers as character spoiler blocks.

=item oneline => 0|1

Output contents as one line (prevent any line breaks).

=item verbatim => 0|1

Don't escape text and place all tags into output "as is".

=item discard => 0|1

Discard all tags (they are replaced with empty strings '').

=item revert => 0|1

Convert database links back to text form. Implies 'verbatim'.

=back

=head2 Tags definition

  NAME => {
    noembed => 0|1,   # cannot contain other tags
    hasvalue => 0|1,  # tag should be specified as [name=value]
    rmnewline => 0|1, # remove newline following the tag
    replace => STRING # if defined, replace the whole enclosed
                      # contents with the string specified
    open => STRING|CODEREF
    close => STRING|CODEREF
  }

Tag C<NAME> should match C</^\w+$/> pattern, that is, only alphanumeric
characters plus '_' are allowed in tag names.

C<open> and C<close> keys define tag's markup. For example, [b] tag
representing an emphasized text region could be defined as:

  b => { open => '<b>', close => '</b>' }

Parameters for C<open> CODEREF: ($self, $tag, $value)

Parameters for C<close> CODEREF: ($self, $tag)

If C<close> is not defined tag is rendered without content, for example:

  br => { open => '<br />' }

=head2 Links parsers

  url => CODEREF,
  dblink => CODEREF,

Parameters passed to CODEREF: ($self, $link)

CODE should return a list (I<markup>, I<length>) that is passed as parameters to C<_append_text> method.
If empty list is returned, C<_append_text> is not called.

=head1 BBCode::Base

Base bb-code parser converts tags, but does not perform escape of input.

=head1 PUBLIC METHODS

=head2 new(option => value, ...)

Options are passed to the C<_define> method (see above).

=head2 parse($text)

Looks for bb-codes within C<$text> and returns parse results.  Note that result
is not necessarily a string, derived classes could implement different semantics
overriding C<_finish> method.

=head1 PRIVATE METHODS

These methods can be overridden by derived classes to extend parser
functionality.

=head2 _start($input)

Reset parser to default state and prepare to parse $input.  Derived class
should call this method explicitly if it's overridden, otherwise, C<_append>
and C<_finish> should be overridden as well.

=head2 _finish

Should return parser output.

=head2 _escape($text)

Returns escaped text and its length before escaping applied.

=head2 _append($text)

Append text or markup to resulting string.  Class could perform other actions
instead of appending text by overriding this method.  C<_append> should return
some I<defined> value as C<_append_text> relies on it (see below).

Used by C<parse> for markup.

=head2 _append_text($text, $length)

By overring this method derived classes could perform additional checks for
appended text length. if C<_append_text> returns C<undef>, parsing is stopped at
this point and result returned to the caller.

Used by C<parse> for text with embedded markup.

=head2 _append_escaped($text)

Escape text and append it to results. Just a shortcut for C<_append_text($self-E<gt>_escape($text))>.

Used by C<parse> for plain text.

=head1 BBCode::Convert

This class implements output length check and proper input escaping.

=head1 BBCode::VNDBLinks

Performs database lookups to substitute VNDBID links with [dblink] tags.

=cut

