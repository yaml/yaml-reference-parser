#!/usr/bin/env perl

use v5.12;
use Encode;
use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../ext/perl/lib/perl5";

BEGIN { -d "$FindBin::Bin/../ext" || `cd $FindBin::Bin/.. && make ext/perl 2>&1` }

use Prelude;
use Parser;
use TestReceiver;

my $events = false;

sub main {
  my ($yaml) = @_;
  $yaml //= file_read '-';

  my $parser = Parser->new(TestReceiver->new);

  my $pass = true;
  my $start = timer;

  eval {
    $parser->parse($yaml);
  };
  if ($@) {
    warn $@;
    $pass = false;
  }

  my $time = timer($start);

  my $n;
  if ($yaml =~ /\n./) {
    $n = "\n";
  }
  else {
    $n = '';
    $yaml =~ s/\n$/\\n/;
  }

  if ($events) {
    print encode_utf8($parser->{receiver}->output());
    return 0;
  }
  elsif ($pass) {
    say encode_utf8("PASS - '$n$yaml'");
    say encode_utf8($parser->{receiver}->output());
    say sprintf "Parse time %.5fs", $time;
    return 1
  }
  else {
    say encode_utf8("FAIL - '$n$yaml'");
    say encode_utf8($parser->{receiver}->output());
    say sprintf "Parse time %.5fs", $time;
    return 0;
  }
}

if (@ARGV and $ARGV[0] eq '--events') {
  $events = true;
  shift @ARGV;
}

if (main @ARGV) {
  exit 0;
}
else {
  exit 1;
}

# vim: sw=2:
