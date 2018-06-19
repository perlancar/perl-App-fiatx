package App::fiatx;

# DATE
# VERSION

use 5.010001;
use strict;
use warnings;

use Finance::Currency::FiatX;

our %SPEC;

$SPEC{':package'} = {
    v => 1.1,
    summary => 'Fiat currency exchange rate tool',
};

our %args_db = (
    db_name => {
        schema => 'str*',
        req => 1,
        tags => ['category:database-connection'],
    },
    # XXX db_host
    # XXX db_port
    db_username => {
        schema => 'str*',
        tags => ['category:database-connection'],
    },
    db_password => {
        schema => 'str*',
        tags => ['category:database-connection'],
    },
);

sub _connect {
    my $args = shift;

    require DBIx::Connect::MySQL;
    DBIx::Connect::MySQL->connect(
        "dbi:mysql:database=$args->{db_name}",
        $args->{db_username},
        $args->{db_password},
        {RaiseError=>1},
    );
}

sub _supply {
    my ($args, $args_spec) = @_;

    my %res;
    for (keys %$args_spec) {
        if (exists $args->{$_}) {
            $res{$_} = $args->{$_};
        }
    }
    %res;
}

$SPEC{sources} = {
    v => 1.1,
    summary => 'List available sources',
    args => {
    },
};
sub sources {
    require PERLANCAR::Module::List;

    my @res;
    my $mods = PERLANCAR::Module::List::list_modules(
        'Finance::Currency::FiatX::Source::', {list_modules=>1});
    unless (keys %$mods) {
        return [412, "No source modules available"];
    }
    for my $src (sort keys %$mods) {
        $src =~ s/^Finance::Currency::FiatX::Source:://;
        push @res, $src;
    }

    [200, "OK", \@res];
}

$SPEC{spot_rate} = {
    v => 1.1,
    summary => 'Get spot (latest) rate',
    args => {
        %args_db,
        %Finance::Currency::FiatX::args_caching,
        %Finance::Currency::FiatX::args_spot_rate,
    },
};
sub spot_rate {
    my %args = @_;

    my $dbh = _connect(\%args);

    Finance::Currency::FiatX::get_spot_rate(
        dbh => $dbh,

        _supply(\%args, \%Finance::Currency::FiatX::args_caching),
        _supply(\%args, \%Finance::Currency::FiatX::args_spot_rate),
    );
}

$SPEC{all_spot_rates} = {
    v => 1.1,
    summary => 'Get all spot (latest) rates from a source',
    args => {
        %args_db,
        %Finance::Currency::FiatX::args_caching,
        %Finance::Currency::FiatX::arg_req0_source,
    },
};
sub all_spot_rates {
    my %args = @_;

    my $dbh = _connect(\%args);

    Finance::Currency::FiatX::get_all_spot_rates(
        dbh => $dbh,

        _supply(\%args, \%Finance::Currency::FiatX::args_caching),
        _supply(\%args, \%Finance::Currency::FiatX::arg_req0_source),
    );
}

1;
# ABSTRACT:

=head1 SYNOPSIS

See the included script L<fiatx>.


=head1 SEE ALSO

L<Finance::Currency::FiatX>
