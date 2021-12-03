package RevBank::Users;

use v5.28;
use warnings;
use feature qw(signatures);
no warnings qw(experimental::signatures);

use RevBank::Global;
use RevBank::Plugins;

my $filename = "revbank.accounts";

sub _read() {
    my @users;
    open my $fh, $filename or die $!;
    /\S/ and push @users, [split " "] while readline $fh;
    close $fh;
    return { map { lc($_->[0]) => $_ } @users };
}

sub names() {
    return map $_->[0], values %{ _read() };
}

sub balance($username) {
    return _read()->{ lc $username }->[1];
}

sub since($username) {
    return _read()->{ lc $username }->[3];
}

sub create($username) {
    open my $fh, '>>', $filename or die $!;
    my $now = now();
    print {$fh} "$username 0.00 $now\n" or die $!;
    close $fh or die $!;
    RevBank::Plugins::call_hooks("user_created", $username);
}

sub update($username, $delta, $transaction_id) {
    open my $in,  'revbank.accounts' or die $!;
    open my $out, ">.revbank.$$" or die $!;
    my $old;
    my $new;
    while (defined (my $line = readline $in)) {
        my @a = split " ", $line;
        if (lc $a[0] eq lc $username) {
            $old = RevBank::Amount->parse_string($a[1]);
            die "Fatal error: invalid balance in revbank:accounts:$.\n"
                if not defined $old;

            $new = $old + $delta;

            my $since = $a[3] // "";

            my $newc = $new->cents;
            my $oldc = $old->cents;
            $since = "+\@" . now() if $newc  > 0 and (!$since or $oldc <= 0);
            $since = "-\@" . now() if $newc  < 0 and (!$since or $oldc >= 0);
            $since = "0\@" . now() if $newc == 0 and (!$since or $oldc != 0);

            printf {$out} "%-16s %9s %s %s\n", (
                $username, $new->string("+"), now(), $since
            ) or die $!;
        } else {
            print {$out} $line or die $!;
        }
    }
    close $out or die $!;
    close $in;
    rename ".revbank.$$", "revbank.accounts" or die $!;

    RevBank::Plugins::call_hooks(
        "user_balance", $username, $old, $delta, $new, $transaction_id
    );
}

sub parse_user($username) {
    my $users = _read();
    return undef if not exists $users->{ lc $username };
    return $users->{ lc $username }->[0];
}

1;


