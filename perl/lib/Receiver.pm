use v5.12;
package Receiver;
use Prelude;

sub stream_start_event {
  { event => 'stream_start' };
}
sub stream_end_event {
  { event => 'stream_end' };
}
sub document_start_event {
  { event => 'document_start', explicit => (shift || false), version => undef };
}
sub document_end_event {
  { event => 'document_end', explicit => (shift || false) };
}
sub mapping_start_event {
  { event => 'mapping_start', flow => (shift || false) };
}
sub mapping_end_event {
  { event => 'mapping_end' };
}
sub sequence_start_event {
  { event => 'sequence_start', flow => (shift || false) };
}
sub sequence_end_event {
  { event => 'sequence_end' };
}
sub scalar_event {
  my ($style, $value) = @_;
  { event => 'scalar', style => $style, value => $value };
}
sub alias_event {
  { event => 'alias', name => (shift) };
}
sub cache {
  { text => (shift) };
}

sub new {
  my ($class) = @_;
  bless {
    event => [],
    cache => [],
  }, $class;
}

sub send {
  my ($self, $event) = @_;
  if (my $callback = $self->{callback}) {
    $callback->($event);
  }
  else {
    push @{$self->{event}}, $event;
  }
}

sub add {
  my ($self, $event) = @_;
  if (defined $event->{event}) {
    if (my $anchor = $self->{anchor}) {
      $event->{anchor} = delete $self->{anchor};
    }
    if (my $tag = $self->{tag}) {
      $event->{tag} = delete $self->{tag};
    }
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
    if ($event->{event} =~ /(mapping_start|sequence_start|scalar)/) {
      $self->check_document_start;
    }
    $self->send($event);
  }
}

sub cache_up {
  my ($self, $event) = @_;
  CORE::push @{$self->{cache}}, [];
  $self->add($event) if $event;
}

sub cache_down {
  my ($self, $event) = @_;
  my $events = pop @{$self->{cache}} or FAIL 'cache_down';
  $self->push($_) for @$events;
  $self->add($event) if $event;
}

sub cache_drop {
  my ($self) = @_;
  my $events = pop @{$self->{cache}} or FAIL 'cache_drop';
  return $events;
}

sub cache_get {
  my ($self, $type) = @_;
  return
    $self->{cache}[-1] &&
    $self->{cache}[-1][0] &&
    $self->{cache}[-1][0]{event} eq $type &&
    $self->{cache}[-1][0];
}

sub check_document_start {
  my ($self) = @_;
  return unless $self->{document_start};
  $self->send($self->{document_start});
  delete $self->{document_start};
  $self->{document_end} = document_end_event;
}

sub check_document_end {
  my ($self) = @_;
  return unless $self->{document_end};
  $self->send($self->{document_end});
  delete $self->{document_end};
  $self->{tag_map} = {};
  $self->{document_start} = document_start_event;
}

#------------------------------------------------------------------------------
sub try__l_yaml_stream {
  my ($self) = @_;
  $self->add(stream_start_event);
  $self->{tag_map} = {};
  $self->{document_start} = document_start_event;
  delete $self->{document_end};
}
sub got__l_yaml_stream {
  my ($self) = @_;
  $self->check_document_end;
  $self->add(stream_end_event);
}

sub got__ns_yaml_version {
  my ($self, $o) = @_;
  die "Multiple %YAML directives not allowed"
    if defined $self->{document_start}{version};
  $self->{document_start}{version} = $o->{text};
}

sub got__c_tag_handle {
  my ($self, $o) = @_;
  $self->{tag_handle} = $o->{text};
}
sub got__ns_tag_prefix {
  my ($self, $o) = @_;
  $self->{tag_map}{$self->{tag_handle}} = $o->{text};
}

sub got__c_directives_end {
  my ($self) = @_;
  $self->check_document_end;
  $self->{document_start}{explicit} = true;
}
sub got__c_document_end {
  my ($self) = @_;
  $self->{document_end}{explicit} = true
    if defined $self->{document_end};
  $self->check_document_end;
}

sub got__c_flow_mapping__all__x7b { $_[0]->add(mapping_start_event(true)) }
sub got__c_flow_mapping__all__x7d { $_[0]->add(mapping_end_event) }

sub got__c_flow_sequence__all__x5b { $_[0]->add(sequence_start_event(true)) }
sub got__c_flow_sequence__all__x5d { $_[0]->add(sequence_end_event) }

sub try__l_block_mapping { $_[0]->cache_up(mapping_start_event) }
sub got__l_block_mapping { $_[0]->cache_down(mapping_end_event) }
sub not__l_block_mapping { $_[0]->cache_drop }

sub try__l_block_sequence { $_[0]->cache_up(sequence_start_event) }
sub got__l_block_sequence { $_[0]->cache_down(sequence_end_event) }
sub not__l_block_sequence {
  my ($self) = @_;
  my $event = $_[0]->cache_drop->[0];
  $self->{anchor} = $event->{anchor};
  $self->{tag} = $event->{tag};
}

sub try__ns_l_compact_mapping { $_[0]->cache_up(mapping_start_event) }
sub got__ns_l_compact_mapping { $_[0]->cache_down(mapping_end_event) }
sub not__ns_l_compact_mapping { $_[0]->cache_drop }

sub try__ns_l_compact_sequence { $_[0]->cache_up(sequence_start_event) }
sub got__ns_l_compact_sequence { $_[0]->cache_down(sequence_end_event) }
sub not__ns_l_compact_sequence { $_[0]->cache_drop }

sub try__ns_flow_pair { $_[0]->cache_up(mapping_start_event(true)) }
sub got__ns_flow_pair { $_[0]->cache_down(mapping_end_event) }
sub not__ns_flow_pair { $_[0]->cache_drop }

sub try__ns_l_block_map_implicit_entry { $_[0]->cache_up }
sub got__ns_l_block_map_implicit_entry { $_[0]->cache_down }
sub not__ns_l_block_map_implicit_entry { $_[0]->cache_drop }

sub try__c_l_block_map_explicit_entry { $_[0]->cache_up }
sub got__c_l_block_map_explicit_entry { $_[0]->cache_down }
sub not__c_l_block_map_explicit_entry { $_[0]->cache_drop }

sub try__c_ns_flow_map_empty_key_entry { $_[0]->cache_up }
sub got__c_ns_flow_map_empty_key_entry { $_[0]->cache_down }
sub not__c_ns_flow_map_empty_key_entry { $_[0]->cache_drop }

sub got__ns_plain {
  my ($self, $o) = @_;
  my $text = $o->{text};
  $text =~ s/(?:[\ \t]*\r?\n[\ \t]*)/\n/g;
  $text =~ s/(\n)(\n*)/length($2) ? $2 : ' '/ge;
  $self->add(scalar_event(plain => $text));
}

sub got__c_single_quoted {
  my ($self, $o) = @_;
  my $text = substr($o->{text}, 1, -1);
  $text =~ s/(?:[\ \t]*\r?\n[\ \t]*)/\n/g;
  $text =~ s/(\n)(\n*)/length($2) ? $2 : ' '/ge;
  $text =~ s/''/'/g;
  $self->add(scalar_event(single => $text));
}

sub got__c_double_quoted {
  my ($self, $o) = @_;
  my $text = substr($o->{text}, 1, -1);
  $text =~ s/(?:[\ \t]*\r?\n[\ \t]*)/\n/g;
  $text =~ s/\\\n[\ \t]*//g;
  $text =~ s/(\n)(\n*)/length($2) ? $2 : ' '/ge;
  $text =~ s/\\(["\/])/$1/g;
  $text =~ s/\\ / /g;
  $text =~ s/\\b/\b/g;
  $text =~ s/\\t/\t/g;
  $text =~ s/\\n/\n/g;
  $text =~ s/\\r/\r/g;
  $text =~ s/\\x([0-9a-fA-F]{2})/chr(hex($1))/eg;
  $text =~ s/\\u([0-9a-fA-F]{4})/chr(hex($1))/eg;
  $text =~ s/\\U([0-9a-fA-F]{8})/chr(hex($1))/eg;
  $text =~ s/\\\\/\\/g;
  $self->add(scalar_event(double => $text));
}

sub got__l_empty {
  my ($self) = @_;
  $self->add(cache '') if $self->{in_scalar};
}
sub got__l_nb_literal_text__all__rep2 {
  my ($self, $o) = @_;
  $self->add(cache $o->{text});
}
sub try__c_l_literal {
  my ($self) = @_;
  $self->{in_scalar} = true;
  $self->cache_up;
}
sub got__c_l_literal {
  my ($self) = @_;
  delete $self->{in_scalar};
  my $lines = $self->cache_drop;
  pop @$lines if @$lines and $lines->[-1]{text} eq '';
  my $text = join '', map "$_->{text}\n", @$lines;
  my $t = $self->{parser}->state_curr->{t};
  if ($t eq 'clip') {
    $text =~ s/\n+\z/\n/;
  }
  elsif ($t eq 'strip') {
    $text =~ s/\n+\z//;
  }
  $self->add(scalar_event(literal => $text));
}
sub not__c_l_literal {
  my ($self) = @_;
  delete $self->{in_scalar};
  $_[0]->cache_drop;
}

sub got__ns_char {
  my ($self, $o) = @_;
  $self->{first} = $o->{text} if $self->{in_scalar};
}
sub got__s_white {
  my ($self, $o) = @_;
  $self->{first} = $o->{text} if $self->{in_scalar};
}
sub got__s_nb_folded_text__all__rep {
  my ($self, $o) = @_;
  $self->add(cache "$self->{first}$o->{text}");
}
sub got__s_nb_spaced_text__all__rep {
  my ($self, $o) = @_;
  $self->add(cache "$self->{first}$o->{text}");
}
sub try__c_l_folded {
  my ($self) = @_;
  $self->{in_scalar} = true;
  $self->{first} = '';
  $self->cache_up;
}
sub got__c_l_folded {
  my ($self) = @_;
  delete $self->{in_scalar};

  my @lines = map $_->{text}, @{$self->cache_drop};
  my $text = join "\n", @lines;
  $text =~ s/^(\S.*)\n(?=\S)/$1 /gm;
  $text =~ s/^(\S.*)\n(\n+)/$1$2/gm;
  $text =~ s/^([\ \t]+\S.*)\n(\n+)(?=\S)/$1$2/gm;
  $text .= "\n";

  my $t = $self->{parser}->state_curr->{t};
  if ($t eq 'clip') {
    $text =~ s/\n+\z/\n/;
    $text = '' if $text eq "\n";
  }
  elsif ($t eq 'strip') {
    $text =~ s/\n+\z//;
  }
  $self->add(scalar_event(folded => $text));
}
sub not__c_l_folded {
  my ($self) = @_;
  delete $self->{in_scalar};
  $_[0]->cache_drop;
}

sub got__e_scalar { $_[0]->add(scalar_event(plain => '')) }

sub not__s_l_block_collection__all__rep__all__any__all {
  my ($self) = @_;
  delete $self->{anchor};
  delete $self->{tag};
}

sub got__c_ns_anchor_property {
  my ($self, $o) = @_;
  $self->{anchor} = substr($o->{text}, 1);
}

sub got__c_ns_tag_property {
  my ($self, $o) = @_;
  my $tag = $o->{text};
  my $prefix;
  if ($tag =~ /^!<(.*)>$/) {
    $self->{tag} = $1;
  }
  elsif ($tag =~ /^!!(.*)/) {
    if (defined($prefix = $self->{tag_map}{'!!'})) {
      $self->{tag} = $prefix . substr($tag, 2);
    }
    else {
      $self->{tag} = "tag:yaml.org,2002:$1";
    }
  }
  elsif ($tag =~ /^(!.*?!)/) {
    $prefix = $self->{tag_map}{$1};
    if (defined $prefix) {
      $self->{tag} = $prefix . substr($tag, length($1));
    }
    else {
      die "No %TAG entry for '$prefix'";
    }
  }
  elsif (defined($prefix = $self->{tag_map}{'!'})) {
    $self->{tag} = $prefix . substr($tag, 1);
  }
  else {
    $self->{tag} = $tag;
  }
  $self->{tag} =~ s/%([0-9a-fA-F]{2})/chr(hex($1))/eg;
}

sub got__c_ns_alias_node {
  my ($self, $o) = @_;
  my $name = $o->{text};
  $name =~ s/^\*//;
  $self->add(alias_event($name));
}

1;

# vim: sw=2:
