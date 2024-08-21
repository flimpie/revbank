use v5.32;
use warnings;

use Test::More;
use Test::Exception;
use Test::Warnings ":all";

require_ok('SpaceTab::Amount');

my $a = SpaceTab::Amount->new(123);

# Basic
isa_ok($a, "SpaceTab::Amount");
cmp_ok($a->cents, '==', 123);
cmp_ok($a->float, '==', 1.23);
is($a->string, "1.23");

# $ perl -le'printf "%.16f\n", 4.56'
# 4.5599999999999996
cmp_ok(SpaceTab::Amount->new(456)->cents, '==', 456);
cmp_ok(SpaceTab::Amount->parse_string("4.56")->cents, '==', 456);
cmp_ok(SpaceTab::Amount->parse_string("4,56")->cents, '==', 456);
cmp_ok(SpaceTab::Amount->new_from_float(4.56)->cents, '==', 456);

cmp_ok(SpaceTab::Amount->new(-456)->cents, '==', -456);
cmp_ok(SpaceTab::Amount->parse_string("-4.56")->cents, '==', -456);
cmp_ok(SpaceTab::Amount->parse_string("-4,56")->cents, '==', -456);
cmp_ok(SpaceTab::Amount->new_from_float(-4.56)->cents, '==', -456);
cmp_ok(SpaceTab::Amount->new(-456)->string, 'eq', "-4.56");

cmp_ok(SpaceTab::Amount->parse_string(".5")->cents, '==', 50);
cmp_ok(SpaceTab::Amount->parse_string("-.5")->cents, '==', -50);
cmp_ok(SpaceTab::Amount->parse_string("4.5")->cents, '==', 450);
cmp_ok(SpaceTab::Amount->parse_string("4,5")->cents, '==', 450);
cmp_ok(SpaceTab::Amount->parse_string("4")->cents, '==', 400);
cmp_ok(SpaceTab::Amount->parse_string("-4")->cents, '==', -400);
cmp_ok(SpaceTab::Amount->parse_string("+4")->cents, '==', 400);
cmp_ok(SpaceTab::Amount->parse_string(" 4")->cents, '==', 400);
cmp_ok(SpaceTab::Amount->parse_string("4 ")->cents, '==', 400);

cmp_ok(SpaceTab::Amount->new_from_float(.425)->cents, '==', 42);

# comparisons
ok($a);
ok(!SpaceTab::Amount->new(0));
cmp_ok($a, '==', 1.23);
cmp_ok($a, '<', 1.24);
cmp_ok($a, '>', 1.22);
cmp_ok($a, '>', 0.30);
cmp_ok($a, '<', 4.56);
cmp_ok($a, '<=', 1.23);
cmp_ok($a, '>=', 1.23);
cmp_ok($a, "eq", "1.23");
cmp_ok($a, 'lt', "1.24");
cmp_ok($a, 'gt', "1.22");
cmp_ok($a, 'le', "1.23");
cmp_ok($a, 'ge', "1.23");

# unary
is(+$a, "1.23");
is(-$a, "-1.23");

# ints/floats
is("" . $a * 4, "4.92");
is("" . 4 * $a, "4.92");
is("" .$a + 1.23, "2.46");
is("" . 1.23 + $a, "2.46");
is("" . $a - 1, "0.23");
is("" . 1 - $a, "-0.23");
is("" . $a + 1, "2.23");
is("" . 1 + $a, "2.23");
is("" . $a * 1.21, "1.48");
is("" . 1.21 * $a, "1.48");
is("" . $a * 1.219, "1.49");
is("" . 1.219 * $a, "1.49");
like(warning { is("" . $a / 2, "0.61") }, qr/float/);
like(warning { is("" . $a / 2.5, "0.49") }, qr/float/);
like(warning { "" . 1.5 / $a }, qr/float/);

# strings
is("" . $a * "4", "4.92");
is("" . "4" * $a, "4.92");
is("" . $a + "1.23", "2.46");
is("" . "1.23" + $a, "2.46");
is("" . $a - "1", "0.23");
is("" . "1" - $a, "-0.23");
is("" . $a + "1", "2.23");
is("" . "1" + $a, "2.23");
is("" . $a * "1.21", "1.48");
is("" . "1.21" * $a, "1.48");
is("" . $a * "1.219", "1.49");
is("" . "1.219" * $a, "1.49");
like(warning { is("" . $a / "2", "0.61") }, qr/float/);
like(warning { is("" . $a / "2.5", "0.49") }, qr/float/);

# other amounts
is("" . $a + $a, "2.46");
my $b = SpaceTab::Amount->new(.3 * 100);
cmp_ok($b, "<",  $a);
cmp_ok($b, "<=", $a);
cmp_ok($b, "lt", $a);
cmp_ok($b, "le", $a);
is("" . ($b *= 5), "1.50");
is("" . $b, "1.50");
is("" . $a + $b, "2.73");
is("" . $a - $b, "-0.27");
like(warning { is($a * $b, "1.84") }, qr/floating-point/);

# typical float example .3 - .2 - .1 != 0
is("" . SpaceTab::Amount->new_from_float(.3 - .2 - .1), "0.00");
#is("" . SpaceTab::Amount->new(30) - .2 - .1, "0.00");  # chained minus doesn't overload as expected
#is("" . SpaceTab::Amount->new(30) - "0.20" - "0.10", "0.00");
is("" . SpaceTab::Amount->new(30) - SpaceTab::Amount->new(20) - SpaceTab::Amount->new(10), "0.00");

is(
    ""
    . SpaceTab::Amount->parse_string("5.55")
    + SpaceTab::Amount->parse_string("18.65")
    - SpaceTab::Amount->parse_string("15")
    - SpaceTab::Amount->parse_string("5")
    - SpaceTab::Amount->parse_string("4.20"),
    "0.00"  # sprintf %.2f would result in "-0.00"
);

is(SpaceTab::Amount->parse_string("-0.00")->string, "0.00");
is(SpaceTab::Amount->parse_string("-0,00")->string, "0.00");
is(SpaceTab::Amount->parse_string("-0")->string, "0.00");
is(SpaceTab::Amount->parse_string("0.00")->string, "0.00");
is(SpaceTab::Amount->parse_string("0,00")->string, "0.00");
is(SpaceTab::Amount->parse_string("0")->string, "0.00");
is(SpaceTab::Amount->new_from_float(0)->string, "0.00");

like(warning { 1.5 / $a }, qr/float/);
like(warning { $a / $a }, qr/float/);
like(warning { rand $a }, qr/float/);

# Invalid amounts

is(SpaceTab::Amount->parse_string("0.000"), undef);
is(SpaceTab::Amount->parse_string("0.042"), undef);
is(SpaceTab::Amount->parse_string("+0.042"), undef);
is(SpaceTab::Amount->parse_string("-0.042"), undef);
is(SpaceTab::Amount->parse_string("0,000"), undef);
is(SpaceTab::Amount->parse_string("0,042"), undef);
is(SpaceTab::Amount->parse_string("+0,042"), undef);
is(SpaceTab::Amount->parse_string("-0,042"), undef);
is(SpaceTab::Amount->parse_string("foo"), undef);
is(SpaceTab::Amount->parse_string(""), undef);
is(SpaceTab::Amount->parse_string("."), undef);
is(SpaceTab::Amount->parse_string(","), undef);
is(SpaceTab::Amount->parse_string("--2"), undef);
is(SpaceTab::Amount->parse_string("+-2"), undef);
is(SpaceTab::Amount->parse_string("++2"), undef);
is(SpaceTab::Amount->parse_string("+ 2"), undef);
is(SpaceTab::Amount->parse_string("- 2"), undef);
is(SpaceTab::Amount->parse_string("2 .00"), undef);
dies_ok(sub { $a == 1.231 });
dies_ok(sub { $a > 1.231 });
dies_ok(sub { $a < 1.231 });
dies_ok(sub { $a - 1.231 });
dies_ok(sub { $a + 1.231 });
dies_ok(sub { $a eq "1.231" });
dies_ok(sub { $a gt "1.231" });
dies_ok(sub { $a lt "1.231" });

# Round tripping stringification
for (-5e99, -5e12, -1, -.99, 0, .99, 1, 5e12) {
    # -5e99 becomes -92233720368547760.08 which is great for this test :)
    my $a = SpaceTab::Amount->new_from_float($_);
    is($a->string, SpaceTab::Amount->parse_string($a->string)->string);
}

done_testing();
