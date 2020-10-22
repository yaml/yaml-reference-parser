use v5.12;
package TestReceiver;
use base 'Receiver';

use Prelude;

my $event_map = {
  stream_start => '+STR',
  stream_end => '-STR',
  document_start => '+DOC',
  document_end => '-DOC',
  mapping_start => '+MAP',
  mapping_end => '-MAP',
  sequence_start => '+SEQ',
  sequence_end => '-SEQ',
  scalar => '=VAL',
  alias => '=ALI',
};

my $style_map = {
  plain => ':',
  single => "'",
  double => '"',
  literal => '|',
  folded => '>',
};

sub output {
  my ($self) = @_;
  join '', map {
    my $type = $event_map->{$_->{event}};
    my @event = ($type);
    push @event, '---' if $type eq '+DOC' and $_->{explicit};
    push @event, '...' if $type eq '-DOC' and $_->{explicit};
    push @event, '{}' if $type eq '+MAP' and $_->{flow};
    push @event, '[]' if $type eq '+SEQ' and $_->{flow};
    push @event, "&$_->{anchor}" if $_->{anchor};
    push @event, "<$_->{tag}>" if $_->{tag};
    push @event, "*$_->{name}" if $_->{name};
    if (exists $_->{value}) {
      my $style = $style_map->{$_->{style}};
      my $value = $_->{value};
      $value =~ s/\\/\\\\/g;
      $value =~ s/\x08/\\b/g;
      $value =~ s/\t/\\t/g;
      $value =~ s/\n/\\n/g;
      $value =~ s/\r/\\r/g;
      $value =~ s/\x20\z/<SPC>/;
      push @event, "$style$value";
    }
    join(' ', @event) . "\n";
  } @{$self->{event}};
}

1;

# vim: sw=2:
