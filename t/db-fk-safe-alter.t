# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.
use 5.14.0;
use strict;
use warnings;
use lib qw( . lib local/lib/perl5 );
use Test::More;
use Test2::Tools::Mock qw(mock);

BEGIN {
  $ENV{LOCALCONFIG_ENV} = 'BMO';
  $ENV{BMO_db_driver}   = 'sqlite';
  $ENV{BMO_db_name}     = ':memory:';
}
use Bugzilla;
use Bugzilla::DB;

# bz_fk_safe_alter_columns only calls back into bz_column_info,
# bz_drop_related_fks and bz_alter_column, so we can exercise it against a
# bare Bugzilla::DB object with those three methods mocked. This keeps the
# test database-independent and lets us assert exactly what gets passed to
# bz_alter_column.

# The (mocked) current state of the database, keyed by "table.column".
my %current_column;

# Ordered log of drop/alter events, so we can assert both what happened and
# that foreign keys are dropped *before* the column is altered.
my @events;

my $mock = mock 'Bugzilla::DB' => (
  override => [
    bz_column_info => sub {
      my ($self, $table, $column) = @_;
      return $current_column{"$table.$column"};
    },
    bz_drop_related_fks => sub {
      my ($self, $table, $column) = @_;
      push @events, {action => 'drop', table => $table, column => $column};
      return [];
    },
    bz_alter_column => sub {
      my ($self, $table, $column, $def) = @_;
      push @events, {action => 'alter', table => $table, column => $column, def => $def};
    },
  ],
);

my $dbh = bless {}, 'Bugzilla::DB';

# Run a fix set with warnings silenced (the method warns for every drop).
sub run_fixes {
  @events = ();
  local $SIG{__WARN__} = sub { };
  $dbh->bz_fk_safe_alter_columns(\@_);
}

# --- The definition is passed to bz_alter_column verbatim ------------------
# This is the regression guard for bug 2052103: passing only {TYPE => ...}
# would silently drop NOTNULL. The method must forward the caller's complete
# definition unchanged.
%current_column = ('flags.type_id' => {TYPE => 'INT2', NOTNULL => 1});
run_fixes({
  table        => 'flags',
  column       => 'type_id',
  definition   => {TYPE => 'INT3', NOTNULL => 1},
  only_if_type => 'INT2',
});
is(scalar(@events), 2, 'a needed fix produces a drop and an alter');
is($events[0]{action}, 'drop',  'foreign keys are dropped first');
is($events[1]{action}, 'alter', 'column is altered second');
is_deeply(
  $events[1]{def},
  {TYPE => 'INT3', NOTNULL => 1},
  'the complete definition (including NOTNULL) is forwarded unchanged'
);

# --- only_if_type gating: scalar mismatch skips the fix --------------------
%current_column = ('flags.type_id' => {TYPE => 'INT3', NOTNULL => 1});
run_fixes({
  table        => 'flags',
  column       => 'type_id',
  definition   => {TYPE => 'INT3', NOTNULL => 1},
  only_if_type => 'INT2',
});
is(scalar(@events), 0, 'only_if_type mismatch (scalar) skips the fix entirely');

# --- only_if_type gating: arrayref match applies the fix -------------------
%current_column = ('flags.type_id' => {TYPE => 'INT4', NOTNULL => 1});
run_fixes({
  table        => 'flags',
  column       => 'type_id',
  definition   => {TYPE => 'INT3', NOTNULL => 1},
  only_if_type => ['INT2', 'INT4'],
});
is(scalar(@events), 2, 'only_if_type arrayref match applies the fix');

# --- Idempotency: no change needed means no drop and no alter --------------
%current_column = ('flags.type_id' => {TYPE => 'INT3', NOTNULL => 1});
run_fixes({
  table      => 'flags',
  column     => 'type_id',
  definition => {TYPE => 'INT3', NOTNULL => 1},
});
is(scalar(@events), 0, 'a column already matching the target is left untouched');

# A differing attribute (NOTNULL) still triggers the fix even when TYPE matches.
%current_column = ('flags.type_id' => {TYPE => 'INT3'});
run_fixes({
  table      => 'flags',
  column     => 'type_id',
  definition => {TYPE => 'INT3', NOTNULL => 1},
});
is(scalar(@events), 2, 'a differing scalar attribute triggers the fix');

# --- Missing column is skipped, not fatal ----------------------------------
%current_column = ();
run_fixes({
  table      => 'no_such_table',
  column     => 'no_such_column',
  definition => {TYPE => 'INT3'},
});
is(scalar(@events), 0, 'a non-existent column is skipped');

# --- Incomplete fix specs are skipped --------------------------------------
%current_column = ('flags.type_id' => {TYPE => 'INT2'});
run_fixes(
  {column => 'type_id', definition => {TYPE => 'INT3'}},    # no table
  {table  => 'flags',   definition => {TYPE => 'INT3'}},    # no column
  {table  => 'flags',   column     => 'type_id'},           # no definition
);
is(scalar(@events), 0, 'fixes missing table/column/definition are skipped');

# --- Multiple fixes are processed in order ---------------------------------
%current_column = (
  'flags.type_id'    => {TYPE => 'INT2', NOTNULL => 1},
  'flagtypes.id'     => {TYPE => 'MEDIUMINT', NOTNULL => 1, PRIMARYKEY => 1},
);
run_fixes(
  {table => 'flags',     column => 'type_id', definition => {TYPE => 'INT3', NOTNULL => 1}, only_if_type => 'INT2'},
  {table => 'flagtypes', column => 'id',      definition => {TYPE => 'MEDIUMSERIAL', NOTNULL => 1, PRIMARYKEY => 1}},
);
my @altered = map { "$_->{table}.$_->{column}" } grep { $_->{action} eq 'alter' } @events;
is_deeply(
  \@altered,
  ['flags.type_id', 'flagtypes.id'],
  'multiple fixes are altered in the order given'
);

done_testing;
