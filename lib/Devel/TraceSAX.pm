package Devel::TraceSAX;

=head1 NAME

Devel::TraceSAX - Trace SAX events

=head1 SYNOPSIS

  ## From the command line:
    perl -d:TraceSAX           script.pl
    perl -d:TraceSAX=-dump_all script.pl

  ## procedural:
    use Devel::TraceSAX;

    trace_SAX $obj1;

=head1 DESCRIPTION

B<WARNING>: alpha code alert!!! This module and its API subject to change,
possibly radically :).

Traces SAX events in a program.  Works by applying Devel::TraceCalls to
a tracer on the desired classes for all known SAX event types (according to
XML::SAX::EventMethodMaker and XML::SAX::Machines).

=cut

$VERSION=0.01;

@EXPORT = qw( trace_SAX );
%EXPORT_TAGS = ( all => \@EXPORT_OK );

## TODO: Can't recall why this class isn't an exporter, need to try that.
@ISA = qw( Devel::TraceCalls );

use strict;
use Devel::TraceCalls qw( trace_calls );
use XML::SAX::EventMethodMaker qw( sax_event_names );
use UNIVERSAL;
use Exporter;

use vars qw( @methods );

@methods = (
    qw(
        set_handler
        set_handlers
        start_manifold_document
        end_manifold_document
    ),
    sax_event_names "Handler", "ParseMethods"
);

##
## WARNING: UGLY CODE AHEAD. I'm still debugging this.
##

## Note that we ignore some common words in methods.
my @scan_methods = grep !/set_handler|warning|error|parse/, sort @methods;
my $methods = join "|", map quotemeta, @scan_methods;
$methods = qr/^(?:$methods)(?!\n)$/;

##
## -d:TraceSAX and -MDevel::TraceSAX support
##
my $always_dump;

sub import {
    my $self = shift;

    if ( ! (caller(0))[2] ) {
        require Devel::TraceSAX::DB;
        for ( @_ ) {
            if ( $_ eq "-dump_all" ) {
                $always_dump = 1;
            }
            else {
                warn "Devel::TraceSAX: unknown parameter '$_'\n";
            }
        }
        return;
    }

    my $meth = Exporter->can( "export_to_level" );
    $meth->( __PACKAGE__, 1, @_ );
}


## External API to add a SAX object instance
sub trace_SAX {
    my ( $processor, $id ) = @_;
warn $processor;
    trace_calls {
        Objects      => [ $processor ],
        ObjectId     => $id,
        Subs         => \@methods,
        LogFormatter => \&log_formatter,
    };
}


sub log_formatter {
    my ( $tp, $r, $params ) = @_;

#warn Data::Dumper::Dumper( $tp, $r );

    my $short_sub_name = $r->{Name};
    $short_sub_name =~ s/.*://;

    if ( ! $always_dump
        && ( my $meth = __PACKAGE__->can( "format_$short_sub_name" ) )
    ) {
        return $meth->( @_ );
    }
    else {
        return undef;
    }

    return "FOO\n";
}


##
## Parser formatters
##
my %builtin_types = map { ( $_ => undef ) } qw(
    SCALAR
    ARRAY
    Regexp
    REF
    HASH
    CODE
);

sub _stringify_blessed_refs {
    my $s = shift;
    my $type = ref $s;

    return $s if ! $type || $type eq "Regexp" ;

    if ( $type eq "HASH" ) {
        $s = {
            map {
                ( $_  => _stringify_blessed_refs( $s->{$_} ) );
            } keys %$s
        };
    }
    elsif ( $type eq "ARRAY" ) {
        $s = [ map _stringify_blessed_refs( $_ ), @$s ];
    }
    elsif( $type eq "Regexp" ) {
        $s = "$s";
    }
    elsif ( !exists $builtin_types{$type} ) {
        ## A blessed ref...
        $s = $type;
    }

    return $s;
}


sub format_set_handler {
    my ( $tp, $r, $params ) = @_;

    return {
        Args => [
        ],
    };
}


