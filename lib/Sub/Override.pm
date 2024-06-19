package Sub::Override;

use strict;
use warnings;

use Carp qw(croak);
use Scalar::Util qw(set_prototype);

our $VERSION = '0.13';

sub new {
    my $class = shift;
    my $self = bless {}, $class;
    $self->replace(@_) if @_;
    return $self;
}

{
    no warnings 'once';
    # because override() was a better name and this is what it should have been
    # called.
    *override = *replace{CODE};
}

sub replace {
    my ( $self, %subs ) = @_;
    while (my ($sub_name, $new_sub_ref) = each %subs) {
        $sub_name = $self->_get_fully_qualified_sub_name($sub_name);
        $self->_ensure_code_slot_exists($sub_name)->_validate_sub_ref($new_sub_ref);
        {
            no strict 'refs';
            $self->{$sub_name} ||= *$sub_name{CODE};
            no warnings 'redefine';
            *$sub_name = $new_sub_ref;
        }
    }
    return $self;
}

sub inject {
    my ( $self, %subs ) = @_;
    while (my ($sub_name, $new_sub_ref) = each %subs) {
        $sub_name = $self->_get_fully_qualified_sub_name($sub_name);
        $self->_ensure_code_slot_does_not_exist($sub_name)->_validate_sub_ref($new_sub_ref);
        {
            no strict 'refs';
            $self->{$sub_name} = undef;
            no warnings 'redefine';
            *$sub_name = $new_sub_ref;
        }
    }
    return $self;
}

sub inherit {
    my ( $self, %subs ) = @_;
    while (my ($sub_name, $new_sub_ref) = each %subs) {
        $sub_name = $self->_get_fully_qualified_sub_name($sub_name);
        $self->_ensure_code_slot_exists_in_parent_class($sub_name)->_validate_sub_ref($new_sub_ref);
        {
            no strict 'refs';
            $self->{$sub_name} = undef;
            no warnings 'redefine';
            *$sub_name = $new_sub_ref;
        }
    }
    return $self;
}

sub wrap {
    my ( $self, %subs ) = @_;
    while (my ($sub_name, $new_sub_ref) = each %subs) {
        $sub_name = $self->_get_fully_qualified_sub_name($sub_name);
        $self->_ensure_code_slot_exists($sub_name)->_validate_sub_ref($new_sub_ref);
        {
            no strict 'refs';
            $self->{$sub_name} ||= *$sub_name{CODE};

            # passing $self->{$sub_name} directly to arguments prevents early
            # destruction. use goto to bypass new stack frame.
            my $weak_old_sub_ref = $self->{$sub_name};
            my $new_wrap_sub_ref = sub { unshift(@_, $weak_old_sub_ref); goto &$new_sub_ref };

            my $prototype = prototype($self->{$sub_name});
            set_prototype(\&$new_wrap_sub_ref, $prototype) if defined $prototype;

            no warnings 'redefine';
            *$sub_name = $new_wrap_sub_ref;
        }
    }
    return $self;
}

sub restore {
    my ( $self, @sub_names ) = @_;

    @sub_names = keys %$self if !@sub_names;

    for my $sub_name (@sub_names) {
        $sub_name = $self->_get_fully_qualified_sub_name($sub_name);
        croak("Cannot restore a sub that was not replaced ($sub_name)")
            unless exists $self->{$sub_name};

        my $maybe_old_sub_ref = delete $self->{$sub_name};

        no strict 'refs';
        no warnings 'redefine', 'misc';
        if ( defined $maybe_old_sub_ref ) {
            *$sub_name = $maybe_old_sub_ref;
        } else {
            undef *$sub_name;
        }
    }

    return $self;
}

sub DESTROY { shift->restore; }

sub _get_fully_qualified_sub_name {
    my ( $self, $sub_name ) = @_;
    if ( ( $sub_name || '' ) =~ /^\w+$/ ) { # || "" for suppressing test warnings
        my $package = do {
            my $this_package = __PACKAGE__;
            my $call_level = 0;
            my $caller_package;
            # skip any package that starts with this package (to allow for
            # inheritance).
            while ( !$caller_package || $caller_package =~ /^$this_package/ ) {
                ($caller_package) = caller($call_level);
                $call_level++;
            }
            $caller_package;
        };
        $sub_name = "${package}::$sub_name";
    }
    return $sub_name;
};

sub _validate_sub_ref {
    my ( $self, $sub_ref ) = @_;
    unless ( 'CODE' eq ref $sub_ref ) {
        croak("($sub_ref) must be a code reference");
    }
    return $self;
};

sub _ensure_code_slot_exists {
    my ( $self, $code_slot ) = @_;
    no strict 'refs';
    unless ( defined *{$code_slot}{CODE} ) {
        croak("Cannot replace non-existent sub ($code_slot)");
    }
    return $self;
};

sub _ensure_code_slot_does_not_exist {
    my ( $self, $code_slot ) = @_;
    no strict 'refs';
    if ( defined *{$code_slot}{CODE} ) {
        croak("Cannot create a sub that already exists ($code_slot)");
    }
    return $self;
};

sub _ensure_code_slot_exists_in_parent_class {
    my ( $self, $code_slot ) = @_;
    $self->_ensure_code_slot_does_not_exist($code_slot);
    {
        no strict 'refs';
        my $class  = *{$code_slot}{PACKAGE};
        my $method = *{$code_slot}{NAME};
        croak("Sub does not exist in parent class ($code_slot)")
            unless $class->can($method);
    }
    return $self;
};

1;

__END__

=head1 NAME

Sub::Override - Perl extension for easily overriding subroutines

=head1 VERSION

0.13

=head1 SYNOPSIS

  use Sub::Override;

  sub foo { 'original sub' };
  print foo(); # prints 'original sub'

  my $override = Sub::Override->new( foo => sub { 'overridden sub' } );
  print foo(); # prints 'overridden sub'
  $override->restore;
  print foo(); # prints 'original sub'

=head1 DESCRIPTION

=head2 The Problem

Sometimes subroutines need to be overridden.  In fact, your author does this
frequently for tests.  Particularly when testing, using a Mock Object can be
overkill when all you want to do is override one tiny, little function.

Overriding a subroutine is often done with syntax similar to the following.

  {
    local *Some::sub = sub {'some behavior'};
    # do something
  }
  # original subroutine behavior restored

This has a few problems.

  {
    local *Get::some_feild = { 'some behavior' };
    # do something
  }

In the above example, not only have we probably misspelled the subroutine name,
but even if there had been a subroutine with that name, we haven't overridden
it.  These two bugs can be subtle to detect.

Further, if we're attempting to localize the effect by placing this code in a
block, the entire construct is cumbersome.

Hook::LexWrap also allows us to override sub behavior, but I can never remember
the exact syntax.

=head2 An easier way to replace subroutines

Instead, C<Sub::Override> allows the programmer to simply name the sub to
replace and to supply a sub to replace it with.

  my $override = Sub::Override->new('Some::sub => sub {'new data'});

  # which is equivalent to:
  my $override = Sub::Override->new;
  $override->replace('Some::sub' => sub { 'new data' });

You can replace multiple subroutines, if needed:

  $override->replace(
    'Some::sub1' => sub { 'new data1' },
    'Some::sub2' => sub { 'new data2' },
    'Some::sub3' => sub { 'new data3' },
  );

If the subroutine has a prototype, the new subroutine should be declared with
same prototype as original one:

  $override->replace('Some::sub_with_proto' => sub ($$) { ($_[0], $_ [1]) });

A subroutine may be replaced as many times as desired.  This is most useful
when testing how code behaves with multiple conditions.

  $override->replace('Some::thing' => sub { 0 });
  is($object->foo, 'wibble', 'wibble is returned if Some::thing is false');

  $override->replace('Some::thing' => sub { 1 });
  is($object->foo, 'puppies', 'puppies are returned if Some::thing is true');

=head2 Injecting a subroutine

If you want to inject a new subroutine into a package, you can use the
C<inject()> method. This is identical to C<replace()>, except that it
requires that the subroutine does not previously exist:

  $override->inject('Some::sub' => sub {'new data'});

This is useful if you want to add a subroutine to a package that doesn't
already have it.

If you attempt to inject a subroutine that already exists, an exception will be
thrown.

  $override->inject('Some::sub' => sub {'new data'}); # works
  $override->inject('Some::sub' => sub {'new data'}); # throws an exception

You can restore your injection if you want to re-inject:

  $override->inject('Some::sub' => sub {'new data'}); # works
  $override->restore;
  $override->inject('Some::sub' => sub {'new data'}); # works

=head2 Inheriting a subroutine

Similar to 'inject', 'inherit' will only allow you to create a new subroutine
on a child object that inherits the routine from the parent, and doesn't
exist in the child:

  package Parent;
  sub foo {}
  sub bar {}

  package Child;
  use parent 'Parent';
  sub foo {}

  $override->inherit('Child::bar' => sub {'new data'});

'Inherit' will allow you to set up a new 'Child::bar' subroutine since it is
inherited from Parent. Attempting to 'inherit' 'Child::foo' will result in an
exception being thrown since 'foo' already exists in Child. Similarly,
attempting to 'inherit' new subroutine 'something' in Child will also result
in an exception since it doesn't exist in Parent and won't be inherited by Child.

=head2 Wrapping a subroutine

There may be times when you want to 'conditionally' replace a subroutine - for
example, to override the original subroutine only if certain args are passed.
For this you can specify C<wrap> instead of C<replace>. C<wrap> is identical to
C<replace>, except the original subroutine is passed as the first arg to your
new subroutine. You can call the original sub via 'shift->(@_)':

  $override->wrap('Some::sub' =>
    sub {
      my ($orig, @args) = @_;
      return 1 if $args[0];
      return $orig->(@args);
    }
  );

=head2 Restoring subroutines

If the object falls out of scope, the original subs are restored.  However, if
you need to restore a subroutine early, just use the C<restore()> method:

  my $override = Sub::Override->new('Some::sub' => sub {'new data'});
  # do stuff
  $override->restore;

Which is somewhat equivalent to:

  {
    my $override = Sub::Override->new('Some::sub' => sub {'new data'});
    # do stuff, then go out of scope and restore.
  }

If you have overridden more than one subroutine with an override object, you
can name individual subroutine(s) you wish to restore:

  $override->restore('This::sub', 'That::sub');

If you simply call C<restore()> with no arguments, all routines that have been
overridden will be restored, leaving the environment in the original state.

Note C<restore()> will always restore the original behavior of the subroutine
no matter how many times you have overridden it.

=head2 Chaining calls

All override routines return the override object, allowing you to chain calls:

  $sub->replace(
    'This::sub' => sub {1},
    'That::sub' => sub {2},
  )->inject(
    'Some::Class::this => sub {3},
  )->wrap(
    'Some::Class::that => sub {4},
  );

=head2 Which package is the subroutine in?

Ordinarily, you want to fully qualify the subroutine by including the package
name.  However, failure to fully qualify the subroutine name will assume the
current package.

  package Foo;
  use Sub::Override;
  sub foo { 23 };
  my $override = Sub::Override->new( foo => sub { 42 } ); # assumes Foo::foo
  print foo(); # prints 42
  $override->restore;
  print foo(); # prints 23

=head1 METHODS

=head2 new

  my $sub = Sub::Override->new;
  my $sub = Sub::Override->new($new_sub_ref => $sub_ref);

Creates a new C<Sub::Override> instance.  Optionally, you may replace a
subroutine while creating a new object.

=head2 replace

  $sub->replace($new_sub_ref => $sub_body);

Temporarily replaces a subroutine with another subroutine.

This method will C<croak> if the subroutine to be replaced does not exist.

=head2 override

  my $sub = Sub::Override->new;
  $sub->override($new_sub_ref => $sub_body);

C<override> is an alternate name for C<replace>.  They are the same method.

=head2 inject

  $sub->inject($new_sub_ref => $sub_body);

Temporarily injects a subroutine into a package.  Returns the instance, so
chaining the method is allowed:

=head2 inherit

  $sub->inherit($new_sub_ref => $sub_body);

Checks that the subroutine exists in a parent class, but not in the current
class, and injects it into the current class to inherit the parent's version.

=head2 wrap

  $sub->wrap($new_sub_ref => $sub_body);

Temporarily wraps a subroutine with another subroutine. The original subroutine
is passed as the first arg to the new subroutine.

=head2 restore

  $sub->restore($sub1, $sub2);

Restores the previous behavior of the specified subroutine(s).  Passing no
args will restore all overridden subs.  This will also happen automatically if
the C<Sub::Override> object falls out of scope.

=head1 EXPORT

None by default.

=head1 CAVEATS

If you need to override the same sub several times do not create a new
C<Sub::Override> object, but instead always reuse the existing one and call
C<replace> on it. Creating a new object to override the same sub will result
in weird behavior.

  # Do not do this!
  my $sub_first = Sub::Override->new( 'Foo:bar' => sub { 'first' } );
  my $sub_second = Sub::Override->new( 'Foo::bar' => sub { 'second' } );

  # Do not do this either!
  my $sub = Sub::Override->new( 'Foo::bar' => sub { 'first' } );
  $sub = Sub::Override->new( 'Foo::bar' => sub { 'second' } );

Both of those usages could result in of your subs being lost, depending
on the order in which you restore them.

Instead, call C<replace> on the existing C<$sub>.

  my $sub = Sub::Override->new( 'Foo::bar' => sub { 'first' } );
  $sub->replace( 'Foo::bar' => sub { 'second' } );

=head1 BUGS

Probably.  Tell me about 'em.

=head1 SEE ALSO

=over 4

=item *
L<Hook::LexWrap> -- can also override subs, but with different capabilities

=item *
L<Test::MockObject> -- use this if you need to alter an entire class

=back

=head1 MAINTAINER

Robin Murray (mvsjes2 on github)

=head1 AUTHOR

Curtis "Ovid" Poe, C<< <ovid [at] cpan [dot] org> >>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2004-2013 by Curtis "Ovid" Poe

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.2 or,
at your option, any later version of Perl 5 you may have available.

=cut
