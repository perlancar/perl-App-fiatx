package App::fiatx;

# DATE
# VERSION

use 5.010001;
use strict;
use warnings;

our %SPEC;

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

our %args_convert = (
    amount => {
        schema => 'num*',
        default => 1,
    },
    from => {
        schema => 'currency::code*',
        req => 1,
    },
    to => {
        schema => 'currency::code*',
        req => 1,
    },
    type => {
        summary => 'Which rate is wanted? e.g. sell, buy',
        schema => 'str*',
        default => 'sell', # because we want to buy
    },
);

our %args_caching = (
    max_age_cache => {
        summary => 'Above this age (in seconds), '.
            'we retrieve rate from remote source again',
        schema => 'posint*',
        default => 4*3600,
        cmdline_aliases => {
            no_cache => {is_flag=>1, code=>sub {$_[0]{max_age_cache} = 0}, summary=>'Alias for --max-age-cache=0'},
        },
    },
    max_age_current => {
        summary => 'Above this age (in seconds), '.
            'we no longer consider the rate to be "current" but "historical"',
        schema => 'posint*',
        default => 24*3600,
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

$SPEC{convert} = {
    v => 1.1,
    summary => 'Convert two currencies using current rate',
    args => {
        %args_db,
        %args_caching,
        %args_convert,
    },
};
sub convert {
    require Finance::Currency::FiatX;

    my %args = @_;

    my $dbh = _connect(\%args);

    Finance::Currency::FiatX::convert_fiat_currency(
        dbh => $dbh,

        _supply(\%args, \%args_caching),
        _supply(\%args, \%args_convert),
    );
}

1;
# ABSTRACT:

=head1 SYNOPSIS

See the included script L<fiatx>.


=head1 SEE ALSO

L<Finance::Currency::FiatX>
