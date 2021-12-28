use v5.12;
package TestMLBridge;
use base 'TestML::Bridge';
use utf8;

use lib 'lib';

use Prelude;
use Parser;
use TestReceiver;

sub parse {
  my ($self, $yaml, $expect_error) = @_;

  my $parser = Parser->new(TestReceiver->new);

  eval { $parser->parse($yaml) };
  my $error = $@;

  if (defined $expect_error) {
    return $error ? 1 : 0;
  }

  return $error
    ? do { warn $error; '' }
    : $parser->{receiver}->output;
}

sub unescape {
  my ($self, $text) = @_;

  $text =~ s/␣/ /g;
  $text =~ s/—*»/\t/g;
  $text =~ s/⇔/x{FEFF}/g;
  $text =~ s/↵//g;
  $text =~ s/∎\n\z//;

  # $text =~ s/↓/\r/g;

  return $text;
}

sub fix_test_output {
  my ($self, $text) = @_;
  return $text;
}

1;
