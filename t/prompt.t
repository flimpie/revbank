use v5.32;

use Test::More;
use Test::Exception;
use Test::Warnings ":all";

use experimental 'signatures';

BEGIN { use_ok('SpaceTab::Prompt'); }

sub are($input, $expected) {
	if (ref($expected) eq 'ARRAY') {
		my @got = SpaceTab::Prompt::split_input($input);
		is_deeply(\@got, $expected, ">$input<");

		my $reconstructed = join " ", map SpaceTab::Prompt::reconstruct($_), @got;
		my @got2 = SpaceTab::Prompt::split_input($reconstructed);
		is_deeply(\@got, \@got2, ">$input< round-trips once");

		my $reconstructed2 = join " ", map SpaceTab::Prompt::reconstruct($_), @got2;
		my @got3 = SpaceTab::Prompt::split_input($reconstructed2);
		is_deeply(\@got, \@got3, ">$input< round-trips twice");
	} else {
		my @got = SpaceTab::Prompt::split_input($input);
		is(scalar @got, 1, "Invalid input >$input< returns 1 element");
		is(${ $got[0] }, $expected, "Invalid input >$input< fails at $expected");
	}
}

are "foo",   [qw/foo/];
are " foo ", [qw/foo/];
are "'foo'", [qw/foo/];
are '"foo"', [qw/foo/];

are "foo bar",           [qw/foo bar/];
are "foo bar baz",       [qw/foo bar baz/];
are "'foo' 'bar' \"baz\"", [qw/foo bar baz/];

are "foo;bar",   ['foo', "\0SEPARATOR", 'bar'];
are "foo ;bar",  ['foo', "\0SEPARATOR", 'bar'];
are "foo; bar",  ['foo', "\0SEPARATOR", 'bar'];
are "foo ; bar", ['foo', "\0SEPARATOR", 'bar'];

are "'foo';bar",   ['foo', "\0SEPARATOR", 'bar'];
are "'foo' ;bar",  ['foo', "\0SEPARATOR", 'bar'];
are "'foo'; bar",  ['foo', "\0SEPARATOR", 'bar'];
are "'foo' ; bar", ['foo', "\0SEPARATOR", 'bar'];

are "foo;'bar'",   ['foo', "\0SEPARATOR", 'bar'];
are "foo ;'bar'",  ['foo', "\0SEPARATOR", 'bar'];
are "foo; 'bar'",  ['foo', "\0SEPARATOR", 'bar'];
are "foo ; 'bar'", ['foo', "\0SEPARATOR", 'bar'];

are "foo\\;bar",   [qw/foo;bar/];
are "foo \\;bar",  [qw/foo ;bar/];
are "foo\\; bar",  [qw/foo; bar/];
are "foo \\; bar", [qw/foo ; bar/];

are "foo\\0bar", ["foo\0bar"];
are "foo\\abar", ["foo\abar"];
are "foo\\rbar", ["foo\rbar"];
are "foo\\nbar", ["foo\nbar"];
are "foo\\tbar", ["foo\tbar"];
are "foo\\'bar", ["foo'bar"];
are 'foo\\"bar', ["foo\"bar"];
are 'foo\\\\bar', ["foo\\bar"];
are 'foo\\\\\\\\bar', ["foo\\\\bar"];

are "abort", ["\0ABORT"];
are "'abort'", [qw/abort/];
are '"abort"', [qw/abort/];

are "\\", 0;
are "'foo", 0;

#    0123
are "foo'", 3;
#    0123
are "foo'bar", 3;

#    01234
are "bar 'foo", 4;
#    01234567
are "bar foo'", 7;
#    01234567
are "bar foo'bar", 7;

#    0123456789
are "foo 'bar'\"baz\"", 9;

done_testing;
