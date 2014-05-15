#!/usr/local/bin/perl -w
use strict;

use Test::More 'no_plan';
#use Test::More tests => 29;
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

can_ok( $override, 'get_call_count' );

is( $override->get_call_count( 'Foo::bar' ), 0,
    '... 0 call count for overridden method'
);

like
    exception { $override->get_call_count },
    qr/^\QYou must provide the name of a sub for a get_call_count/,
    '... but we must explicitly provide the sub name for a get_call_count';

like
    exception { $override->get_call_count( 'Foo::none' ) },
    qr/^\QCan only provide call counts for overridden subs/,
    '... and it should fail if the subroutine had not been replaced';

is( Foo::bar(), 'new subroutine',
    '... and the subroutine should exhibit the new behavior'
);

is( $override->get_call_count( 'Foo::bar' ), 1,
    '... 1 call count for overridden method'
);

can_ok( $override, 'get_call_args' );

can_ok( $override, 'get_return_values' );

like
    exception { $override->get_call_args },
    qr/^\QYou must provide the name of a sub for get_call_args/,
    '... but we must explicitly provide the sub name for get_call_args';

like
    exception { $override->get_call_args( 'Foo::none' ) },
    qr/^\QCan only provide call args for overridden subs/,
    '... and it should fail if the subroutine had not been replaced';


is_deeply( $override->get_call_args( 'Foo::bar' ), [ [] ], '... and should have just the first call\'s args available' );

is_deeply( $override->get_return_values( 'Foo::bar' ), [ 'new subroutine' ], '... and just the first call\'s return values' );

Foo::bar( 'some arg' );

is_deeply(
    $override->get_call_args( 'Foo::bar' ),
    [ [], ['some arg']],
    '... and after a second call, have 2 sets of args' );

is_deeply(
    $override->get_return_values( 'Foo::bar' ),
    [ 'new subroutine', 'new subroutine' ],
    '... and 2 sets of return values' );

is_deeply(
    $override->get_call_args( 'Foo::bar', 2 ),
    ['some arg'],
    '... and just the 2nd call\'s args' );

is_deeply(
    $override->get_return_values( 'Foo::bar', 2 ),
    'new subroutine',
    '... and just the 2nd call\'s return values' );

like
    exception { $override->get_call_args( 'Foo::bar', 3 ) },
    qr/^\QCannot provide args for a call not made/,
    '... but we must specify a call number within the get_call_args';

like
    exception { $override->get_return_values( 'Foo::bar', 3 ) },
    qr/^\QCannot provide return values for a call not made/,
    '... but we must specify a call number within the get_call_args';

like
    exception { $override->get_return_values },
    qr/^\QYou must provide the name of a sub for get_return_values/,
    '... but we must explicitly provide the sub name for get_return_values';

like
    exception { $override->get_return_values( 'Foo::none' ) },
    qr/^\QCan only provide return values for overridden subs/,
    '... and it should fail if the subroutine had not been replaced';


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
    my $new_override = $CLASS->new;
    ok( $new_override->replace( 'Foo::bar', sub {'lexical value'} ),
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
    my $new_override = $CLASS->new( 'Foo::bar', sub {'lexical value'} );
    ok( $new_override,
        'We should be able to override a sub from the constructor' );

    is( Foo::bar(), 'lexical value',
        '... and the subroutine should exhibit the new behavior'
    );
    ok( $new_override->restore,
        '... and we do not need an argument to restore if only one sub is overridden'
    );
    is( Foo::bar(), 'original value',
        '... and the subroutine should exhibit its original behavior'
    );
    $new_override->replace( 'Foo::bar', sub { } );
    $new_override->replace( 'Foo::baz', sub { } );

    like
      exception { $new_override->restore },
      qr/You must provide the name of a sub to restore: \(Foo::bar, Foo::baz\)/,
      '... but we must explicitly provide the sub name if more than one was replaced';
}

{

    package Temp;
    sub foo {23}
    sub bar {42}

    my $override = Sub::Override->new( 'foo', sub {42} );
    $override->replace( 'bar', sub {'barbar'} );
    main::is( foo(), 42,
        'Not fully qualifying a sub name will assume the current package' );
    $override->restore('foo');
    main::is( foo(), 23, '... and we should be able to restore said sub' );

    $override->restore('Temp::bar');
    main::is( bar(), 42, '... even if we use a full qualified sub name' );
}
