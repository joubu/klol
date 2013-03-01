package Klol::Lxc::Templates;

use Modern::Perl;
use IPC::Cmd qw[run];
use Klol::Config;
use base qw(Class::Accessor);
__PACKAGE__->mk_accessors(qw( config templates) );

use overload '""' => \&str;

sub new {
    my ( $class ) = @_;
    my $config = Klol::Config->new();

    my $self = $class->SUPER::new( { config => $config, templates => [] });

    bless( $self, $class );
}

sub list {
    my ( $self ) = @_;
    return $self->templates
        if scalar(@{$self->templates});
    my $templates = $self->config->{template}{availables};
    my @templates;
    my $i = 1;
    for my $template_name ( sort keys %$templates ) {
        my $template = $templates->{$template_name};
        $template->{name} = $template_name;
        $template->{id} = $i;
        push @templates, $template;
        $i++;
    }
    return @templates;
}

sub str {
    my ( $self ) = @_;
    my @str;
    my @templates = $self->list;
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
