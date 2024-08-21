package SpaceTab::Cart::Entry;

use v5.32;
use warnings;
use experimental 'signatures';  # stable since v5.36

use Carp qw(carp croak);
use SpaceTab::Users;
use List::Util ();
use Scalar::Util ();

# Workaround for @_ in signatured subs being experimental and controversial
my $NONE = \do { my $dummy };
sub _arg_provided($a) {
    return 1 if not ref $a;
    return Scalar::Util::refaddr($a) != Scalar::Util::refaddr($NONE) 
}

sub new($class, $amount, $description, $attributes = {}) {
    $amount = SpaceTab::Amount->parse_string($amount) if not ref $amount;

    my $self = {
        quantity    => 1,
        amount      => $amount,  # negative = pay, positive = add money
        description => $description,
        attributes  => { %$attributes },
        user        => undef,
        contras     => [],
        caller      => List::Util::first(sub { !/^SpaceTab::Cart/ }, map { (caller $_)[3] } 1..10)
                       || (caller 1)[3],
        highlight   => 1,
    };

    return bless $self, $class;
}

sub add_contra($self, $user, $amount, $description, $display = undef) {
    # $display should be given for either ALL or NONE of the contras,
    # with the exception of contras with $amount == 0.00;

    $amount = SpaceTab::Amount->parse_string($amount) if not ref $amount;
    $user = SpaceTab::Users::assert_user($user);

    $description =~ s/\$you/$self->{user}/g if defined $self->{user};

    push @{ $self->{contras} }, {
        user        => $user,
        amount      => $amount,  # should usually have opposite sign (+/-)
        description => $description,  # contra user's perspective
        display     => $display,  # interactive user's perspective
        highlight   => 1,
    };

    $self->attribute('changed', 1);

    return $self;  # for method chaining
}

sub has_attribute($self, $key) {
    return (
        exists      $self->{attributes}->{$key}
        and defined $self->{attributes}->{$key}
    );
}

sub attribute($self, $key, $new = $NONE) {
    my $ref = \$self->{attributes}->{$key};
    $$ref = $new if _arg_provided($new);
    return $$ref;
}

sub amount($self, $new = undef) {
    my $ref = \$self->{amount};
    if (defined $new) {
        $new = SpaceTab::Amount->parse_string($new) if not ref $new;
        $$ref = $new;
        $self->attribute('changed', 1);
        $self->{highlight_amount} = 1;
    }

    return $$ref;
}

sub quantity($self, $new = undef) {
    my $ref = \$self->{quantity};
    if (defined $new) {
        $new >= 0 or croak "Quantity must be positive";
        $$ref = $new;
        $self->attribute('changed', 1);
        $self->{highlight_quantity} = 1;
    }

    return $$ref;
}

sub multiplied($self) {
    return $self->{quantity} != 1;
}

sub contras($self) {
    # Shallow copy suffices for now, because there is no depth.
    return map +{ %$_ }, @{ $self->{contras} };
}

sub delete_contras($self) {
    $self->{contras} = [];
}

my $HI = "\e[37;1m";
my $LO = "\e[2m";
my $END = "\e[0m";

