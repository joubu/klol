package Klol::Lxc::Templates;

use Klol::Config;

use Modern::Perl;
use List::Util qw[ first ];
use base qw[Class::Accessor];
__PACKAGE__->mk_accessors(qw[ config templates ] );

use overload '""' => \&str;

sub new {
    my ( $class ) = @_;
    my $config = Klol::Config->new();

    my $self = $class->SUPER::new( { config => $config, templates => [] });

    bless( $self, $class );
    $self->set('templates', $self->list);
    return $self;
}

sub list {
    my ( $self ) = @_;
    return $self->templates
        if scalar(@{$self->templates});
    my $templates = $self->config->{template}{availables};
    my $host = $self->config->{template}{server}{host};
    my $login = $self->config->{template}{server}{login};
    my $identity_file = $self->config->{template}{server}{identity_file};
    my $root_path = $self->config->{template}{server}{root_path};
    my @templates;
    my $i = 1;
    for my $template_name ( sort keys %$templates ) {
        my $template = $templates->{$template_name};
        $template->{name} = $template_name;
        $template->{id} = $i;
        $template->{host} = $host;
        $template->{login} = $login;
        $template->{identity_file} = $identity_file;
        $template->{root_path} = $root_path;
        push @templates, $template;
        $i++;
    }
    return \@templates;
}

sub get_template {
    my ( $self, $template_name ) = @_;
    return first {$_->{id} == int($template_name) } @{$self->templates}
        if $template_name =~ /^\d+$/;
    return first {$_->{name} eq $template_name } @{$self->templates};
}

sub str {
    my ( $self ) = @_;
    my @str;
    my @templates = @{$self->templates};
    my $login = $self->config->{template}{server}{login};
    my $host = $self->config->{template}{server}{host};
    my $root_path =  $self->config->{template}{server}{root_path};
    return "There is no template defined in your config files" unless @templates;

    push @str, @templates . " templates availables (They will get from $login\@$host:$root_path)";
    for my $template ( @templates ) {
        my $id = $template->{id};
        my $name = $template->{name};
        my $filename = $template->{filename};
        my $searchengine = $template->{searchengine};
        push @str, "[$id] \t$name ( $filename " . ($searchengine // "") . ")";
    }
    return join "\n", @str;
}

1;

__END__

=pod

=head1 NAME

Klol::Lxc::Templates - Lxc templates class.

=head1 DESCRIPTION

List of templates. Contain methods to access to a specific template or list all templates.

=head1 METHODS

=head2 new

    my $templates = Lxc::Templates->new;

Construct a list of template.

=head2 get_template

    my template = $templates->get_template( 'template_name' );

Return a hashref representing a template.
The parameter can be an id or a name.

=head2 str

    say $templates;

Stringify this class.

=head1 AUTHORS

Jonathan Druart <jonathan.druart@biblibre.com>

=head1 LICENSE

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
