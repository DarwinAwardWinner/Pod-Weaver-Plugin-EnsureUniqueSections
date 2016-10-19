use strict;
use warnings;
use utf8;

package Pod::Weaver::Plugin::EnsureUniqueSections;
use Moose;
use MooseX::Has::Sugar;
use Moose::Autobox 0.10;
use Text::Trim;

use Lingua::EN::Inflect::Number qw(to_S);
use Carp;
with 'Pod::Weaver::Role::Finalizer';
with 'Pod::Weaver::Role::Preparer';
# ABSTRACT: Ensure that POD has no duplicate section headers.

=attr strict

If set to true (1), section headers will only be considered duplicates
if they match exactly. If false (the default), certain similar section
headers will be considered equivalent. The following similarities are
considered (more may be added later):

=over 4

=item All whitespace and punctuation are equivalant

For example, the following would all be considered duplicates of each
other: C< SEE ALSO>, C<SEE ALSO>, C<SEE,ALSO:>.

=item Case-insensitive

For example, C<Name> and C<NAME> would be considered duplicates.

=item Sets of words separated by "AND".

For example, "COPYRIGHT AND LICENSE" would be considered a duplicate
of "LICENSE AND COPYRIGHT".

=item Plurals

A plural noun is considered equivalent to its singular. For example,
"AUTHOR" and "AUTHORS" are the same section. A section header
consisting of multiple words, such as "DISCLAIMER OF WARRANTY", is not
affected by this rule.

This rule uses L<Lingua::EN::Inflect::Number> to interconvert between
singular and plural forms. Hopefully you don't need to make a section
called C<OCTOPI>.

=back

Note that these rules apply recursively, so C<Authors; and
Contributors> would be a duplicate of C< CONTRIBUTORS AND AUTHOR>.

=cut

has strict => (
    ro, lazy,
    isa => 'Bool',
    default => sub { 0 },
);

sub _header_key {
    my ($self, $text) = @_;
    if (!$self->strict) {
        # Replace all non-words with a single space
        $text =~ s{\W+}{ }xsmg;
        # Trim leading and trailing whitespace
        $text = trim $text;
        # All to uppercase
        $text = uc $text;
        # Reorder "AND" lists and singularize nouns
        $text = $text
            ->split(qr{ AND }i)
                ->map(sub { m{\W} ? $_ : to_S $_; })
                    ->sort->join(' AND ');
    }
    return $text;
}

=method prepare_input

This method modifies the weaver object by moving EnsureUniqueSections
to the end of the weaver's plugin list to ensure that it gets to look
at the final woven POD.

THIS IS PURE EVIL. This is a hack to ensure that this plugin gets "the
last word". Obviously if all plugins used this it would be total
chaos. I welcome alternative suggestions. The main issue is that when
other Finalizers, such as Section::Leftovers (which happens to be the
most likely plugin to create duplicate sections), produce sections,
this plugin will only see those sections if it runs after those
Finalizers. Hence the need to be the last plugin on the list.

=cut

sub prepare_input {
    my $self = shift;
    # Put EnsureUniqueSections plugins at the end
    my $plugins = $self->weaver->plugins;
    @$plugins = ((grep { $_ != $self } @$plugins), $self);
}

=method finalize_document

This method checks the document for duplicate headers, and throws an
error if any are found. If no duplicates are found, it simply does
nothing. It does not modify the POD in any way.

=cut

sub finalize_document {
    my ($self, $document) = @_;
    my $headers = $document->children
        ->grep(sub{ $_->can( 'command' ) and $_->command eq 'head1' })
            ->map(sub{ $_->content });
    my %header_group;
    for my $h (@$headers) {
        push @{$header_group{$self->_header_key($h)}}, $h;
    }

    my $duplicate_headers = [ keys %header_group ]
        ->map(sub{ @{$header_group{$_}} > 1 ? $header_group{$_}->head : () })
            ->sort;
    if (@$duplicate_headers > 0) {
        my $pod_string = "";
        for my $h (@$duplicate_headers) {
            for my $node (@{ $document->children->grep(
                sub {
                    $_->can('command') && $_->command eq 'head1' &&
                        $_->content eq $h
                    }) }) {
                $pod_string .= $node->as_pod_string;
            }
        }
        $self->log_debug(["POD of duplicated headers:\n\n%s", $pod_string]);
        my $message = "Error: The following headers appear multiple times: '" . $duplicate_headers->join(q{', '}) . q{'};
        $self->log_fatal($message);
    }
}

1;                        # Magic true value required at end of module
__END__

=head1 SYNOPSIS

In F<weaver.ini>

    [-EnsureUniqueSections]
    strict = 0 ; The default

=head1 DESCRIPTION

This plugin simply ensures that the POD after weaving has no duplicate
top-level section headers. This can help you if you are converting
from writing all your own POD to generating it with L<Pod::Weaver>. If
you begin generating a section with L<Pod::Weaver> but you forget to
delete the manually written section of the same name, this plugin will
warn you.

By default, this module does some tricks to detect similar headers,
such as C<AUTHOR> and C<AUTHORS>. You can turn this off by setting
C<strict = 1> in F<weaver.ini>, in which case only I<exactly identical>
headers will be considered duplicates of each other.

=head2 DIAGNOSTIC MESSAGES

If any similar (or identical if C<strict> is 1) section headers are
found, all of their names will be listed on STDERR. Generally, you
should take this list of modules and remove each from your POD. Then
you should ensure that the sections generated by L<Pod::Weaver> are
suitable substitutes for those sections. In the case of similar names,
only the first instance in each set of similar names will be listed.

=head1 BUGS AND LIMITATIONS

=head2 Should also be available as a L<Dist::Zilla> testing plugin

I would like to convert this to a L<Dist::Zilla> testing plugin, so that
you can use it without enabling L<Pod::Weaver> if you don't want to,
but I haven't yet figured out how to find all files in a dist with POD
and extract all their headers. If anyone knows, please tell me.

=head2 No recursive duplicate checks

This module only checks for duplicates in top-level headers (i.e.
C<head1>). It could be extended to check the C<head2> elements within
each C<head1> section and so on, but generally L<Pod::Weaver> is not
called upon to generate subsections, so you are unlikely to end up
with duplicates at any level other than the first. However, if there
is demand for recursive duplicate detection, I will add it.

Please report any bugs or feature requests to
C<rct+perlbug@thompsonclan.org>.

=head1 SEE ALSO

=for :list
* L<Pod::Weaver> - The module that this is a plugin for.
* L<Lingua::EN::Inflect::Number> - Used to determine the singular forms of plural nouns.
