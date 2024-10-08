package SpaceTab::Plugins;

use v5.32;
use warnings;
use experimental 'signatures';  # stable since v5.36

use SpaceTab::Eval;
use SpaceTab::Plugin;
use SpaceTab::Global;
use Exporter;
our @EXPORT = qw(call_hooks load_plugins);

my @plugins;

sub _read_file($fn) {
    local @ARGV = ($fn);
    readline *ARGV;
}

sub call_hooks {
    my $hook = shift;
    my $method = "hook_$hook";
    my $success = 1;

    for my $class (@plugins) {
         if ($class->can($method)) {
            my ($rv, @message) = eval { $class->$method(@_) };

            if ($@) {
                $success = 0;
                call_hooks("plugin_fail", $class->id, "$class->$method died: $@");
            } elsif (defined $rv and ref $rv) {
                main::abort(@message) if $rv == ABORT;

                $success = 0;
                call_hooks("plugin_fail", $class->id, "$class->$method returned an unsupported value");
            }
        }
    }

    return $success;
};

sub register(@new_plugins) {
    call_hooks("register", $_) for @new_plugins;
    push @plugins, @new_plugins;
}

sub load($class) {
    my @config = _read_file('data/plugins');
    chomp @config;
    s/#.*//g for @config;
    @config = map /(\S+)/, grep /\S/, @config;

    for my $name (@config) {
        my $fn = "plugins/$name";
        my $overlay_fn = "plugins/overlay/$name"; 
        # "overlaying" plugins to make developing/scratching/bodging easier

        my $package = "SpaceTab::Plugin::$name";
        if (not -e $overlay_fn) {
            if (not -e $fn) {
                warn "$fn does not exist; skipping plugin.\n";
                next;
            }
        } else {
            $fn = $overlay_fn;
        }
        SpaceTab::Eval::clean_eval(qq[
            use strict;
            use warnings;
            use v5.32;
            use experimental 'signatures';
            use experimental 'isa';
            package $package;
            BEGIN { SpaceTab::Global->import; }
            our \@ISA = qw(SpaceTab::Plugin);
            our \%ATTR;
            sub MODIFY_CODE_ATTRIBUTES(\$class, \$sub, \@attrs) {
                \$ATTR{ \$sub } = "\@attrs";
                return;
            }
            sub FETCH_CODE_ATTRIBUTES {
                return \$ATTR{ +pop };
            }
            sub HELP1 {
                \$::HELP1{ +shift } = +pop;
            }
            sub HELP {
                \$::HELP{ +shift } = +pop;
            }
            sub id { '$name' }
        ] . "\n#line 1 $fn\n" . join "", _read_file($fn));

        if ($@) {
            call_hooks("plugin_fail", $name, "Compile error: $@");
            next;
        }
        if (not $package->can("command")) {
            warn "Plugin $name does not have a 'command' method; skipping.\n";
            next;
        }

        register $package;
    }
}

sub new($class) {
    return map $_->new, @plugins;
}

1;
