# ABSTRACT: Construct data structure from Parser Events
use strict;
use warnings;
package YAML::PP::Constructor;

our $VERSION = '0.025'; # VERSION

use YAML::PP;
use YAML::PP::Common qw/ PRESERVE_ALL PRESERVE_ORDER PRESERVE_SCALAR_STYLE PRESERVE_FLOW_STYLE /;
use Scalar::Util qw/ reftype /;

use constant DEBUG => ($ENV{YAML_PP_LOAD_DEBUG} or $ENV{YAML_PP_LOAD_TRACE}) ? 1 : 0;
use constant TRACE => $ENV{YAML_PP_LOAD_TRACE} ? 1 : 0;

my %cyclic_refs = qw/ allow 1 ignore 1 warn 1 fatal 1 /;

sub new {
    my ($class, %args) = @_;

    my $default_yaml_version = delete $args{default_yaml_version};
    my $preserve = delete $args{preserve} || 0;
    if ($preserve == PRESERVE_ALL) {
        $preserve = PRESERVE_ORDER | PRESERVE_SCALAR_STYLE | PRESERVE_FLOW_STYLE;
    }
    my $cyclic_refs = delete $args{cyclic_refs} || 'allow';
    die "Invalid value for cyclic_refs: $cyclic_refs"
        unless $cyclic_refs{ $cyclic_refs };
    my $schemas = delete $args{schemas};

    if (keys %args) {
        die "Unexpected arguments: " . join ', ', sort keys %args;
    }

    my $self = bless {
        default_yaml_version => $default_yaml_version,
        schemas => $schemas,
        cyclic_refs => $cyclic_refs,
        preserve => $preserve,
    }, $class;
    $self->init;
    return $self;
}

sub clone {
    my ($self) = @_;
    my $clone = {
        schemas => $self->{schemas},
        schema => $self->{schema},
        default_yaml_version => $self->{default_yaml_version},
        cyclic_refs => $self->cyclic_refs,
        preserve => $self->{preserve},
    };
    return bless $clone, ref $self;
}

sub init {
    my ($self) = @_;
    $self->set_docs([]);
    $self->set_stack([]);
    $self->set_anchors({});
    $self->set_yaml_version($self->default_yaml_version);
    $self->set_schema($self->schemas->{ $self->yaml_version } );
}

sub docs { return $_[0]->{docs} }
sub stack { return $_[0]->{stack} }
sub anchors { return $_[0]->{anchors} }
sub set_docs { $_[0]->{docs} = $_[1] }
sub set_stack { $_[0]->{stack} = $_[1] }
sub set_anchors { $_[0]->{anchors} = $_[1] }
sub schemas { return $_[0]->{schemas} }
sub schema { return $_[0]->{schema} }
sub set_schema { $_[0]->{schema} = $_[1] }
sub cyclic_refs { return $_[0]->{cyclic_refs} }
sub set_cyclic_refs { $_[0]->{cyclic_refs} = $_[1] }
sub yaml_version { return $_[0]->{yaml_version} }
sub set_yaml_version { $_[0]->{yaml_version} = $_[1] }
sub default_yaml_version { return $_[0]->{default_yaml_version} }
sub preserve_order { return $_[0]->{preserve} & PRESERVE_ORDER }
sub preserve_scalar_style { return $_[0]->{preserve} & PRESERVE_SCALAR_STYLE }
sub preserve_flow_style { return $_[0]->{preserve} & PRESERVE_FLOW_STYLE }

sub document_start_event {
    my ($self, $event) = @_;
    my $stack = $self->stack;
    if ($event->{version_directive}) {
        my $version = $event->{version_directive};
        $version = "$version->{major}.$version->{minor}";
        if ($self->{schemas}->{ $version }) {
            $self->set_yaml_version($version);
            $self->set_schema($self->schemas->{ $version });
        }
        else {
            $self->set_yaml_version($self->default_yaml_version);
            $self->set_schema($self->schemas->{ $self->default_yaml_version });
        }
    }
    my $ref = [];
    push @$stack, { type => 'document', ref => $ref, data => $ref, event => $event };
}