sub format_start_element {
    my ( $tp, $r, $params ) = @_;

    return undef if @$params != 2;
    my $elt = $params->[1];
    return undef if ! defined( $elt ) || ref $elt ne "HASH";

    for ( keys %$elt ) {
        next if $_ eq "Name"
            || $_ eq "LocalName"
            || $_ eq "Prefix"
            || $_ eq "Attributes";
        return undef if defined $elt->{$_};
    }

    return {
        Args => join( "",
            ": <",
            (
                (
                   defined $elt
                && ref $elt eq "HASH"
                && exists $elt->{Name}
                && defined $elt->{Name}
                )
                    ? ( defined $elt->{Name} ? $elt->{Name} : "???" )
                    : "???"
            ),
            exists $elt->{Attributes} && defined $elt->{Attributes}
                ? map {
                    ## TODO: escape the attr value
                    " " . $_ . "='" . $elt->{Attributes}->{$_}->{Value} . "'";
                } keys %{$elt->{Attributes}} 
                : (),
            ">"
        ),
    };
}


sub format_end_element {
    my ( $tp, $r, $params ) = @_;

    return undef if @$params != 2;
    my $elt = $params->[1];
    return undef if ! defined( $elt ) || ref $elt ne "HASH";

    for ( keys %$elt ) {
        next if $_ eq "Name"
            || $_ eq "LocalName"
            || $_ eq "Prefix"
            || $_ eq "Attributes";
        return undef if defined $elt->{$_};
    }

    return {
        Args => join( "",
            ": </",
            (
                (
                   defined $elt
                && ref $elt eq "HASH"
                && exists $elt->{Name}
                && defined $elt->{Name}
                )
                    ? ( defined $elt->{Name} ? $elt->{Name} : "???" )
                    : "???"
            ),
            ">"
        ),
    };
}


sub format_characters {
    my ( $tp, $r, $params ) = @_;

    return undef if @$params != 2;
    my $data = $params->[1];
    return undef if ! defined( $data ) || ref $data ne "HASH";
    return undef if ! exists $data->{Data} || ! defined $data->{Data};


    for ( keys %$data ) {
        next if $_ eq "Data";
        return undef;
    }

    $data = $data->{Data};

    $data =~ s/\010/\\b/g;
    $data =~ s/\n/\\n/g;
    $data =~ s/\r/\\r/g;
    $data =~ s/\r/\\e/g;
    $data =~ s/\f/\\f/g;
    $data =~ s/'/\\'/g;

    ## TODO: escape the data
    return { Args => ": '$data'\n" };
}


sub format_comment {
    my ( $tp, $r, $params ) = @_;

    return undef if @$params != 2;
    my $data = $params->[1];
    return undef if ! defined( $data ) || ref $data ne "HASH";
    return undef if ! exists $data->{Data} || ! defined $data->{Data};


    for ( keys %$data ) {
        next if $_ eq "Data";
        return undef;
    }

    $data = $data->{Data};

    $data =~ s/\010/\\b/g;
    $data =~ s/\n/\\n/g;
    $data =~ s/\r/\\r/g;
    $data =~ s/\r/\\e/g;
    $data =~ s/\f/\\f/g;
    $data =~ s/'/\\'/g;

    ## TODO: escape the data
    return { Args => ": <!--$data-->\n" };
}

sub format_parse {
    my ( $tp, $r, $params ) = @_;

    return undef if @$params != 2 || ref $params->[1] ne "HASH" ;

    return {
        Args => [
            $params->[0],
            _stringify_blessed_refs $params->[1],
        ]
    };
}

=head1 TODO

Add a lot more formatting clean-up.

=head1 LIMITATIONS

This module overloads CORE::GLOBAL::require when used from the command
line via -d: or -M.  For some reason this causes spurious warnings like

   Unquoted string "fields" may clash with future reserved word at /usr/local/lib/perl5/5.6.1/base.pm line 87.

That line looks like "require fields;", so it looks like the (*) prototype
on our CORE::GLOBAL::require = sub (*) {...} isn't having it's desired
effect.  It would be nice to clean these up.

=head1 AUTHOR

    Barrie Slaymaker <barries@slaysys.com>

=head1 LICENSE

You may use this under the terms of either the Artistic License or any
version of the BSD or GPL licenses :).

=cut

1;
