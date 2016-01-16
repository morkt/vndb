#!/usr/bin/perl


package VNDB;

use strict;
use warnings;


use Cwd 'abs_path';
our $ROOT;
BEGIN { ($ROOT = abs_path $0) =~ s{/util/vndb\.pl$}{}; }


use lib $ROOT.'/lib';


use TUWF ':html', 'kv_validate';
use VNDB::L10N;
use VNDB::Func 'json_decode';
use VNDBUtil 'gtintype';
use SkinFile;


our(%O, %S);


# load the skins
# NOTE: $S{skins} can be modified in data/config.pl, allowing deletion of skins or forcing only one skin
my $skin = SkinFile->new("$ROOT/static/s");
$S{skins} = { map +($_ => [ $skin->get($_, 'name'), $skin->get($_, 'userid') ]), $skin->list };


# load lang.dat
VNDB::L10N::loadfile();


# load settings from global.pl
require $ROOT.'/data/global.pl';


# automatically regenerate the skins and script.js and whatever else should be done
system "make -sC $ROOT" if $S{regen_static};


$TUWF::OBJ->{$_} = $S{$_} for (keys %S);
TUWF::set(
  %O,
  pre_request_handler => \&reqinit,
  error_404_handler => \&handle404,
  log_format => \&logformat,
  validate_templates => {
    id    => { template => 'uint', max => 1<<40 },
    page  => { template => 'uint', max => 1000 },
    uname => { regex => qr/^[a-z0-9-]*$/, minlength => 2, maxlength => 15 },
    gtin  => { func => \&gtintype },
    editsum => { maxlength => 5000, minlength => 2 },
    json  => { func => \&json_validate, inherit => ['json_fields','json_maxitems','json_unique','json_sort'], default => [] },
  },
);
TUWF::load_recursive('VNDB::Util', 'VNDB::DB', 'VNDB::Handler');
TUWF::run();


sub reqinit {
  my $self = shift;

  # check authentication cookies
  $self->authInit;

  # Set language to English
  $self->{l10n} = VNDB::L10N->get_handle('en');

  # load some stats (used for about all pageviews, anyway)
  $self->{stats} = $self->dbStats;

  return 1;
}


sub handle404 {
  my $self = shift;
  $self->resStatus(404);
  $self->htmlHeader(title => 'Page Not Found');
  div class => 'mainbox';
   h1 'Page not found';
   div class => 'warning';
    h2 'Oops!';
    p;
     txt 'It seems the page you were looking for does not exist,';
     br;
     txt 'you may want to try using the menu on your left to find what you are looking for.';
    end;
   end;
  end;
  $self->htmlFooter;
}


# log user IDs (necessary for determining performance issues, user preferences
# have a lot of influence in this)
sub logformat {
  my($self, $uri, $msg) = @_;
  sprintf "[%s] %s %s: %s\n", scalar localtime(), $uri,
    $self->authInfo->{id} ? 'u'.$self->authInfo->{id} : '-', $msg;
}


# Figure out if a field is treated as a number in kv_validate().
sub json_validate_is_num {
  my $opts = shift;
  return 0 if !$opts->{template};
  return 1 if $opts->{template} eq 'num' || $opts->{template} eq 'int' || $opts->{template} eq 'uint';
  my $t = TUWF::set('validate_templates')->{$opts->{template}};
  return $t && json_validate_is_num($t);
}


sub json_validate_sort {
  my($sort, $fields, $data) = @_;

  # Figure out which fields need to use number comparison
  my %nums;
  for my $k (@$sort) {
    my $f = (grep $_->{field} eq $k, @$fields)[0];
    $nums{$k}++ if json_validate_is_num($f);
  }

  # Sort
  return [sort {
    for(@$sort) {
      my $r = $nums{$_} ? $a->{$_} <=> $b->{$_} : $a->{$_} cmp $b->{$_};
      return $r if $r;
    }
    0
  } @$data];
}

# Special validation function for simple JSON structures as form fields. It can
# only validate arrays of key-value objects. The key-value objects are then
# validated using kv_validate.
# TODO: json_unique implies json_sort on the same fields? These options tend to be the same.
sub json_validate {
  my($val, $opts) = @_;
  my $fields = $opts->{json_fields};
  my $maxitems = $opts->{json_maxitems};
  my $unique = $opts->{json_unique};
  my $sort = $opts->{json_sort};
  $unique = [$unique] if $unique && !ref $unique;
  $sort = [$sort] if $sort && !ref $sort;

  my $data = eval { json_decode $val };
  $_[0] = $@ ? [] : $data;
  return 0 if $@ || ref $data ne 'ARRAY';
  return 0 if defined($maxitems) && @$data > $maxitems;

  my %known_fields = map +($_->{field},1), @$fields;
  my %unique;

  for my $i (0..$#$data) {
    return 0 if ref $data->[$i] ne 'HASH';
    # Require that all keys are known and have a scalar value.
    return 0 if grep !$known_fields{$_} || ref($data->[$i]{$_}), keys %{$data->[$i]};
    $data->[$i] = kv_validate({ field => sub { $data->[$i]{shift()} } }, $TUWF::OBJ->{_TUWF}{validate_templates}, $fields);
    return 0 if $data->[$i]{_err};
    return 0 if $unique && $unique{ join '|||', map $data->[$i]{$_}, @$unique }++;
  }

  $_[0] = json_validate_sort($sort, $fields, $data) if $sort;
  return 1;
}
