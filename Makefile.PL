use ExtUtils::MakeMaker;

WriteMakefile(
    NAME          => "Devel::TraceSAX",
    VERSION_FROM  => "lib/Devel/TraceSAX.pm",
    PREREQ_PM     => {
        "Devel::TraceCalls" => 0,
        ## Need XML::SAX::EventMethodMaker, want to tell the user
        ## the distro name (X::S::M) instead of the buried pkg name
        ## in case they're not running CPAN.pm
        "XML::SAX::Machines" => 0,
    },
);


sub MY::libscan {
    package MY;
    my $self = shift;
    my ( $path ) = @_;
    return '' if /\.sw[a-z]$/;
    return '' unless length $self->SUPER::libscan( $path );
    return $path;
}
