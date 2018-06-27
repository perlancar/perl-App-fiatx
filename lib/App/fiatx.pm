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

our %arg_per_type = (
    per_type => {
        schema => 'bool*',
    },
);

my $fnum8 = [number => {precision=>8}];

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

    my $bres = Finance::Currency::FiatX::get_spot_rate(
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
        %arg_per_type,
    },
};
sub all_spot_rates {
    my %args = @_;

    my $dbh = _connect(\%args);

    my $bres = Finance::Currency::FiatX::get_all_spot_rates(
        dbh => $dbh,

        _supply(\%args, \%Finance::Currency::FiatX::args_caching),
        _supply(\%args, \%Finance::Currency::FiatX::arg_req0_source),
    );
    return $bres unless $bres->[0] == 200 || $bres->[0] == 304;

    my @rows;
    my $resmeta = {};

    if ($args{per_type}) {
        for (@{ $bres->[2] }) {
            delete $_->{source};
            push @rows, $_;
        }
        $resmeta->{'table.fields'}        = ['pair', 'type' , 'rate' , 'note'];
        $resmeta->{'table.field_formats'} = [undef , undef  , $fnum8 , undef ];
        $resmeta->{'table.field_aligns'}  = ['left', 'right', 'right', 'left'];
    } else {
        my %per_pair_rates;
        for my $r (@{ $bres->[2] }) {
            $per_pair_rates{ $r->{pair} } //= {
                pair => $r->{pair},
                mtime => 0,
            };
            next unless $r->{type} =~ /^(buy|sell)/;
            $per_pair_rates{ $r->{pair} }{ $r->{type} } = $r->{rate};
            $per_pair_rates{ $r->{pair} }{mtime} = $r->{mtime}
                if $per_pair_rates{ $r->{pair} }{mtime} < $r->{mtime};
        }
        for my $pair (sort keys %per_pair_rates) {
            push @rows, $per_pair_rates{$pair};
        }
        $resmeta->{'table.fields'}        = ['pair', 'buy'  , 'sell' , 'mtime'           ];
        $resmeta->{'table.field_formats'} = [undef , $fnum8 , $fnum8 , 'iso8601_datetime'];
        $resmeta->{'table.field_aligns'}  = ['left', 'right', 'right', 'left'];
        $resmeta->{'table.field_align_code'}  = sub { $_[0] =~ /^(buy|sell)/ ? 'right' : undef },
        $resmeta->{'table.field_format_code'} = sub { $_[0] =~ /^(buy|sell)/ ? $fnum8  : undef },
    }

    [200, "OK", \@rows, $resmeta];
}

1;
# ABSTRACT:

=head1 SYNOPSIS

See the included script L<fiatx>.


=head1 SEE ALSO

L<Finance::Currency::FiatX>
