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
    my $value = exists $_->{value} ? $_->{value} : '';
    $value =~ s/\\/\\\\/g;
    $value =~ s/\n/\\n/g;
    $value =~ s/\t/\\t/g;
    $value =~ s/\ \z/<SPC>/;
    $_->{type}
    . ($_->{marker} ? " $_->{marker}" : '')
    . ($_->{anchor} ? " $_->{anchor}" : '')
    . ($_->{tag} ? " <$_->{tag}>" : '')
    . ($value ? " $value" : '')
    . "\n"
  } @{$self->{event}};
}

sub try__l_yaml_stream {
  my ($self) = @_;
  $self->add('+STR');
  $self->{tag_map} = {};
}
sub got__l_yaml_stream { $_[0]->add('-STR') }

sub got__c_tag_handle {
  my ($self, $o) = @_;
  $self->{tag_handle} = $o->{text};
}
sub got__ns_tag_prefix {
  my ($self, $o) = @_;
  $self->{tag_map}{$self->{tag_handle}} = $o->{text};
}

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
  my ($self) = @_;
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
  my ($self) = @_;
  my $event = $_[0]->cache_drop->[0];
  $self->{anchor} = $event->{anchor};
  $self->{tag} = $event->{tag};
}

sub try__ns_l_compact_mapping { $_[0]->cache_up('+MAP') }
sub got__ns_l_compact_mapping { $_[0]->cache_down('-MAP') }
sub not__ns_l_compact_mapping { $_[0]->cache_drop }

sub try__ns_flow_pair { $_[0]->cache_up('+MAP {}') }
sub got__ns_flow_pair { $_[0]->cache_down('-MAP') }
sub not__ns_flow_pair { $_[0]->cache_drop }

sub try__ns_l_block_map_implicit_entry{ $_[0]->cache_up }
sub got__ns_l_block_map_implicit_entry{ $_[0]->cache_down }
sub not__ns_l_block_map_implicit_entry{ $_[0]->cache_drop }

sub try__c_l_block_map_explicit_entry{ $_[0]->cache_up }
sub got__c_l_block_map_explicit_entry{ $_[0]->cache_down }
sub not__c_l_block_map_explicit_entry{ $_[0]->cache_drop }

sub try__c_ns_flow_map_empty_key_entry { $_[0]->cache_up }
sub got__c_ns_flow_map_empty_key_entry { FAIL 'got__c_ns_flow_map_empty_key_entry' }
sub not__c_ns_flow_map_empty_key_entry { $_[0]->cache_drop }

sub got__ns_plain {
  my ($self, $o) = @_;
  my $text = $o->{text};
  $text =~ s/(?:[\ \t]*\r?\n[\ \t]*)/\n/g;
  $text =~ s/(\n)(\n*)/length($2) ? $2 : ' '/ge;
  $self->add('=VAL', qq<:$text>);
}

sub got__c_single_quoted {
  my ($self, $o) = @_;
  my $text = substr($o->{text}, 1, -1);
  $text =~ s/(?:[\ \t]*\r?\n[\ \t]*)/\n/g;
  $text =~ s/(\n)(\n*)/length($2) ? $2 : ' '/ge;
  $text =~ s/''/'/g;
  $self->add('=VAL', qq<'$text>);
}

sub got__c_double_quoted {
  my ($self, $o) = @_;
  my $text = substr($o->{text}, 1, -1);
  $text =~ s/(?:[\ \t]*\r?\n[\ \t]*)/\n/g;
  $text =~ s/\\\n[\ \t]*//g;
  $text =~ s/(\n)(\n*)/length($2) ? $2 : ' '/ge;
  $text =~ s/\\(["\/])/$1/g;
  $text =~ s/\\ / /g;
  $text =~ s/\\t/\t/g;
  $text =~ s/\\n/\n/g;
  $text =~ s/\\\\/\\/g;
  $self->add('=VAL', qq<"$text>);
}

sub got__l_empty {
  my ($self) = @_;
  $self->add(undef, '') if $self->{in_scalar};
}
sub got__l_nb_literal_text__all__rep2 {
  my ($self, $o) = @_;
  $self->add(undef, $o->{text});
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
  my $text = join '', map "$_->{value}\n", @$lines;
  my $t = $self->{parser}->state_curr->{t};
  if ($t eq 'clip') {
    $text =~ s/\n+\z/\n/;
  }
  elsif ($t eq 'strip') {
    $text =~ s/\n+\z//;
  }
  $self->add('=VAL', qq<|$text>);
}
sub not__c_l_literal {
  my ($self) = @_;
  delete $self->{in_scalar};
  $_[0]->cache_drop;
}

sub got__ns_char {
  my ($self, $o) = @_;
  $self->{ns_char} = $o->{text} if $self->{in_scalar};
}
sub got__s_nb_folded_text__all__rep {
  my ($self, $o) = @_;
  $self->add(undef, "$self->{ns_char}$o->{text}");
}
sub try__c_l_folded {
  my ($self) = @_;
  $self->{in_scalar} = true;
  $self->cache_up;
}
sub got__c_l_folded {
  my ($self) = @_;
  delete $self->{in_scalar};
  my $lines = $self->cache_drop;
  my $text = join '', map "$_->{value}\n", @$lines;
  $text =~ s/(\n+)(?=.)/("\n" x (length($1) -1)) || ' '/ge;
  my $t = $self->{parser}->state_curr->{t};
  if ($t eq 'clip') {
    $text =~ s/\n+\z/\n/;
  }
  elsif ($t eq 'strip') {
    $text =~ s/\n+\z//;
  }
  $self->add('=VAL', qq{>$text});
}
sub not__c_l_folded {
  my ($self) = @_;
  delete $self->{in_scalar};
  $_[0]->cache_drop;
}

sub got__e_scalar { $_[0]->add('=VAL', ':') }

sub got__c_ns_anchor_property { $_[0]->{anchor} = $_[1]->{text} }

sub got__c_ns_tag_property {
  my ($self, $o) = @_;
  my $tag = $o->{text};
  if ($tag =~ /^!!(.*)/) {
    if (defined(my $prefix = $self->{tag_map}{'!!'})) {
      $self->{tag} = $prefix . substr($tag, 2);
    }
    else {
      $self->{tag} = "tag:yaml.org,2002:$1";
    }
  }
  elsif (
    $tag =~ /^(!.*?!)/ and
    defined(my $prefix = $self->{tag_map}{$1})
  ) {
    $self->{tag} = $prefix . substr($tag, length($1));
  }
  elsif (defined(my $prefix = $self->{tag_map}{'!'})) {
    $self->{tag} = $prefix . substr($tag, 1);
  }
  else {
    $self->{tag} = $tag;
  }
  $self->{tag} =~ s/%([0-9a-fA-F]{2})/chr(hex($1))/eg;
}

sub got__c_ns_alias_node { $_[0]->add("=ALI $_[1]->{text}") }

1;

# vim: sw=2:
