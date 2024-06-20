use strict;
use warnings;

use Test::More;
use Test::Fatal;

my $CLASS;

{

    package Foo;

    sub bar {
        return 'original value';
    }

    sub baz {
        return 'original baz value';
    }
}

BEGIN {
    chdir 't' if -d 't';
    use lib '../lib';
    $CLASS = 'Sub::Override';
    use_ok($CLASS) || die;
}

can_ok( $CLASS, 'new' );

my $override = $CLASS->new;
isa_ok( $override, $CLASS, '... and the object it returns' );

can_ok( $override, 'replace' );

like
  exception { $override->replace( 'No::Such::Sub', '' ) },
  qr/^\QCannot replace non-existent sub (No::Such::Sub)\E/,
  "... and we can't replace a sub which doesn't exist";

like
  exception { $override->replace( 'Foo::bar', 'not a subref' ) },
  qr/\(not a subref\) must be a code reference/,
  '... and only a code reference may replace a subroutine';

ok( $override->replace( 'Foo::bar', sub {'new subroutine'} ),
    '... and replacing a subroutine should succeed'
);
is( Foo::bar(), 'new subroutine',
    '... and the subroutine should exhibit the new behavior'
);

ok( $override->replace( 'Foo::bar' => sub {'new subroutine 2'} ),
    '... and we should be able to replace a sub more than once'
);
is( Foo::bar(), 'new subroutine 2',
    '... and still have the sub exhibit the new behavior'
);

can_ok( $override, 'override' );
ok( $override->override( 'Foo::bar' => sub {'new subroutine 3'} ),
    '... and it should also replace a subroutine'
);
is( Foo::bar(), 'new subroutine 3',
    '... and act just like replace()'
);

can_ok( $override, 'restore' );

like
  exception { $override->restore('Did::Not::Override') },
  qr/^\QCannot restore a sub that was not replaced (Did::Not::Override)/,
  '... and it should fail if the subroutine had not been replaced';

$override->restore('Foo::bar');
is( Foo::bar(), 'original value',
    '... and the subroutine should exhibit the original behavior'
);

like
  exception { $override->restore('Foo::bar') },
  qr/^\QCannot restore a sub that was not replaced (Foo::bar)/,
  '... but we should not be able to restore it twice';

{
    my $override = $CLASS->new;
    ok( $override->replace( 'Foo::bar', sub {'lexical value'} ),
        'A new override object should be able to replace a subroutine'
    );

    is( Foo::bar(), 'lexical value',
        '... and the subroutine should exhibit the new behavior'
    );
}
is( Foo::bar(), 'original value',
    '... but should revert to the original behavior when the object falls out of scope'
);

{
    my $override = $CLASS->new( 'Foo::bar', sub {'lexical value'} );
    ok( $override,
        'We should be able to override a sub from the constructor' );

    is( Foo::bar(), 'lexical value',
        '... and the subroutine should exhibit the new behavior'
    );
    ok( $override->restore,
        '... and we do not need an argument to restore'
    );
    is( Foo::bar(), 'original value',
        '... and the subroutine should exhibit its original behavior'
    );
    $override->replace( 'Foo::bar', sub { } );
    $override->replace( 'Foo::baz', sub { } );
}

{

    package TempReplace;
    sub foo {23}
    sub bar {42}

    my $override = $CLASS->new( 'foo', sub {42} );
    $override->replace( 'bar', sub {'barbar'} );
    main::is( foo(), 42,
        'Not fully qualifying a sub name will assume the current package' );
    $override->restore('foo');
    main::is( foo(), 23, '... and we should be able to restore said sub' );
    main::is( bar(), 'barbar', '... and not restore any other overridden subs' );

    $override->restore('TempReplace::bar');
    main::is( bar(), 42, '... and restore even if we use a full qualified sub name' );
}

can_ok( $override, 'inject' );

{

    package TempInject;
    sub foo      { 23 }

    my $override = $CLASS->new;

    main::like
      main::exception { $override->inject( 'foo', '' ) },
      qr/\QCannot create a sub that already exists (TempInject::foo)/,
      '... and we should not be able to inject subs over existing subs';

    main::ok(
        $override->inject( 'something', sub { 42 } ),
        '... but injecting a new subroutine should succeed'
    );
    main::is( TempInject::something(), 42,
        '... and we should be able to call the new function' );

    $override->restore('something');
    main::like
      main::exception { TempInject::something() },
      qr/\QUndefined subroutine &TempInject::something called\E/,
      '... and we should be able to restore the original behavior';
}

can_ok( $override, 'inherit' );

{

    package TempInheritParent;
    sub foo { 'foo' }
    sub bar { 'bar' }

    package TempInheritChild;
    our @ISA = qw(TempInheritParent);
    sub foo { 'foo' }
    sub baz { 'baz' }

    my $override = $CLASS->new;

    main::like
      main::exception { $override->inherit( 'foo', sub { 'foo-override'; } ) },
      qr/\QCannot create a sub that already exists (TempInheritChild::foo)/,
      '... and we should not be able to inherit and existing inherited sub';

    main::like
      main::exception { $override->inherit( 'baz', sub { 'baz-override'; } ) },
      qr/\QCannot create a sub that already exists (TempInheritChild::baz)/,
      '... and we should not be able to inherit an existing sub';

    main::like
      main::exception { $override->inherit( 'foobarbaz', sub { 'foo-override'; } ) },
      qr/\QSub does not exist in parent class (TempInheritChild::foobarbaz)/,
      '... and we should not be able to inherit a non-existing sub';

    main::ok(
      $override->inherit( 'bar', sub { 'bar-inherited' } ),
      '... but inheriting a subroutine should succeed'
    );
    main::is( TempInheritChild->bar(), 'bar-inherited',
      '... and we should be able to call the new function' );


    $override->restore('bar');
    main::is( TempInheritChild->bar(), 'bar',
      '... and we should be able to restore the original behaviour' );
}


can_ok( $override, 'wrap' );

{

    package TempWrap;
    sub foo {23}
    sub bar ($$) {$_[0] + $_[1]}

    my $override = $CLASS->new;

    main::ok( $override->wrap( 'foo',
        sub {
            my ($orig, @args) = @_;
            return $args[0] ? 24 : $orig->();
        }
    ), '... and we should be able to successfully wrap a subroutine' );
    main::is( foo(),  23, '... and wrapped sub foo conditionally returns original value' );
    main::is( foo(1), 24, '... and wrapped sub foo conditionally returns override value' );

    $override->restore('foo');
    main::is( foo(1), 23, '... and we can restore a wrapped subroutine' );

    main::ok( $override->wrap( 'bar',
        sub {
            my ($orig, @args) = @_;
            return $args[0] == 4 && $args[1] == 2 ? 42 : $orig->(@args);
        }
    ), '... and we should be able to successfully wrap a prototyped subroutine' );
    main::is( bar(5,2),  7,  '... and wrapped prototyped sub bar conditionally returns original value' );
    main::is( bar(4,2),  42, '... and wrapped prototyped sub bar conditionally returns override value' );

    # make sure there are no left-over references preventing destroy from running.
    undef $override;
    main::is( bar(4,2), 6, '... and we can restore a wrapped subroutine' );
}

{

    package TempMultiParent;
    sub new { bless {}, shift }
    sub inherit1 { 'inherit1' }
    sub inherit2 { 'inherit2' }

    package TempMultiChild;
    our @ISA = qw(TempMultiParent);
    sub replace1 { 'replace1' }
    sub replace2 { 'replace2' }
    sub wrap1    { 'wrap1' }
    sub wrap2    { 'wrap2' }

    main::ok(
        my $override = $CLASS->new(
            replace1 => sub { 'replaced1' },
            replace2 => sub { 'replaced2' },
        )->inject(
            inject1 => sub { 'injected1' },
            inject2 => sub { 'injected2' },
        )->inherit(
            inherit1 => sub { 'inherited1' },
            inherit2 => sub { 'inherited2' },
        )->wrap(
            wrap1 => sub { $_[0]->() . ' wrapped' },
            wrap2 => sub { $_[0]->() . ' wrapped' },
        ),
        "We should be able to override multiple subs at once"
    );

    package main;

    my $child = TempMultiChild->new;
    is($child->replace1, 'replaced1', "... and 'replace1' was replaced");
    is($child->replace2, 'replaced2', "... and 'replace2' was replaced");
    is($child->inject1, 'injected1', "... and 'inject1' was injected");
    is($child->inject2, 'injected2', "... and 'inject2' was injected");
    is($child->inherit1, 'inherited1', "... and 'inherit1' was inherited");
    is($child->inherit2, 'inherited2', "... and 'inherit2' was inherited");
    is($child->wrap1, 'wrap1 wrapped', "... and 'wrap1' was wrapped");
    is($child->wrap2, 'wrap2 wrapped', "... and 'wrap2' was wrapped");

    undef $override;
    is($child->replace1, 'replace1', "... and 'replace1' was restored");
    is($child->replace2, 'replace2', "... and 'replace2' was restored");
    like exception { $child->inject1 }, qr/\QCan't locate object method/, "... and 'inject1' was restored";
    like exception { $child->inject2 }, qr/\QCan't locate object method/, "... and 'inject2' was restored";
    is($child->inherit1, 'inherit1', "... and 'inherit1' was restored");
    is($child->inherit2, 'inherit2', "... and 'inherit2' was restored");
    is($child->wrap1, 'wrap1', "... and 'wrap1' was restored");
    is($child->wrap2, 'wrap2', "... and 'wrap2' was restored");
}

done_testing;
