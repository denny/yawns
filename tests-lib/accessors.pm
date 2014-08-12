
=head1 NAME

accessors - create accessor methods in caller's package.

=head1 SYNOPSIS

  package Foo;
  use accessors qw( foo bar baz );

  my $obj = bless {}, 'Foo';

  # generates chaining accessors
  # that you can set like this:
  $obj->foo( 'hello ' )
      ->bar( 'world' )
      ->baz( "!\n" );

  # you get the values by passing no params:
  print $obj->foo, $obj->bar, $obj->baz;

=cut

package accessors;

use 5.006;
use strict;
use warnings::register;

our $VERSION = '1.02';
our $REVISION = ( split( / /, ' $Revision: 1.22 $ ' ) )[2];

our $Debug        = 0;
our $ExportLevel  = 0;
our @InvalidNames = qw( BEGIN CHECK INIT END DESTROY AUTOLOAD );

use constant style => 'chained';

sub import
{
    my $class   = shift;
    my $callpkg = caller( $class->ExportLevel );

    my @properties = @_ or return;

    $class->create_accessors_for( $callpkg, @properties );
}

sub create_accessors_for
{
    my $class   = shift;
    my $callpkg = shift;

    warn( 'creating ' . $class->style . ' accessors( ',
          join( ' ', @_ ),
          " ) in pkg '$callpkg'" )
      if $class->Debug;

    foreach my $property (@_)
    {
        my $accessor = "$callpkg\::$property";
        die("can't create $accessor - '$property' is not a valid name!")
          unless $class->isa_valid_name($property);
        warn( "creating " . $class->style . " accessor: $accessor\n" )
          if $class->Debug > 1;
        $class->create_accessor( $accessor, $property );
    }

    return $class;
}

sub create_accessor
{
    my ( $class, $accessor, $property ) = @_;
    $property = "-$property";

    # set/get is slightly faster if we eval instead of using a closure + anon
    # sub, but the difference is marginal (~5%), and this uses less memory...
    my $sub = sub {
        ( @_ > 1 ) ? ( $_[0]->{ $property } = $_[1], return $_[0] ) :
                     $_[0]->{ $property };
    };
    no strict 'refs';
    *{ $accessor } = $sub;
}

sub isa_valid_name
{
    my ( $class, $property ) = @_;
    return unless $property =~ /^(?!\d)\w+$/;
    return if grep {$property eq $_} $class->InvalidNames;
    return 1;
}

##
## on the off-chance that someone will sub-class:
##

## don't like studly caps for sub-names, but stick with Exporter-like style...
sub Debug        {$Debug;}
sub ExportLevel  {$ExportLevel}
sub InvalidNames {@InvalidNames}

1;

__END__

=head1 DESCRIPTION

The B<accessors> pragma lets you create simple accessors at compile-time.

This saves you from writing them by hand, which tends to result in
I<cut-n-paste> errors and a mess of duplicated code.  It can also help you
reduce the ammount of unwanted I<direct-variable access> that may creep into
your codebase when you're feeling lazy.  B<accessors> was designed with
laziness in mind.

Method-chaining accessors are generated by default.  Note that you can still
use L<accessors::chained> directly for reasons of backwards compatibility.

See L<accessors::rw> for accessors that always return the current value if
you don't like method chaining.

=head1 GENERATED METHODS

B<accessors> will generate methods that return the current object on set:

  sub foo {
      my $self = shift;
      if (@_) { $self->{-foo} = shift; return $self; }
      else    { return $self->{-foo}; }
  }

This way they can be I<chained> together.

=head2 Why prepend the dash?

The dash (C<->) is prepended to the property name for a few reasons:

=over 4

=item *

interoperability with L<Error>.

=item *

to make it difficult to accidentally access the property directly ala:

  use accessors qw( foo );
  $obj->{foo};  # prevents this by mistake
  $obj->foo;    # when you probably meant this

(this might sound woolly, but it's easy enough to do).

=item *

syntactic sugar (this I<is> woolly :).

=back

You shouldn't care too much about how the property is stored anyway - if you do,
you're likely trying to do something special (and should really consider writing
the accessors out long hand), or it's simply a matter of preference in which
case you can use L<accessors::rw>, or sub-class this module.

=head1 PERFORMANCE

There is B<little-to-no performace hit> when using generated accessors; in
fact there is B<usually a performance gain>.

=over 4

=item *

typically I<10-30% faster> than hard-coded accessors (like the above example).

=item *

typically I<1-15% slower> than I<optimized> accessors (less readable).

=item *

typically a I<small> performance hit at startup (accessors are created at
compile-time).

=item *

uses the same anonymous sub to reduce memory consumption (sometimes by 80%).

=back

See the benchmark tests included with this distribution for more details.

=head1 MOTIVATION

The main difference between the B<accessors> pragma and other accessor
generators is B<simplicity>.

=over 4

=item * interface

B<use accessors qw( ... )> is as easy as it gets.

=item * a pragma

it fits in nicely with the B<base> pragma:

  use base      qw( Some::Class );
  use accessors qw( foo bar baz );

and accessors get created at compile-time.

=item * no bells and whistles

The module is extensible instead.

=back

=head1 SUB-CLASSING

If you prefer a different style of accessor or you need to do something more
complicated, there's nothing to stop you from sub-classing.  It should be
pretty easy.  Look through L<accessors::classic>, L<accessors::ro>, and
L<accessors::rw> to see how it's done.

=head1 CAVEATS

Classes using blessed scalarrefs, arrayrefs, etc. are not supported for sake
of simplicity.  Only hashrefs are supported.

=head2 Class Accessors Are Not Supported

If you are accidentally calling the accessor as a class method:

  my $object = 'Foo'; # an accident!
  print $object->bla, "\n"; # does not die!

Then (as of v1.02) this will produce an error ala:

  Can't use string ("Foo") as a HASH ref while "strict refs" in use
  at lib/accessors.pm line 72.

=head1 THANKS

Thanks to Michael G. Schwern for indirectly inspiring this module, and for his
feedback & suggestions.

Also to Paul Makepeace and David Wright for showing me faster accessors, to
chocolateboy & others for their contributions, the CPAN Testers for their bug
reports, and to James Duncan and people on London.pm for their feedback.

=head1 AUTHORS

Steve Purkis <spurkis@cpan.org>

Contributions from:

  chocolateboy
  Slaven Rezić

=head1 SOURCE

L<https://github.com/spurkis/Perl-accessors>

=head1 SEE ALSO

L<accessors::classic>, L<accessors::chained>

Similar and related modules:

L<base>,
L<fields>,
L<Class::Accessor>,
L<Moose>,
L<Class::Struct>,
L<Class::Methodmaker>,
L<Class::Generate>,
L<Class::Class>,
L<Class::Tangram>,
L<Object::Tiny>

=cut