sub as_printable($self) {
    my @s;

    # Normally, the implied sign is "+", and an "-" is only added for negative
    # numbers. Here, the implied sign is "-", and a "+" is only added for
    # positive numbers.
    my $q = $self->{quantity};
    push @s, sprintf "%s%-4s%s" . "%s%8s%s" . " " . "%s%s%s", 
        ($self->{highlight} || $self->{highlight_quantity} ? $HI : $LO),
        ($q > 1 || $self->{highlight_quantity} ? "${q}x" : ""),
        ($self->{highlight} ? "" : $END),

        ($self->{highlight} || $self->{highlight_amount} ? $HI : $LO),
        $self->{amount}->string_flipped,
        ($self->{highlight} ? "" : $END),

        ($self->{highlight} ? $HI : $LO),
        $self->{description},
        $END;

    for my $c (@{ $self->{contras} }) {
        my $description;
        my $amount = $self->{amount};
        my $hidden = SpaceTab::Users::is_hidden($c->{user});
        my $fromto = $c->{amount}->cents < 0 ? "<-" : "->";
        $fromto .= " $c->{user}";

        if ($c->{display}) {
            $description =
                $hidden
                ? ($ENV{SPACETAB_DEBUG} ? "($fromto:) $c->{display}" : $c->{display})
                : "$fromto: $c->{display}";

            $amount *= -1;
        } elsif ($hidden) {
            next unless $ENV{SPACETAB_DEBUG};
            $description = "($fromto: $c->{description})";
        } else {
            $description = $fromto;
        }
        push @s, sprintf(
            "%s%15s %s%s",
            ($self->{highlight} || $c->{highlight} ? $HI : $LO),
            ($self->{amount} > 0 ? $c->{amount}->string_flipped("") : $c->{amount}->string),
            $description,
            $END,
        );
        delete $c->{highlight};
    }
    delete $self->@{qw(highlight highlight_quantity highlight_amount)};

    return @s;
}

sub as_loggable($self) {
    croak "Loggable called before set_user" if not defined $self->{user};

    my $quantity = $self->{quantity};

    my @s;
    for ($self, @{ $self->{contras} }) {
        my $total = $quantity * $_->{amount};

        my $description =
            $quantity == 1
            ? $_->{description}
            : sprintf("%s [%sx %s]", $_->{description}, $quantity, $_->{amount}->abs);

        push @s, sprintf(
            "%-12s %4s %3d %6s  # %s",
            $_->{user},
            ($total->cents > 0 ? 'GAIN' : $total->cents < 0 ? 'LOSE' : '===='),
            $quantity,
            $total->abs,
            $description
        );
    }

    return @s;
}

sub user($self, $new = undef) {
    if (defined $new) {
        croak "User can only be set once" if defined $self->{user};

        $self->{user} = $new;
        $_->{description} =~ s/\$you/$new/g for $self, @{ $self->{contras} };
    }

    return $self->{user};
}

sub sanity_check($self) {
    # Turnover and journals were implicit contras in previous versions of
    # spacetab, but old plugins may need upgrading to the new dual-entry system,
    # so (for now) a zero sum is not required.

    my @contras = $self->contras;

    my $sum = SpaceTab::Amount->new(
        List::Util::sum(map $_->{amount}->cents, $self, @contras)
    );

    # Although unbalanced transactiens are still allowed, a transaction with
    # contras should at least not try to issue money that does not exist.
    if ($sum > 0 and @contras and not $self->{FORCE_UNBALANCED}) {
        local $ENV{SPACETAB_DEBUG} = 1;
        my $message = join("\n",
            "BUG! (probably in $self->{caller})",
            "This adds up to creating money that does not exist:",
            $self->as_printable,
            (
                $sum == 2 * $self->{amount}
                ? "Hint for the developer: contras for positive value should be negative values and vice versa."
                : ()
            ),
            "Cowardly refusing to create $sum out of thin air"
        );
        SpaceTab::Plugins::call_hooks("log_error", "UNBALANCED ENTRY $message");
        croak $message;
    }

    if ($sum != 0) {
        local $ENV{SPACETAB_DEBUG} = 1;
        my $forced = $self->{FORCE_UNBALANCED} ? " (FORCED)" : "";
        SpaceTab::Plugins::call_hooks(
            "log_warning",
            "UNBALANCED ENTRY$forced in $self->{caller}: " . (
                @contras
                ? "sum of entry with contras ($sum) != 0.00"
                : "transaction has no contras"
            ) . ". This will be a fatal error in a future version of SpaceTab.\n"
            . "The unbalanced entry is:\n" . join("\n", $self->as_printable)
        );

        warn "$self->{caller} has created an unbalanced entry, which is deprecated. Support for unbalanced entries will be removed in a future version of SpaceTab.\n";
    }

    return 1;
}

1;
