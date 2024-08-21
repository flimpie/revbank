package SpaceTab::Cart;

use v5.32;
use warnings;
use experimental 'signatures';  # stable since v5.36

use Carp ();
use List::Util ();
use SpaceTab::Global;
use SpaceTab::Users;
use SpaceTab::FileIO;
use SpaceTab::Cart::Entry;

{
    package SpaceTab::Cart::CheckoutProhibited;
    sub new($class, $reason) { return bless \$reason, $class; }
    sub reason($self) { return $$self; }
}

sub new($class) {
    return bless { entries => [] }, $class;
}

sub add_entry($self, $entry) {
    SpaceTab::Plugins::call_hooks("add_entry", $self, $entry);

    push @{ $self->{entries} }, $entry;
    $self->{changed}++;
    $self->select($entry);

    SpaceTab::Plugins::call_hooks("added_entry", $self, $entry);

    return $entry;
}

sub add($self, $amount, $description, $data = {}) {
    ref $data or Carp::croak "Non-hash data argument";

    return $self->add_entry(SpaceTab::Cart::Entry->new($amount, $description, $data));
}

sub select($self, $entry) {
    return $self->{selected_entry} = $entry;
}

sub selected($self) {
    return undef if not @{ $self->{entries} };

    for my $entry (@{ $self->{entries} }) {
        return $entry if $entry == $self->{selected_entry};
    }

    return $self->select( $self->{entries}->[-1] );
}

sub delete($self, $entry) {
    my $entries = $self->{entries};

    my $oldnum = @$entries;
    @$entries = grep $_ != $entry, @$entries;
    $self->{changed}++;

    return $oldnum - @$entries;
}

sub empty($self) {
    $self->{entries} = [];
    $self->{changed}++;
}

sub display($self, $prefix = "") {
    say "$prefix$_" for map $_->as_printable, @{ $self->{entries} };
}

sub size($self) {
    return scalar @{ $self->{entries} };
}

sub prohibit_checkout($self, $bool, $reason) {
    if ($bool) {
        $self->{prohibited} = $reason;
    } else {
        delete $self->{prohibited};
    }
}

sub checkout($self, $user) {
    if ($self->{prohibited}) {
        die SpaceTab::Cart::CheckoutProhibited->new(
            "Cannot complete transaction: $self->{prohibited}"
        );
    }

    if ($self->entries('refuse_checkout')) {
        $self->display;
        die "Refusing to finalize deficient transaction";
    }

    $user = SpaceTab::Users::assert_user($user);

    my $entries = $self->{entries};

    for my $entry (@$entries) {
        $entry->sanity_check;
        $entry->user($user);
    }

    SpaceTab::FileIO::with_lock {
        my $fn = ".spacetab.nextid";
        my $transaction_id = eval { SpaceTab::FileIO::slurp($fn) };
        my $legacy_id = 0;

        if (defined $transaction_id) {
            chomp $transaction_id;
            if ($transaction_id eq "LEGACY") {
                $legacy_id = 1;
                $transaction_id = time() - 1300000000;;
            }
        } else {
            warn "Could not read $fn; using timestamp as first transaction ID.\n";
            $transaction_id = time() - 1300000000;
        }

        SpaceTab::Plugins::call_hooks("checkout_prepare", $self, $user, $transaction_id)
            or die "Refusing to finalize after failed checkout_prepare";

        for my $entry (@$entries) {
            $entry->sanity_check;
            $entry->user($user) if not $entry->user;
        }

        SpaceTab::FileIO::spurt($fn, ++(my $next_id = $transaction_id)) unless $legacy_id;

        SpaceTab::Plugins::call_hooks("checkout", $self, $user, $transaction_id);

        my %deltas = ($user => SpaceTab::Amount->new(0));

        for my $entry (@$entries) {
            $deltas{$_->{user}} += $_->{amount} * $entry->quantity
                for $entry, $entry->contras;
        }

        for my $account (reverse sort keys %deltas) {
            # The reverse sort is a lazy way to make the "-" accounts come last,
            # which looks nicer with the "cash" plugin.
            SpaceTab::Users::update($account, $deltas{$account}, $transaction_id)
                if $deltas{$account} != 0;
        }

        SpaceTab::Plugins::call_hooks("checkout_done", $self, $user, $transaction_id);

        sleep 1;  # look busy

        $self->empty;
    };
}

sub entries($self, $attribute = undef) {
    my @entries = @{ $self->{entries} };
    return grep $_->has_attribute($attribute), @entries if defined $attribute;
    return @entries;
}

sub changed($self, $keep = 0) {
    my $changed = 0;
    for my $entry ($self->entries('changed')) {
        $entry->attribute('changed', undef) unless $keep;
        $changed = 1;
    }
    $changed = 1 if $self->{changed};
    delete $self->{changed} unless $keep;

    return $changed;
}

sub sum($self) {
    return List::Util::sum(map $_->{amount} * $_->quantity, @{ $self->{entries} });
}

1;
