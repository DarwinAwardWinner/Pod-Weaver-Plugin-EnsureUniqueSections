use strict;
use warnings;
use utf8;

package Pod::Weaver::Plugin::EnsureUniqueSections;
use Moose;
use MooseX::Has::Sugar;
use Moose::Autobox;
use Text::Trim;

use Lingua::EN::Inflect::Number qw(to_S);
use Carp;
with 'Pod::Weaver::Role::Finalizer';
# ABSTRACT: Ensure that POD has no duplicate section headers.

=attr lax

If true (the default), certain similar section headers will be considered
equivalent. The following similarities are considered (more may be added later):

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

"AUTHOR" and "AUTHORS" are the same section. A section header
consisting of multiple words, such as "DISCLAIMER OF WARRANTY", is not
affected by this rule.

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
                    ->sort->join(" AND ");
    }
    return $text;
}

=method finalize_document

This method checks the document for duplicate headers, and throws an
error if any are found. If no duplicates are found, it simply does
nothing. It does not modify the POD in any way.

=cut

sub finalize_document {
    use Smart::Comments;
    my ($self, $document) = @_;
    my $headers = $document->children
        ->grep(sub{ $_->command eq 'head1' })
            ->map(sub{ $_->content });
    my %header_group;
    for my $h (@$headers) {
        push @{$header_group{$self->_header_key($h)}}, $h;
    }

    my $duplicate_headers = [ keys %header_group ]
        ->map(sub{ @{$header_group{$_}} > 1 ? $header_group{$_}->head : () })
            ->sort;
    if (@$duplicate_headers > 0) {
        my $message = "Error: The following headers appear multiple times: '" . $duplicate_headers->join(q{', '}) . q{'};
        croak $message;
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
top-level section headers. This can help you if you are converting a
dist to Dist::Zilla and Pod::Weaver, and you forgot to remove POD
sections that are now auto-generated.

By default, this module does some tricks to detect similar headers,
such as C<AUTHOR> and C<AUTHORS>. You can turn this off by setting
C<strict = 1> in F<weaver.ini>.

=head1 BUGS AND LIMITATIONS

I would like to convert this to a Dist::Zilla testing plugin, but I
haven't yet figured out how to find all files in a dist with POD and
extract all their headers.

Please report any bugs or feature requests to
C<rct+perlbug@thompsonclan.org>.

=head1 SEE ALSO

=for :list
* L<Pod::Weaver>
