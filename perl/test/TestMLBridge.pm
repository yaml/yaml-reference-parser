use v5.12;
package TestMLBridge;
use base 'TestML::Bridge';

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
  $text =~ s/<SPC>/ /g;
  $text =~ s/<TAB>/\t/g;
  return $text;
}

sub fix_test_output {
  my ($self, $text) = @_;
  $text =~ s/^\+MAP\ \{\}/+MAP/gm;
  $text =~ s/^\+SEQ\ \[\]/+SEQ/gm;
  return $text;
}

1;
