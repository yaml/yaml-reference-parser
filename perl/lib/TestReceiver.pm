use v5.12;
package TestReceiver;
use Prelude;

sub new {
  my ($class) = @_;
  bless {
    event => [],
    cache => [],
  }, $class;
}

sub add {
  my ($self, $event) = @_;
  if (@{$self->{cache}}) {
    push @{$self->{cache}[-1]}, $event;
  }
  else {
    $self->send($event);
  }
}

sub cache_up {
  my ($self, $event) = @_;
  push @{$self->{cache}}, [];
  $self->add($event) if $event;
}

sub cache_down {
  my ($self, $event) = @_;
  my $events = pop @{$self->{cache}} or xxxxx @_;
  $self->add($_) for @$events;
  $self->add($event) if $event;
}

sub cache_drop {
  my ($self) = @_;
  pop @{$self->{cache}} or xxxxx @_;
}

sub send {
  my ($self, $event) = @_;
  push @{$self->{event}}, $event;
}

sub output {
  my ($self) = @_;
  join "\n", @{$self->{event}}, '';
}

sub try__l_yaml_stream { $_[0]->add('+STR') }
sub got__l_yaml_stream { $_[0]->add('-STR') }

sub try__l_bare_document { $_[0]->add('+DOC') }
sub got__l_bare_document { $_[0]->add('-DOC') }

sub got__c_flow_mapping__all__x7b { $_[0]->add('+MAP {}') }
sub got__c_flow_mapping__all__x7d { $_[0]->add('-MAP') }

sub got__c_flow_sequence__all__x5b { $_[0]->add('+SEQ []') }
sub got__c_flow_sequence__all__x5d { $_[0]->add('-SEQ') }

sub try__l_block_mapping { $_[0]->cache_up('+MAP') }
sub got__l_block_mapping { $_[0]->cache_down('-MAP') }
sub not__l_block_mapping { $_[0]->cache_drop }

sub try__l_block_sequence { $_[0]->cache_up('+SEQ') }
sub got__l_block_sequence { $_[0]->cache_down('-SEQ') }
sub not__l_block_sequence { $_[0]->cache_drop }

sub try__ns_l_compact_mapping { $_[0]->cache_up('+MAP') }
sub got__ns_l_compact_mapping { $_[0]->cache_down('-MAP') }
sub not__ns_l_compact_mapping { $_[0]->cache_drop }

sub try__ns_flow_pair { $_[0]->cache_up }
sub got__ns_flow_pair { xxxxx @_ }
sub not__ns_flow_pair { $_[0]->cache_drop }

sub try__ns_l_block_map_implicit_entry{ $_[0]->cache_up() }
sub got__ns_l_block_map_implicit_entry{ $_[0]->cache_down() }
sub not__ns_l_block_map_implicit_entry{ $_[0]->cache_drop() }

sub try__c_ns_flow_map_empty_key_entry { $_[0]->cache_up }
sub got__c_ns_flow_map_empty_key_entry { xxxxx @_ }
sub not__c_ns_flow_map_empty_key_entry { $_[0]->cache_drop }

sub got__ns_plain { $_[0]->add("=VAL :${\ $_[1]->{text}}"); }
sub got__c_single_quoted {
  $_[0]->add("=VAL \'${\substr($_[1]->{text}, 1, -1)}");
}
sub got__c_double_quoted {
  $_[0]->add("=VAL \"${\substr($_[1]->{text}, 1, -1)}");
}
sub got__e_scalar { $_[0]->add("=VAL :") }

1;

# vim: sw=2:
