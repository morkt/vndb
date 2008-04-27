
package VNDB::Util::Tools;

use strict;
use warnings;
use Encode;
use Tie::ShareLite ':lock';
use Exporter 'import';

our $VERSION = $VNDB::VERSION;
our @EXPORT = qw| FormCheck AddHid SendMail AddDefaultStuff RunCmd |;


# Improved version of ParamsCheck
#  - hashref instead of hash
#  - parameters don't start with form*
sub FormCheck {
  my $self = shift;
  my @ps = @_;
  my %hash; my @err;
 
  foreach my $i (0..$#ps) {
    next if !$ps[$i] || ref($ps[$i]) ne 'HASH';
    my $k = $ps[$i]{name};
    $hash{$k} = [ ( $self->ReqParam($k) ) ];
    $hash{$k}[0] = '' if !defined $hash{$k}[0];
    foreach my $j (0..$#{$hash{$k}}) {
      my $val = \$hash{$k}[$j]; my $e = 0;
      $e = 1 if !$e && $ps[$i]{required} && !$$val && length($$val) < 1 && $$val ne '0';
      $e = 2 if !$e && $ps[$i]{minlength} && length($$val) < $ps[$i]{minlength};
      $e = 3 if !$e && $ps[$i]{maxlength} && length($$val) > $ps[$i]{maxlength};
      if(!$e && $ps[$i]{template}) {
        my $t = $ps[$i]{template};
        $hash{$k}[$j] = lc $hash{$k}[$j] if $t eq 'pname';
        $e = 4 if ($t eq 'mail' && $$val !~    # From regexlib.com, author: Gavin Sharp
            /^(([A-Za-z0-9]+_+)|([A-Za-z0-9]+\-+)|([A-Za-z0-9]+\.+)|([A-Za-z0-9]+\++))*[A-Za-z0-9]+\@((\w+\-+)|(\w+\.))*\w{1,63}\.[a-zA-Z]{2,6}$/)
          || ($t eq 'url' && $$val !~          # From regexlib.com, author: M H
            /^(http|https):\/\/[\w\-_]+(\.[\w\-_]+)+([\w\-\.,@?^=%&:\/~\+#]*[\w\-\@?^=%&\/~\+#])?$/)
          || ($t eq 'pname' && $$val !~ /^[a-z0-9][a-z0-9\-]*$/)
          || ($t eq 'asciiprint' && $$val !~ /^[\x20-\x7E]*$/)
          || ($t eq 'int' && $$val !~ /^\-?[0-9]+$/)
          || ($t eq 'date' && $$val !~ /^[0-9]{4}(-[0-9]{2}(-[0-9]{2})?)?$/);
      }
      $e = 5 if !$e && $ps[$i]{enum} && ref($ps[$i]{enum}) eq "ARRAY" && !_inarray($$val, $ps[$i]{enum});
      if($e) {
        if($ps[$i]{required}) {
          my $errc = $ps[$i]{name}.'_'.$e;
          $errc .= '_'.$ps[$i]{minlength} if $e == 2;
          $errc .= '_'.$ps[$i]{maxlength} if $e == 3;
          $errc .= '_'.$ps[$i]{template} if $e == 4;
          push(@err, $errc);
          last;
        } else {
          $hash{$k}[$j] = exists $ps[$i]{default} ? $ps[$i]{default} : undef;
        }
      }
      last if !$ps[$i]{multi};
    }
    $hash{$k} = $hash{$k}[0] if !$ps[$i]{multi};
  }
  $hash{_err} = $#err >= 0 ? \@err : 0;

  return \%hash;
}


sub AddHid {
  my $fh = $_[0]->FormCheck({ name => 'fh', required => 0, maxlength => 30 })->{fh};
  $_[1]->{_hid} = { map { $_ => 1 } 'com', 'mod', split /,/, $fh }
    if $fh;
}


sub _inarray { # errr... this is from when I didn't know about grep
  foreach (@{$_[1]}) {
    (return 1) if $_[0] eq $_;
  }
  return 0;
}


sub SendMail {
  my $self = shift;
  my $body = shift;
  my %hs = @_;

  die "No To: specified!\n" if !$hs{To};
  die "No Subject specified!\n" if !$hs{Subject};
  $hs{'Content-Type'} ||= 'text/plain; charset=\'UTF-8\'';
  $hs{From} ||= 'vndb <noreply@vndb.org>';
  $hs{'X-mailer'} ||= "VNDB $VERSION";
  $body =~ s/\r?\n/\n/g; # force a '\n'-linebreak

  my $mail = '';
  foreach (keys %hs) {
    $hs{$_} =~ s/[\r\n]//g;
    $mail .= sprintf "%s: %s\n", $_, $hs{$_};
  }
  $mail .= sprintf "\n%s", $body;

  if(open(my $mailer, "|/usr/sbin/sendmail -t -f '$hs{From}'")) {
    print $mailer encode('UTF-8', $mail);
    die "Error running sendmail ($!)"
      if !close($mailer);
  } else {
    die "Error opening sendail: $!";
  }
}


sub AddDefaultStuff {
  my $self = shift;

  $self->AuthAddTpl;
  $self->ResAddTpl(st => $self->{static_url});

  $self->ResAddTpl('Stat'.$_, $self->DBTableCount($_))
    for (qw|users producers vn releases votes|);

 # development shit
  if($self->{debug}) {
    my $sqls;
    for (@{$self->{_DB}->{Queries}}) {
      $_->[0] =~ s/^\s//g;
      $sqls .= sprintf("[%6.2fms] %s\n", $_->[1]*1000, $_->[0] || '[undef]');
    }
    $self->ResAddTpl(devshit => $sqls);
  }
}


sub RunCmd { # cmd
  my $s = tie my %s, 'Tie::ShareLite', @VNDB::SHMOPTS;
  $s->lock(LOCK_EX);
  $s{queue} = [] if !$s{queue};
  push(@{$s{queue}}, grep !/^-/, $_[1]);
  $s->unlock();
}


1;

