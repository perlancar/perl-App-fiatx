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
        summary => 'Return one row of result per rate type',
        schema => 'bool*',
        description => <<'_',

This allow seeing notes and different mtime per rate type, which can be
different between different types of the same source.

_
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

my %arg_0_source = (
    source => {
        %{ $Finance::Currency::FiatX::arg_source{source} },
        pos => 0,
        default => ':all',
    },
);

my %arg_1_pair = (
    pair => {
        schema => 'currency::pair*',
        pos => 1,
    },
);

my %arg_2_type = (
    type => {
        %{ $Finance::Currency::FiatX::args_spot_rate{type} },
        pos => 2,
    },
);

$SPEC{spot_rates} = {
    v => 1.1,
    summary => 'Get spot (latest) rate(s) from a source',
    args => {
        %args_db,
        %Finance::Currency::FiatX::args_caching,
        %arg_0_source,
        %arg_1_pair,
        %arg_2_type,
        %arg_per_type,
    },
};
sub spot_rates {
    my %args = @_;

    my $source = $args{source};
    my $pair   = $args{pair};
    my $type   = $args{type};

    my ($from, $to); ($from, $to) = $pair =~ m!(.+)/(.+)! if $pair;

    my $dbh = _connect(\%args);

    my $rows0;

    if ($source ne ':all' && $pair && $type) {
        my $bres = Finance::Currency::FiatX::get_spot_rate(
            dbh => $dbh,
            max_age_cache => $args{max_age_cache},
            source        => $source,
            from          => $from,
            to            => $to,
            type          => $type,
        );
        return $bres unless $bres->[0] == 200 || $bres->[0] == 304;
        $rows0 = [$bres->[2]];
    } else {
        my $bres = Finance::Currency::FiatX::get_all_spot_rates(
            dbh => $dbh,
            max_age_cache => $args{max_age_cache},
            source        => $source,
        );
        return $bres unless $bres->[0] == 200 || $bres->[0] == 304;
        $rows0 = $bres->[2];
    }

    my @rows;
    my $resmeta = {};

    if ($args{per_type}) {
        for (@$rows0) {
            delete $_->{source} unless $source eq ':all';
            push @rows, $_;
        }
        $resmeta->{'table.fields'}        = ['source', 'pair', 'type' , 'rate' , 'note'];
        $resmeta->{'table.field_formats'} = [undef   , undef , undef  , $fnum8 , undef ];
        $resmeta->{'table.field_aligns'}  = ['left'  , 'left', 'right', 'right', 'left'];
        unless ($source eq ':all') {
            shift @{ $resmeta->{'table.fields'} };
            shift @{ $resmeta->{'table.field_formats'} };
            shift @{ $resmeta->{'table.field_aligns'} };
        }
    } else {
        my %sources;
        for my $r (@$rows0) {
            my $src = $r->{source} // '';
            $sources{ $src }++;
        }

        for my $src (sort keys %sources) {
            my %per_pair_rates;
            for my $r (@$rows0) {
                next unless ($r->{source} // '') eq $src;
                $per_pair_rates{ $r->{pair} } //= {
                    pair => $r->{pair},
                    mtime => 0,
                };
                $per_pair_rates{ $r->{pair} }{source} = $src
                    unless $source eq $src;
                next unless $r->{type} =~ /^(buy|sell)/;
                $per_pair_rates{ $r->{pair} }{ $r->{type} } = $r->{rate};
                $per_pair_rates{ $r->{pair} }{mtime} = $r->{mtime}
                    if $per_pair_rates{ $r->{pair} }{mtime} < $r->{mtime};
            }
            for my $pair (sort keys %per_pair_rates) {
                push @rows, $per_pair_rates{$pair};
            }
        }
        $resmeta->{'table.fields'}        = ['source', 'pair', 'buy'  , 'sell' , 'mtime'           ];
        $resmeta->{'table.field_formats'} = [undef   , undef , $fnum8 , $fnum8 , 'iso8601_datetime'];
        $resmeta->{'table.field_aligns'}  = ['left'  , 'left', 'right', 'right', 'left'];
        if ($source =~ /\A\w+\z/) {
            shift @{ $resmeta->{'table.fields'} };
            shift @{ $resmeta->{'table.field_formats'} };
            shift @{ $resmeta->{'table.field_aligns'} };
        }
        $resmeta->{'table.field_align_code'}  = sub { $_[0] =~ /^(buy|sell)/ ? 'right' : undef },
        $resmeta->{'table.field_format_code'} = sub { $_[0] =~ /^(buy|sell)/ ? $fnum8  : undef },
    }

  FILTER_ROWS:
    {
        my @rows_f;
        for (@rows) {
            next if $pair && $_->{pair} ne $pair;
            push @rows_f, $_;
        }
        @rows = @rows_f;
    }

    [200, "OK", \@rows, $resmeta];
}

1;
# ABSTRACT:

=head1 SYNOPSIS

See the included script L<fiatx>.


=head1 SEE ALSO

L<Finance::Currency::FiatX>
