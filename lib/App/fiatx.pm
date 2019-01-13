package App::fiatx;

# DATE
# VERSION

use 5.010001;
use strict;
use warnings;
use Log::ger;

use Finance::Currency::FiatX;

our %SPEC;

$SPEC{':package'} = {
    v => 1.1,
    summary => 'Fiat currency exchange rate tool',
};

our %args_db = (
    db_name => {
        schema => 'str*',
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

my %arg_sources = (
    sources => {
        'x.name.is_plural' => 1,
        'x.name.singular' => 'source',
        schema => ['array*', of=>['str*']],
        cmdline_aliases => {s=>{}},
    },
);

my %arg_type = (
    type => {
        schema => 'str*',
        cmdline_aliases => {t=>{}},
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

$SPEC{fiatx} = {
    v => 1.1,
    summary => 'Currency exchange rate tool',
    args => {
        %args_db,
        %Finance::Currency::FiatX::args_caching,
        %arg_sources,
        query => {
            schema => 'str*',
            pos => 0,
        },
        action => {
            schema => 'str*',
            default => 'get_spot_rates',
            cmdline_aliases => {
                l => {is_flag=>1, summary=>"Shortcut for --action=list_sources", code=>sub{ $_[0]{action} = 'list_sources' }},
            },
        },
        default_quote_currency => {
            schema => 'fiat_or_cryptocurrency*',
        },
    },
};
sub fiatx {
    my %args = @_;

    my $action = $args{action} // 'get_spot_rates';
    my $type = $args{type};

    if ($action eq 'list_sources') {
        return Finance::Currency::FiatX::list_rate_sources();
    }

    my $sources = $args{sources} // [];
    push @$sources, ':any' unless @$sources;
    {
        my $special;
        my $num_special = 0;
        my $num_regular = 0;
        for (@$sources) {
            if (/\Q:/) {
                $special //= $_; $num_special++;
            } else {
                $num_regular++;
            }
        }
        return [400, "Cannot mix special source '$special' with others"]
            if $num_special && @$sources > 1;
    }

    return [400, "Please specify db_name"] unless defined $args{db_name};
    my $dbh = _connect(\%args);

    if ($action eq 'get_spot_rates') {

        my $query = $args{query} // '';
        my @res;

        if ($query eq '') {
            # user requests all currency pairs
            for my $source (@$sources) {
                my $bres = Finance::Currency::FiatX::get_all_spot_rates(
                    dbh => $dbh,
                    max_age_cache => $args{max_age_cache},
                    source        => $source,
                );
                unless ($bres->[0] == 200) {
                    log_warn "Can't get spot rates from source '$source': $bres->[0] - $bres->[1]";
                    next;
                }
                push @res, @{ $bres->[2] };
            }
            log_warn "Can't get any rates" unless @res;
            return [200, "OK", \@res];
        }

        my ($from, $to);
        if ($query =~ m!\A(\w+)/(\w+)\z!) {
            # user specifies a currency pair e.g. "USD/IDR"
            ($from, $to) = ($1, $2);
        } elsif ($query =~ /\A\w+\z/) {
            # user specifies a base currency e.g. "USD"
            $from = $query;
            $to = $args{default_quote_currency}
                or return [400, "You specified '$query' but do not define default_quote_currency"];
        } else {
            return [400, "Invalid query, please specify currency code or pair"];
        }

        for my $source (@$sources) {
            my $bres = Finance::Currency::FiatX::get_spot_rate(
                dbh => $dbh,
                max_age_cache => $args{max_age_cache},
                source        => $source,
                from          => $from,
                to            => $to,
                type          => $type,
            );
            unless ($bres->[0] == 200) {
                log_warn "Can't get spot rates from source '$source': $bres->[0] - $bres->[1]";
                next;
            }

            push @res, $bres->[2];
        }
        log_warn "Can't get any rates" unless @res;
        return [200, "OK", \@res];

    } else {

        return [400, "Invalid action '$action'"];

    }
}

1;
# ABSTRACT:

=head1 SYNOPSIS

See the included script L<fiatx>.


=head1 SEE ALSO

L<Finance::Currency::FiatX>

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