sub document_end_event {
    my ($self, $event) = @_;
    my $stack = $self->stack;
    my $last = pop @$stack;
    $last->{type} eq 'document' or die "Expected mapping, but got $last->{type}";
    if (@$stack) {
        die "Got unexpected end of document";
    }
    my $docs = $self->docs;
    push @$docs, $last->{ref}->[0];
    $self->set_anchors({});
    $self->set_stack([]);
}

sub mapping_start_event {
    my ($self, $event) = @_;
    my ($data, $on_data) = $self->schema->create_mapping($self, $event);
    my $ref = {
        type => 'mapping',
        ref => [],
        data => \$data,
        event => $event,
        on_data => $on_data,
    };
    my $stack = $self->stack;

    my $preserve_order = $self->preserve_order;
    my $preserve_style = $self->preserve_flow_style;
    if (($preserve_order or $preserve_style) and not tied(%$data)) {
        tie %$data, 'YAML::PP::Preserve::Hash';
    }
    if ($preserve_style) {
        my $t = tied %$data;
        $t->{style} = $event->{style};
    }

    push @$stack, $ref;
    if (defined(my $anchor = $event->{anchor})) {
        $self->anchors->{ $anchor } = { data => $ref->{data} };
    }
}

sub mapping_end_event {
    my ($self, $event) = @_;
    my $stack = $self->stack;

    my $last = pop @$stack;
    my ($ref, $data) = @{ $last }{qw/ ref data /};
    $last->{type} eq 'mapping' or die "Expected mapping, but got $last->{type}";

    my @merge_keys;
    my @ref;
    for (my $i = 0; $i < @$ref; $i += 2) {
        my $key = $ref->[ $i ];
        if (ref $key eq 'YAML::PP::Type::MergeKey') {
            my $merge = $ref->[ $i + 1 ];
            if ((reftype($merge) || '') eq 'HASH') {
                push @merge_keys, $merge;
            }
            elsif ((reftype($merge) || '') eq 'ARRAY') {
                for my $item (@$merge) {
                    if ((reftype($item) || '') eq 'HASH') {
                        push @merge_keys, $item;
                    }
                    else {
                        die "Expected hash for merge key";
                    }
                }
            }
            else {
                die "Expected hash or array for merge key";
            }
        }
        else {
            push @ref, $key, $ref->[ $i + 1 ];
        }
    }
    for my $merge (@merge_keys) {
        for my $key (keys %$merge) {
            unless (exists $$data->{ $key }) {
                $$data->{ $key } = $merge->{ $key };
            }
        }
    }
    my $on_data = $last->{on_data} || sub {
        my ($self, $hash, $items) = @_;
        for (my $i = 0; $i < @$items; $i += 2) {
            my ($key, $value) = @$items[ $i, $i + 1 ];
            $key = '' unless defined $key;
            if (ref $key) {
                $key = $self->stringify_complex($key);
            }
            $$hash->{ $key } = $value;
        }
    };
    $on_data->($self, $data, \@ref);
    push @{ $stack->[-1]->{ref} }, $$data;
    if (defined(my $anchor = $last->{event}->{anchor})) {
        $self->anchors->{ $anchor }->{finished} = 1;
    }
    return;
}

sub sequence_start_event {
    my ($self, $event) = @_;
    my ($data, $on_data) = $self->schema->create_sequence($self, $event);
    my $ref = {
        type => 'sequence',
        ref => [],
        data => \$data,
        event => $event,
        on_data => $on_data,
    };
    my $stack = $self->stack;

    my $preserve_style = $self->preserve_flow_style;
    if ($preserve_style and not tied(@$data)) {
        tie @$data, 'YAML::PP::Preserve::Array', @$data;
        my $t = tied @$data;
        $t->{style} = $event->{style};
    }

    push @$stack, $ref;
    if (defined(my $anchor = $event->{anchor})) {
        $self->anchors->{ $anchor } = { data => $ref->{data} };
    }
}

sub sequence_end_event {
    my ($self, $event) = @_;
    my $stack = $self->stack;
    my $last = pop @$stack;
    $last->{type} eq 'sequence' or die "Expected mapping, but got $last->{type}";
    my ($ref, $data) = @{ $last }{qw/ ref data /};

    my $on_data = $last->{on_data} || sub {
        my ($self, $array, $items) = @_;
        push @$$array, @$items;
    };
    $on_data->($self, $data, $ref);
    push @{ $stack->[-1]->{ref} }, $$data;
    if (defined(my $anchor = $last->{event}->{anchor})) {
        my $test = $self->anchors->{ $anchor };
        $self->anchors->{ $anchor }->{finished} = 1;
    }
    return;
}

sub stream_start_event {}

sub stream_end_event {}

sub scalar_event {
    my ($self, $event) = @_;
    DEBUG and warn "CONTENT $event->{value} ($event->{style})\n";
    my $value = $self->schema->load_scalar($self, $event);
    if (defined (my $name = $event->{anchor})) {
        $self->anchors->{ $name } = { data => \$value, finished => 1 };
    }
    my $last = $self->stack->[-1];
    if ($self->preserve_scalar_style and not ref $value) {
        $value = YAML::PP::Preserve::Scalar->new(
            value => $value,
            style => $event->{style},
            tag => $event->{tag},
        );
    }
    push @{ $last->{ref} }, $value;
}

sub alias_event {
    my ($self, $event) = @_;
    my $value;
    my $name = $event->{value};
    if (my $anchor = $self->anchors->{ $name }) {
        # We know this is a cyclic ref since the node hasn't
        # been constructed completely yet
        unless ($anchor->{finished} ) {
            my $cyclic_refs = $self->cyclic_refs;
            if ($cyclic_refs ne 'allow') {
                if ($cyclic_refs eq 'fatal') {
                    die "Found cyclic ref";
                }
                if ($cyclic_refs eq 'warn') {
                    $anchor = { data => \undef };
                    warn "Found cyclic ref";
                }
                elsif ($cyclic_refs eq 'ignore') {
                    $anchor = { data => \undef };
                }
            }
        }
        $value = $anchor->{data};
    }
    my $last = $self->stack->[-1];
    push @{ $last->{ref} }, $$value;
}

sub stringify_complex {
    my ($self, $data) = @_;
    return $data if (ref $data eq 'YAML::PP::Preserve::Scalar' and $self->preserve_scalar_style);
    require Data::Dumper;
    local $Data::Dumper::Quotekeys = 0;
    local $Data::Dumper::Terse = 1;
    local $Data::Dumper::Indent = 0;
    local $Data::Dumper::Useqq = 0;
    local $Data::Dumper::Sortkeys = 1;
    my $string = Data::Dumper->Dump([$data], ['data']);
    $string =~ s/^\$data = //;
    return $string;
}

1;

__END__

=pod

=encoding utf-8

=head1 NAME

YAML::PP::Constructor - Constructing data structure from parsing events

=head1 METHODS

=over

=item new

The Constructor constructor

    my $constructor = YAML::PP::Constructor->new(
        schema => $schema,
        cyclic_refs => $cyclic_refs,
    );

=item init

Resets any data being used during construction.

    $constructor->init;

=item document_start_event, document_end_event, mapping_start_event, mapping_end_event, sequence_start_event, sequence_end_event, scalar_event, alias_event, stream_start_event, stream_end_event

These methods are called from L<YAML::PP::Parser>:

    $constructor->document_start_event($event);

=item anchors, set_anchors

Helper for storing anchors during construction

=item docs, set_docs

Helper for storing resulting documents during construction

=item stack, set_stack

Helper for storing data during construction

=item cyclic_refs, set_cyclic_refs

Option for controlling the behaviour when finding circular references

=item schema, set_schema

Holds a L<YAML::PP::Schema> object

=item stringify_complex

When constructing a hash and getting a non-scalar key, this method is
used to stringify the key.

It uses a terse Data::Dumper output. Other modules, like L<YAML::XS>, use
the default stringification, C<ARRAY(0x55617c0c7398)> for example.

=back

=cut
