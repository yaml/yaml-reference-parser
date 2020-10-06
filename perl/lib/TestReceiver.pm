use v5.12;
package TestReceiver;
use Prelude;

sub new {
  my ($class) = @_;
  bless {
    event => [],
    cache => [],
    props => undef,
  }, $class;
}

sub add {
  my ($self, $type, $value) = @_;
  my $event = { type => $type };
  if ($self->{marker}) {
    $event->{marker} = delete $self->{marker};
  }
  if (my $anchor = $self->{anchor}) {
    $event->{anchor} = delete $self->{anchor};
  }
  if (my $tag = $self->{tag}) {
    $event->{tag} = delete $self->{tag};
  }
  if (defined $value) {
    $event->{value} = $value;
  }
  $self->push($event);
  return $event;
}

sub push {
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
  $self->push($_) for @$events;
  $self->add($event) if $event;
}

sub cache_drop {
  my ($self) = @_;
  my $events = pop @{$self->{cache}} or xxxxx @_;
  return $events->[0];
}

sub cache_get {
  my ($self, $type) = @_;
  return
    $self->{cache}[-1] &&
    $self->{cache}[-1][0] &&
    $self->{cache}[-1][0]{type} eq $type &&
    $self->{cache}[-1][0];
}

sub send {
  my ($self, $event) = @_;
  push @{$self->{event}}, $event;
}

sub output {
  my ($self) = @_;
  join '', map {
    $_->{type}
    . ($_->{marker} ? " $_->{marker}" : '')
    . ($_->{anchor} ? " $_->{anchor}" : '')
    . ($_->{tag} ? " <$_->{tag}>" : '')
    . ($_->{value} ? " $_->{value}" : '')
    . "\n"
  } @{$self->{event}};
}

sub try__l_yaml_stream { $_[0]->add('+STR') }
sub got__l_yaml_stream { $_[0]->add('-STR') }

sub try__l_bare_document {
  my ($self) = @_;
  my $parser = $self->{parser};
  if (
    substr($parser->{input}, $parser->{pos}) =~
      /^(\s|\#.*\n?)*\S/
  ) {
    $self->add('+DOC');
  }
}
sub got__l_bare_document { $_[0]->cache_up('-DOC') }
sub got__c_directives_end { $_[0]->{marker} = '---' }
sub got__c_document_end {
  my ($self) = @_;
  if (my $event = $self->cache_get('-DOC')) {
    $event->{marker} = '...';
    $self->cache_down;
  }
}
sub not__c_document_end {
  if ($_[0]->cache_get('-DOC')) {
    $_[0]->cache_down;
  }
}

sub got__c_flow_mapping__all__x7b { $_[0]->add('+MAP {}') }
sub got__c_flow_mapping__all__x7d { $_[0]->add('-MAP') }

sub got__c_flow_sequence__all__x5b { $_[0]->add('+SEQ []') }
sub got__c_flow_sequence__all__x5d { $_[0]->add('-SEQ') }

sub try__l_block_mapping { $_[0]->cache_up('+MAP') }
sub got__l_block_mapping { $_[0]->cache_down('-MAP') }
sub not__l_block_mapping { $_[0]->cache_drop }

sub try__l_block_sequence { $_[0]->cache_up('+SEQ') }
sub got__l_block_sequence { $_[0]->cache_down('-SEQ') }
sub not__l_block_sequence {
  my $event = $_[0]->cache_drop;
  $_[0]->{anchor} = $event->{anchor};
  $_[0]->{tag} = $event->{tag};
}

sub try__ns_l_compact_mapping { $_[0]->cache_up('+MAP') }
sub got__ns_l_compact_mapping { $_[0]->cache_down('-MAP') }
sub not__ns_l_compact_mapping { $_[0]->cache_drop }

sub try__ns_flow_pair { $_[0]->cache_up }
sub got__ns_flow_pair { xxxxx @_ }
sub not__ns_flow_pair { $_[0]->cache_drop }

sub try__ns_l_block_map_implicit_entry{ $_[0]->cache_up }
sub got__ns_l_block_map_implicit_entry{ $_[0]->cache_down }
sub not__ns_l_block_map_implicit_entry{ $_[0]->cache_drop }

sub try__c_ns_flow_map_empty_key_entry { $_[0]->cache_up }
sub got__c_ns_flow_map_empty_key_entry { xxxxx @_ }
sub not__c_ns_flow_map_empty_key_entry { $_[0]->cache_drop }

sub got__ns_plain { $_[0]->add('=VAL', ':'.$_[1]->{text}) }
sub got__c_single_quoted {
  $_[0]->add('=VAL', "'".substr($_[1]->{text}, 1, -1));
}
sub got__c_double_quoted {
  $_[0]->add('=VAL', '"'.substr($_[1]->{text}, 1, -1));
}
sub got__e_scalar { $_[0]->add('=VAL', ':') }

sub got__c_ns_anchor_property { $_[0]->{anchor} = $_[1]->{text} }

sub got__c_ns_tag_property { $_[0]->{tag} = $_[1]->{text} }

sub got__c_ns_alias_node { $_[0]->add("=ALI $_[1]->{text}") }

1;

# vim: sw=2:
