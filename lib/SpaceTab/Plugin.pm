package SpaceTab::Plugin;

use v5.32;
use warnings;
use experimental 'signatures';  # stable since v5.36
use attributes;

require SpaceTab::Global;

sub new($class) {
    return bless { }, $class;
}

sub command($self, $cart, $command, @) {
    return SpaceTab::Global::NEXT();
}

sub Tab($self, $method) {
    my %completions;

    my $attr = attributes::get(
        ref $method ? $method : $self->can($method)
    ) or return;

    my ($tab) = $attr =~ /Tab \( (.*?) \)/x or return;
    for my $keyword (split /\s*,\s*/, $tab) {
        if ($keyword =~ /^&(.*)/) {
            my $method = $1;
            @completions{ $self->$method } = ();
        } else {
            $completions{ $keyword }++;
        }
    }

    if (delete $completions{USERS}) {
        for my $name (SpaceTab::Users::names()) {
            next if SpaceTab::Users::is_hidden($name);

            $completions{ $name }++;
            $completions{ $1 }++ if $name =~ /^\*(.*)/;
        }
    }

    return keys %completions;
}

sub AllChars($self, $method) {
    my $attr = attributes::get(
        ref $method ? $method : $self->can($method)
    ) or return;

    return !!($attr =~ /AllChars/);
}

1;

__END__

=head1 NAME

SpaceTab::Plugin - Base class for RevBank plugins

=head1 DESCRIPTION

Documentation on writing plugins is at L<SpaceTab::Plugins>.
