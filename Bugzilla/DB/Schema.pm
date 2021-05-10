# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::DB::Schema;

###########################################################################
#
# Purpose: Object-oriented, DBMS-independent database schema for Bugzilla
#
# This is the base class implementing common methods and abstract schema.
#
###########################################################################

use 5.10.1;
use strict;
use warnings;
use Moo;

use Bugzilla::Error;
use Bugzilla::Hook;
use Bugzilla::Util;
use Bugzilla::Constants;

use Carp qw(confess);
use Digest::MD5 qw(md5_hex);
use Hash::Util qw(lock_value unlock_hash lock_keys unlock_keys);
use List::MoreUtils qw(firstidx natatime);
use Try::Tiny;
use Module::Runtime qw(require_module);
use Safe;

# Historical, needed for SCHEMA_VERSION = '1.00'
use Storable qw(dclone freeze thaw);

# New SCHEMA_VERSIONs (2+) use this
use Data::Dumper;

# Whether or not this database can safely create FKs when doing a
# CREATE TABLE statement. This is false for most DBs, because they
# prevent you from creating FKs on tables and columns that don't
# yet exist. (However, in SQLite it's 1 because SQLite allows that.)
use constant FK_ON_CREATE => 0;

#--------------------------------------------------------------------------
# Define the Bugzilla abstract database schema and version as constants.

use constant SCHEMA_VERSION => 3;
use constant ADD_COLUMN     => 'ADD COLUMN';

# Multiple FKs can be added using ALTER TABLE ADD CONSTRAINT in one
# SQL statement. This isn't true for all databases.
use constant MULTIPLE_FKS_IN_ALTER => 1;

# This is a reasonable default that's true for both PostgreSQL and MySQL.
use constant MAX_IDENTIFIER_LEN => 63;

use constant FIELD_TABLE_SCHEMA => {
  FIELDS => [
    id                  => {TYPE => 'SMALLSERIAL', NOTNULL => 1, PRIMARYKEY => 1},
    value               => {TYPE => 'varchar(64)', NOTNULL => 1},
    sortkey             => {TYPE => 'INT2',        NOTNULL => 1, DEFAULT => 0},
    isactive            => {TYPE => 'BOOLEAN',     NOTNULL => 1, DEFAULT => 'TRUE'},
    visibility_value_id => {TYPE => 'INT2'},
  ],

  # Note that bz_add_field_table should prepend the table name
  # to these index names.
  INDEXES => [
    value_idx               => {FIELDS => ['value'], TYPE => 'UNIQUE'},
    sortkey_idx             => ['sortkey',           'value'],
    visibility_value_id_idx => ['visibility_value_id'],
  ],
};

use constant ABSTRACT_SCHEMA => {

  # BUG-RELATED TABLES
  # ------------------

  # General Bug Information
  # -----------------------
  bugs => {
    FIELDS => [
      bug_id      => {TYPE => 'MEDIUMSERIAL', NOTNULL => 1, PRIMARYKEY => 1},
      assigned_to => {
        TYPE       => 'INT3',
        NOTNULL    => 1,
        REFERENCES => {TABLE => 'profiles', COLUMN => 'userid'}
      },
      bug_file_loc => {TYPE => 'MEDIUMTEXT',   NOTNULL => 1, DEFAULT => "''"},
      bug_severity => {TYPE => 'varchar(64)',  NOTNULL => 1},
      bug_status   => {TYPE => 'varchar(64)',  NOTNULL => 1},
      bug_type     => {TYPE => 'varchar(20)',  NOTNULL => 1},
      filed_via    => {TYPE => 'varchar(40)',  NOTNULL => 1, DEFAULT => "'unknown'"},
      creation_ts  => {TYPE => 'DATETIME'},
      delta_ts     => {TYPE => 'DATETIME',     NOTNULL => 1},
      short_desc   => {TYPE => 'varchar(255)', NOTNULL => 1},
      op_sys       => {TYPE => 'varchar(64)',  NOTNULL => 1},
      priority     => {TYPE => 'varchar(64)',  NOTNULL => 1},
      product_id   => {
        TYPE       => 'INT2',
        NOTNULL    => 1,
        REFERENCES => {TABLE => 'products', COLUMN => 'id'}
      },
      rep_platform => {TYPE => 'varchar(64)', NOTNULL => 1},
      reporter     => {
        TYPE       => 'INT3',
        NOTNULL    => 1,
        REFERENCES => {TABLE => 'profiles', COLUMN => 'userid'}
      },
      version      => {TYPE => 'varchar(64)', NOTNULL => 1},
      component_id => {
        TYPE       => 'INT2',
        NOTNULL    => 1,
        REFERENCES => {TABLE => 'components', COLUMN => 'id'}
      },
      resolution       => {TYPE => 'varchar(64)', NOTNULL => 1, DEFAULT => "''"},
      target_milestone => {TYPE => 'varchar(20)', NOTNULL => 1, DEFAULT => "'---'"},
      qa_contact =>
        {TYPE => 'INT3', REFERENCES => {TABLE => 'profiles', COLUMN => 'userid'}},
      status_whiteboard   => {TYPE => 'MEDIUMTEXT', NOTNULL => 1, DEFAULT => "''"},
      lastdiffed          => {TYPE => 'DATETIME'},
      everconfirmed       => {TYPE => 'BOOLEAN', NOTNULL => 1},
      reporter_accessible => {TYPE => 'BOOLEAN', NOTNULL => 1, DEFAULT => 'TRUE'},
      cclist_accessible   => {TYPE => 'BOOLEAN', NOTNULL => 1, DEFAULT => 'TRUE'},
      estimated_time      => {TYPE => 'decimal(7,2)', NOTNULL => 1, DEFAULT => '0'},
      remaining_time      => {TYPE => 'decimal(7,2)', NOTNULL => 1, DEFAULT => '0'},
      deadline            => {TYPE => 'DATETIME'},
      alias               => {TYPE => 'varchar(40)'},
    ],
    INDEXES => [
      bugs_alias_idx            => {FIELDS => ['alias'], TYPE => 'UNIQUE'},
      bugs_assigned_to_idx      => ['assigned_to'],
      bugs_creation_ts_idx      => ['creation_ts'],
      bugs_delta_ts_idx         => ['delta_ts'],
      bugs_bug_severity_idx     => ['bug_severity'],
      bugs_bug_status_idx       => ['bug_status'],
      bugs_but_type_idx         => ['bug_type'],
      bugs_op_sys_idx           => ['op_sys'],
      bugs_priority_idx         => ['priority'],
      bugs_product_id_idx       => ['product_id'],
      bugs_reporter_idx         => ['reporter'],
      bugs_version_idx          => ['version'],
      bugs_component_id_idx     => ['component_id'],
      bugs_resolution_idx       => ['resolution'],
      bugs_target_milestone_idx => ['target_milestone'],
      bugs_qa_contact_idx       => ['qa_contact'],
    ],
  },

  bugs_fulltext => {
    FIELDS => [
      bug_id => {
        TYPE       => 'INT3',
        NOTNULL    => 1,
        PRIMARYKEY => 1,
        REFERENCES => {TABLE => 'bugs', COLUMN => 'bug_id', DELETE => 'CASCADE'}
      },
      short_desc => {TYPE => 'varchar(255)', NOTNULL => 1},

      # Comments are stored all together in one column for searching.
      # This allows us to examine all comments together when deciding
      # the relevance of a bug in fulltext search.
      comments           => {TYPE => 'LONGTEXT'},
      comments_noprivate => {TYPE => 'LONGTEXT'},
    ],
    INDEXES => [
      bugs_fulltext_short_desc_idx => {FIELDS => ['short_desc'], TYPE => 'FULLTEXT'},
      bugs_fulltext_comments_idx   => {FIELDS => ['comments'],   TYPE => 'FULLTEXT'},
      bugs_fulltext_comments_noprivate_idx =>
        {FIELDS => ['comments_noprivate'], TYPE => 'FULLTEXT'},
    ],
  },

  bugs_activity => {
    FIELDS => [
      id     => {TYPE => 'INTSERIAL', NOTNULL => 1, PRIMARYKEY => 1},
      bug_id => {
        TYPE       => 'INT3',
        NOTNULL    => 1,
        REFERENCES => {TABLE => 'bugs', COLUMN => 'bug_id', DELETE => 'CASCADE'}
      },
      attach_id => {
        TYPE => 'INT5',
        REFERENCES =>
          {TABLE => 'attachments', COLUMN => 'attach_id', DELETE => 'CASCADE'}
      },
      who => {
        TYPE       => 'INT3',
        NOTNULL    => 1,
        REFERENCES => {TABLE => 'profiles', COLUMN => 'userid'}
      },
      bug_when => {TYPE => 'DATETIME', NOTNULL => 1},
      fieldid  => {
        TYPE       => 'INT3',
        NOTNULL    => 1,
        REFERENCES => {TABLE => 'fielddefs', COLUMN => 'id'}
      },
      added      => {TYPE => 'varchar(255)'},
      removed    => {TYPE => 'varchar(255)'},
      comment_id => {
        TYPE => 'INT4',
        REFERENCES =>
          {TABLE => 'longdescs', COLUMN => 'comment_id', DELETE => 'CASCADE'}
      },
    ],
    INDEXES => [
      bugs_activity_bug_id_idx   => ['bug_id'],
      bugs_activity_who_idx      => ['who'],
      bugs_activity_bug_when_idx => ['bug_when'],
      bugs_activity_fieldid_idx  => ['fieldid'],
      bugs_activity_added_idx    => ['added'],
      bugs_activity_removed_idx  => ['removed'],
    ],
  },

  cc => {
    FIELDS => [
      bug_id => {
        TYPE       => 'INT3',
        NOTNULL    => 1,
        REFERENCES => {TABLE => 'bugs', COLUMN => 'bug_id', DELETE => 'CASCADE'}
      },
      who => {
        TYPE       => 'INT3',
        NOTNULL    => 1,
        REFERENCES => {TABLE => 'profiles', COLUMN => 'userid', DELETE => 'CASCADE'}
      },
    ],
    INDEXES => [
      cc_bug_id_idx => {FIELDS => [qw(bug_id who)], TYPE => 'UNIQUE'},
      cc_who_idx    => ['who'],
    ],
  },

  longdescs => {
    FIELDS => [
      comment_id => {TYPE => 'INTSERIAL', NOTNULL => 1, PRIMARYKEY => 1},
      bug_id     => {
        TYPE       => 'INT3',
        NOTNULL    => 1,
        REFERENCES => {TABLE => 'bugs', COLUMN => 'bug_id', DELETE => 'CASCADE'}
      },
      who => {
        TYPE       => 'INT3',
        NOTNULL    => 1,
        REFERENCES => {TABLE => 'profiles', COLUMN => 'userid'}
      },
      bug_when        => {TYPE => 'DATETIME',     NOTNULL => 1},
      work_time       => {TYPE => 'decimal(7,2)', NOTNULL => 1, DEFAULT => '0'},
      thetext         => {TYPE => 'LONGTEXT',     NOTNULL => 1},
      isprivate       => {TYPE => 'BOOLEAN',      NOTNULL => 1, DEFAULT => 'FALSE'},
      already_wrapped => {TYPE => 'BOOLEAN',      NOTNULL => 1, DEFAULT => 'FALSE'},
      type            => {TYPE => 'INT2',         NOTNULL => 1, DEFAULT => '0'},
      extra_data  => {TYPE => 'varchar(255)'},
      is_markdown => {TYPE => 'BOOLEAN', NOTNULL => 1, DEFAULT => 'FALSE'}
    ],
    INDEXES => [
      longdescs_bug_id_idx   => ['bug_id'],
      longdescs_who_idx      => [qw(who bug_id)],
      longdescs_bug_when_idx => ['bug_when'],
    ],
  },

  longdescs_tags => {
    FIELDS => [
      id         => {TYPE => 'MEDIUMSERIAL', NOTNULL => 1, PRIMARYKEY => 1},
      comment_id => {
        TYPE => 'INT4',
        REFERENCES =>
          {TABLE => 'longdescs', COLUMN => 'comment_id', DELETE => 'CASCADE'}
      },
      tag => {TYPE => 'varchar(24)', NOTNULL => 1},
    ],
    INDEXES =>
      [longdescs_tags_idx => {FIELDS => ['comment_id', 'tag'], TYPE => 'UNIQUE'},],
  },

  longdescs_tags_weights => {
    FIELDS => [
      id     => {TYPE => 'MEDIUMSERIAL', NOTNULL => 1, PRIMARYKEY => 1},
      tag    => {TYPE => 'varchar(24)',  NOTNULL => 1},
      weight => {TYPE => 'INT3',         NOTNULL => 1},
    ],
    INDEXES =>
      [longdescs_tags_weights_tag_idx => {FIELDS => ['tag'], TYPE => 'UNIQUE'},],
  },

  longdescs_tags_activity => {
    FIELDS => [
      id     => {TYPE => 'MEDIUMSERIAL', NOTNULL => 1, PRIMARYKEY => 1},
      bug_id => {
        TYPE       => 'INT3',
        NOTNULL    => 1,
        REFERENCES => {TABLE => 'bugs', COLUMN => 'bug_id', DELETE => 'CASCADE'}
      },
      comment_id => {
        TYPE => 'INT4',
        REFERENCES =>
          {TABLE => 'longdescs', COLUMN => 'comment_id', DELETE => 'CASCADE'}
      },
      who => {
        TYPE       => 'INT3',
        NOTNULL    => 1,
        REFERENCES => {TABLE => 'profiles', COLUMN => 'userid'}
      },
      bug_when => {TYPE => 'DATETIME', NOTNULL => 1},
      added    => {TYPE => 'varchar(24)'},
      removed  => {TYPE => 'varchar(24)'},
    ],
    INDEXES => [longdescs_tags_activity_bug_id_idx => ['bug_id'],],
  },

  dependencies => {
    FIELDS => [
      blocked => {
        TYPE       => 'INT3',
        NOTNULL    => 1,
        REFERENCES => {TABLE => 'bugs', COLUMN => 'bug_id', DELETE => 'CASCADE'}
      },
      dependson => {
        TYPE       => 'INT3',
        NOTNULL    => 1,
        REFERENCES => {TABLE => 'bugs', COLUMN => 'bug_id', DELETE => 'CASCADE'}
      },
    ],
    INDEXES => [
      dependencies_blocked_idx =>
        {FIELDS => [qw(blocked dependson)], TYPE => 'UNIQUE'},
      dependencies_dependson_idx => ['dependson'],
    ],
  },

  regressions => {
    FIELDS => [
      regressed_by => {
        TYPE       => 'INT3',
        NOTNULL    => 1,
        REFERENCES => {TABLE => 'bugs', COLUMN => 'bug_id', DELETE => 'CASCADE'}
      },
      regresses => {
        TYPE       => 'INT3',
        NOTNULL    => 1,
        REFERENCES => {TABLE => 'bugs', COLUMN => 'bug_id', DELETE => 'CASCADE'}
      },
    ],
    INDEXES => [
      regressions_regresses_idx =>
        {FIELDS => [qw(regresses regressed_by)], TYPE => 'UNIQUE'},
      regressions_regressed_by_idx => ['regressed_by'],
    ],
  },

  attachments => {
    FIELDS => [
      attach_id => {TYPE => 'BIGSERIAL', NOTNULL => 1, PRIMARYKEY => 1},
      bug_id    => {
        TYPE       => 'INT3',
        NOTNULL    => 1,
        REFERENCES => {TABLE => 'bugs', COLUMN => 'bug_id', DELETE => 'CASCADE'}
      },
      creation_ts       => {TYPE => 'DATETIME',     NOTNULL => 1},
      modification_time => {TYPE => 'DATETIME',     NOTNULL => 1},
      description       => {TYPE => 'TINYTEXT',     NOTNULL => 1},
      mimetype          => {TYPE => 'TINYTEXT',     NOTNULL => 1},
      ispatch           => {TYPE => 'BOOLEAN',      NOTNULL => 1, DEFAULT => 'FALSE'},
      filename          => {TYPE => 'varchar(100)', NOTNULL => 1},
      submitter_id => {
        TYPE       => 'INT3',
        NOTNULL    => 1,
        REFERENCES => {TABLE => 'profiles', COLUMN => 'userid'}
      },
      isobsolete  => {TYPE => 'BOOLEAN', NOTNULL => 1, DEFAULT => 'FALSE'},
      isprivate   => {TYPE => 'BOOLEAN', NOTNULL => 1, DEFAULT => 'FALSE'},
      attach_size => {TYPE => 'INT4',    NOTNULL => 1, DEFAULT => 0},
    ],
    INDEXES => [
      attachments_bug_id_idx            => ['bug_id'],
      attachments_creation_ts_idx       => ['creation_ts'],
      attachments_modification_time_idx => ['modification_time'],
      attachments_submitter_id_idx      => ['submitter_id', 'bug_id'],
      attachments_ispatch_idx           => ['ispatch'],
    ],
  },

  attach_data => {
    FIELDS => [
      id => {
        TYPE       => 'INT5',
        NOTNULL    => 1,
        PRIMARYKEY => 1,
        REFERENCES =>
          {TABLE => 'attachments', COLUMN => 'attach_id', DELETE => 'CASCADE'}
      },
      thedata => {TYPE => 'LONGBLOB', NOTNULL => 1},
    ],
  },

  attachment_storage_class => {
    FIELDS => [
      id => {
        TYPE       => 'INT5',
        NOTNULL    => 1,
        PRIMARYKEY => 1,
        REFERENCES =>
          {TABLE => 'attachments', COLUMN => 'attach_id', DELETE => 'CASCADE'}
      },
      storage_class => {TYPE => 'varchar(64)', NOTNULL => 1},
      extra_data    => {TYPE => 'MEDIUMTEXT'}
    ],
  },

  duplicates => {
    FIELDS => [
      dupe_of => {
        TYPE       => 'INT3',
        NOTNULL    => 1,
        REFERENCES => {TABLE => 'bugs', COLUMN => 'bug_id', DELETE => 'CASCADE'}
      },
      dupe => {
        TYPE       => 'INT3',
        NOTNULL    => 1,
        PRIMARYKEY => 1,
        REFERENCES => {TABLE => 'bugs', COLUMN => 'bug_id', DELETE => 'CASCADE'}
      },
    ],
  },

  bug_see_also => {
    FIELDS => [
      id     => {TYPE => 'MEDIUMSERIAL', NOTNULL => 1, PRIMARYKEY => 1},
      bug_id => {
        TYPE       => 'INT3',
        NOTNULL    => 1,
        REFERENCES => {TABLE => 'bugs', COLUMN => 'bug_id', DELETE => 'CASCADE'}
      },
      value => {TYPE => 'varchar(255)', NOTNULL => 1},
      class => {TYPE => 'varchar(255)', NOTNULL => 1, DEFAULT => "''"},
    ],
    INDEXES => [
      bug_see_also_bug_id_idx => {FIELDS => [qw(bug_id value)], TYPE => 'UNIQUE'},
    ],
  },

  # Auditing
  # --------

  audit_log => {
    FIELDS => [
      user_id => {
        TYPE       => 'INT3',
        REFERENCES => {TABLE => 'profiles', COLUMN => 'userid', DELETE => 'SET NULL'}
      },
      class     => {TYPE => 'varchar(255)', NOTNULL => 1},
      object_id => {TYPE => 'INT4',         NOTNULL => 1},
      field     => {TYPE => 'varchar(64)',  NOTNULL => 1},
      removed   => {TYPE => 'MEDIUMTEXT'},
      added     => {TYPE => 'MEDIUMTEXT'},
      at_time   => {TYPE => 'DATETIME',     NOTNULL => 1},
    ],
    INDEXES => [audit_log_class_idx => ['class', 'at_time'],],
  },

  # Keywords
  # --------

  keyworddefs => {
    FIELDS => [
      id          => {TYPE => 'SMALLSERIAL', NOTNULL => 1, PRIMARYKEY => 1},
      name        => {TYPE => 'varchar(64)', NOTNULL => 1},
      description => {TYPE => 'MEDIUMTEXT',  NOTNULL => 1},
      is_active   => {TYPE => 'BOOLEAN',     NOTNULL => 1, DEFAULT => 'TRUE'},
    ],
    INDEXES => [keyworddefs_name_idx => {FIELDS => ['name'], TYPE => 'UNIQUE'},],
  },

  keywords => {
    FIELDS => [
      bug_id => {
        TYPE       => 'INT3',
        NOTNULL    => 1,
        REFERENCES => {TABLE => 'bugs', COLUMN => 'bug_id', DELETE => 'CASCADE'}
      },
      keywordid => {
        TYPE       => 'INT2',
        NOTNULL    => 1,
        REFERENCES => {TABLE => 'keyworddefs', COLUMN => 'id', DELETE => 'CASCADE'}
      },

    ],
    INDEXES => [
      keywords_bug_id_idx    => {FIELDS => [qw(bug_id keywordid)], TYPE => 'UNIQUE'},
      keywords_keywordid_idx => ['keywordid'],
    ],
  },

  # Flags
  # -----

  # "flags" stores one record for each flag on each bug/attachment.
  flags => {
    FIELDS => [
      id      => {TYPE => 'MEDIUMSERIAL', NOTNULL => 1, PRIMARYKEY => 1},
      type_id => {
        TYPE       => 'INT2',
        NOTNULL    => 1,
        REFERENCES => {TABLE => 'flagtypes', COLUMN => 'id', DELETE => 'CASCADE'}
      },
      status => {TYPE => 'char(1)', NOTNULL => 1},
      bug_id => {
        TYPE       => 'INT3',
        NOTNULL    => 1,
        REFERENCES => {TABLE => 'bugs', COLUMN => 'bug_id', DELETE => 'CASCADE'}
      },
      attach_id => {
        TYPE => 'INT5',
        REFERENCES =>
          {TABLE => 'attachments', COLUMN => 'attach_id', DELETE => 'CASCADE'}
      },
      creation_date     => {TYPE => 'DATETIME', NOTNULL => 1},
      modification_date => {TYPE => 'DATETIME'},
      setter_id         => {
        TYPE       => 'INT3',
        NOTNULL    => 1,
        REFERENCES => {TABLE => 'profiles', COLUMN => 'userid'}
      },
      requestee_id =>
        {TYPE => 'INT3', REFERENCES => {TABLE => 'profiles', COLUMN => 'userid'}},
    ],
    INDEXES => [
      flags_bug_id_idx       => [qw(bug_id attach_id)],
      flags_setter_id_idx    => ['setter_id'],
      flags_requestee_id_idx => ['requestee_id'],
      flags_type_id_idx      => ['type_id'],
    ],
  },

  # "flagtypes" defines the types of flags that can be set.
  flagtypes => {
    FIELDS => [
      id               => {TYPE => 'SMALLSERIAL', NOTNULL => 1, PRIMARYKEY => 1},
      name             => {TYPE => 'varchar(50)', NOTNULL => 1},
      description      => {TYPE => 'MEDIUMTEXT',  NOTNULL => 1},
      cc_list          => {TYPE => 'varchar(200)'},
      target_type      => {TYPE => 'char(1)',     NOTNULL => 1, DEFAULT => "'b'"},
      is_active        => {TYPE => 'BOOLEAN',     NOTNULL => 1, DEFAULT => 'TRUE'},
      is_requestable   => {TYPE => 'BOOLEAN',     NOTNULL => 1, DEFAULT => 'FALSE'},
      is_requesteeble  => {TYPE => 'BOOLEAN',     NOTNULL => 1, DEFAULT => 'FALSE'},
      is_multiplicable => {TYPE => 'BOOLEAN',     NOTNULL => 1, DEFAULT => 'FALSE'},
      sortkey          => {TYPE => 'INT2',        NOTNULL => 1, DEFAULT => '0'},
      grant_group_id   => {
        TYPE       => 'INT3',
        REFERENCES => {TABLE => 'groups', COLUMN => 'id', DELETE => 'SET NULL'}
      },
      request_group_id => {
        TYPE       => 'INT3',
        REFERENCES => {TABLE => 'groups', COLUMN => 'id', DELETE => 'SET NULL'}
      },
    ],
  },

  # "flaginclusions" and "flagexclusions" specify the products/components
  #     a bug/attachment must belong to in order for flags of a given type
  #     to be set for them.
  flaginclusions => {
    FIELDS => [
      type_id => {
        TYPE       => 'INT2',
        NOTNULL    => 1,
        REFERENCES => {TABLE => 'flagtypes', COLUMN => 'id', DELETE => 'CASCADE'}
      },
      product_id => {
        TYPE       => 'INT2',
        REFERENCES => {TABLE => 'products', COLUMN => 'id', DELETE => 'CASCADE'}
      },
      component_id => {
        TYPE       => 'INT2',
        REFERENCES => {TABLE => 'components', COLUMN => 'id', DELETE => 'CASCADE'}
      },
    ],
    INDEXES => [
      flaginclusions_type_id_idx =>
        {FIELDS => [qw(type_id product_id component_id)], TYPE => 'UNIQUE'},
    ],
  },

  flagexclusions => {
    FIELDS => [
      type_id => {
        TYPE       => 'INT2',
        NOTNULL    => 1,
        REFERENCES => {TABLE => 'flagtypes', COLUMN => 'id', DELETE => 'CASCADE'}
      },
      product_id => {
        TYPE       => 'INT2',
        REFERENCES => {TABLE => 'products', COLUMN => 'id', DELETE => 'CASCADE'}
      },
      component_id => {
        TYPE       => 'INT2',
        REFERENCES => {TABLE => 'components', COLUMN => 'id', DELETE => 'CASCADE'}
      },
    ],
    INDEXES => [
      flagexclusions_type_id_idx =>
        {FIELDS => [qw(type_id product_id component_id)], TYPE => 'UNIQUE'},
    ],
  },

  # General Field Information
  # -------------------------

  fielddefs => {
    FIELDS => [
      id     => {TYPE => 'MEDIUMSERIAL', NOTNULL => 1, PRIMARYKEY => 1},
      name   => {TYPE => 'varchar(64)',  NOTNULL => 1},
      type   => {TYPE => 'INT2',         NOTNULL => 1, DEFAULT => FIELD_TYPE_UNKNOWN},
      custom => {TYPE => 'BOOLEAN',      NOTNULL => 1, DEFAULT => 'FALSE'},
      description => {TYPE => 'TINYTEXT', NOTNULL => 1},
      mailhead    => {TYPE => 'BOOLEAN',  NOTNULL => 1, DEFAULT => 'FALSE'},
      sortkey     => {TYPE => 'INT2',     NOTNULL => 1},
      obsolete    => {TYPE => 'BOOLEAN',  NOTNULL => 1, DEFAULT => 'FALSE'},
      enter_bug   => {TYPE => 'BOOLEAN',  NOTNULL => 1, DEFAULT => 'FALSE'},
      buglist     => {TYPE => 'BOOLEAN',  NOTNULL => 1, DEFAULT => 'FALSE'},
      visibility_field_id =>
        {TYPE => 'INT3', REFERENCES => {TABLE => 'fielddefs', COLUMN => 'id'}},
      value_field_id =>
        {TYPE => 'INT3', REFERENCES => {TABLE => 'fielddefs', COLUMN => 'id'}},
      reverse_desc => {TYPE => 'TINYTEXT'},
      is_mandatory => {TYPE => 'BOOLEAN', NOTNULL => 1, DEFAULT => 'FALSE'},
      is_numeric   => {TYPE => 'BOOLEAN', NOTNULL => 1, DEFAULT => 'FALSE'},
    ],
    INDEXES => [
      fielddefs_name_idx           => {FIELDS => ['name'], TYPE => 'UNIQUE'},
      fielddefs_sortkey_idx        => ['sortkey'],
      fielddefs_value_field_id_idx => ['value_field_id'],
      fielddefs_is_mandatory_idx   => ['is_mandatory'],
    ],
  },

  # Field Visibility Information
  # -------------------------

  field_visibility => {
    FIELDS => [
      field_id => {
        TYPE       => 'INT3',
        REFERENCES => {TABLE => 'fielddefs', COLUMN => 'id', DELETE => 'CASCADE'}
      },
      value_id => {TYPE => 'INT2', NOTNULL => 1}
    ],
    INDEXES => [
      field_visibility_field_id_idx =>
        {FIELDS => [qw(field_id value_id)], TYPE => 'UNIQUE'},
    ],
  },

  # Per-product Field Values
  # ------------------------

  versions => {
    FIELDS => [
      id         => {TYPE => 'MEDIUMSERIAL', NOTNULL => 1, PRIMARYKEY => 1},
      value      => {TYPE => 'varchar(64)',  NOTNULL => 1},
      product_id => {
        TYPE       => 'INT2',
        NOTNULL    => 1,
        REFERENCES => {TABLE => 'products', COLUMN => 'id', DELETE => 'CASCADE'}
      },
      isactive => {TYPE => 'BOOLEAN', NOTNULL => 1, DEFAULT => 'TRUE'},
    ],
    INDEXES => [
      versions_product_id_idx => {FIELDS => [qw(product_id value)], TYPE => 'UNIQUE'},
    ],
  },

  milestones => {
    FIELDS => [
      id         => {TYPE => 'MEDIUMSERIAL', NOTNULL => 1, PRIMARYKEY => 1},
      product_id => {
        TYPE       => 'INT2',
        NOTNULL    => 1,
        REFERENCES => {TABLE => 'products', COLUMN => 'id', DELETE => 'CASCADE'}
      },
      value    => {TYPE => 'varchar(20)', NOTNULL => 1},
      sortkey  => {TYPE => 'INT2',        NOTNULL => 1, DEFAULT => 0},
      isactive => {TYPE => 'BOOLEAN',     NOTNULL => 1, DEFAULT => 'TRUE'},
    ],
    INDEXES => [
      milestones_product_id_idx =>
        {FIELDS => [qw(product_id value)], TYPE => 'UNIQUE'},
    ],
  },

  # Global Field Values
  # -------------------

  bug_type => {
    FIELDS  => dclone(FIELD_TABLE_SCHEMA->{FIELDS}),
    INDEXES => [
      bug_type_value_idx               => {FIELDS => ['value'], TYPE => 'UNIQUE'},
      bug_type_sortkey_idx             => ['sortkey',           'value'],
      bug_type_visibility_value_id_idx => ['visibility_value_id'],
    ],
  },

  bug_status => {
    FIELDS => [
      @{dclone(FIELD_TABLE_SCHEMA->{FIELDS})},
      is_open => {TYPE => 'BOOLEAN', NOTNULL => 1, DEFAULT => 'TRUE'},

    ],
    INDEXES => [
      bug_status_value_idx               => {FIELDS => ['value'], TYPE => 'UNIQUE'},
      bug_status_sortkey_idx             => ['sortkey',           'value'],
      bug_status_visibility_value_id_idx => ['visibility_value_id'],
    ],
  },

  resolution => {
    FIELDS  => dclone(FIELD_TABLE_SCHEMA->{FIELDS}),
    INDEXES => [
      resolution_value_idx               => {FIELDS => ['value'], TYPE => 'UNIQUE'},
      resolution_sortkey_idx             => ['sortkey',           'value'],
      resolution_visibility_value_id_idx => ['visibility_value_id'],
    ],
  },

  bug_severity => {
    FIELDS  => dclone(FIELD_TABLE_SCHEMA->{FIELDS}),
    INDEXES => [
      bug_severity_value_idx               => {FIELDS => ['value'], TYPE => 'UNIQUE'},
      bug_severity_sortkey_idx             => ['sortkey',           'value'],
      bug_severity_visibility_value_id_idx => ['visibility_value_id'],
    ],
  },

  priority => {
    FIELDS  => dclone(FIELD_TABLE_SCHEMA->{FIELDS}),
    INDEXES => [
      priority_value_idx               => {FIELDS => ['value'], TYPE => 'UNIQUE'},
      priority_sortkey_idx             => ['sortkey',           'value'],
      priority_visibility_value_id_idx => ['visibility_value_id'],
    ],
  },

  rep_platform => {
    FIELDS  => dclone(FIELD_TABLE_SCHEMA->{FIELDS}),
    INDEXES => [
      rep_platform_value_idx               => {FIELDS => ['value'], TYPE => 'UNIQUE'},
      rep_platform_sortkey_idx             => ['sortkey',           'value'],
      rep_platform_visibility_value_id_idx => ['visibility_value_id'],
    ],
  },

  op_sys => {
    FIELDS  => dclone(FIELD_TABLE_SCHEMA->{FIELDS}),
    INDEXES => [
      op_sys_value_idx               => {FIELDS => ['value'], TYPE => 'UNIQUE'},
      op_sys_sortkey_idx             => ['sortkey',           'value'],
      op_sys_visibility_value_id_idx => ['visibility_value_id'],
    ],
  },

  status_workflow => {
    FIELDS => [

      # On bug creation, there is no old value.
      old_status => {
        TYPE       => 'INT2',
        REFERENCES => {TABLE => 'bug_status', COLUMN => 'id', DELETE => 'CASCADE'}
      },
      new_status => {
        TYPE       => 'INT2',
        NOTNULL    => 1,
        REFERENCES => {TABLE => 'bug_status', COLUMN => 'id', DELETE => 'CASCADE'}
      },
      require_comment => {TYPE => 'INT1', NOTNULL => 1, DEFAULT => 0},
    ],
    INDEXES => [
      status_workflow_idx =>
        {FIELDS => ['old_status', 'new_status'], TYPE => 'UNIQUE'},
    ],
  },

  # USER INFO
  # ---------

  # General User Information
  # ------------------------

  profiles => {
    FIELDS => [
      userid         => {TYPE => 'MEDIUMSERIAL', NOTNULL => 1, PRIMARYKEY => 1},
      login_name     => {TYPE => 'varchar(255)', NOTNULL => 1},
      cryptpassword  => {TYPE => 'varchar(128)'},
      realname       => {TYPE => 'varchar(255)', NOTNULL => 1, DEFAULT => "''"},
      nickname       => {TYPE => 'varchar(255)', NOTNULL => 1, DEFAULT => "''"},
      disabledtext   => {TYPE => 'MEDIUMTEXT',   NOTNULL => 1, DEFAULT => "''"},
      disable_mail   => {TYPE => 'BOOLEAN',      NOTNULL => 1, DEFAULT => 'FALSE'},
      mybugslink     => {TYPE => 'BOOLEAN',      NOTNULL => 1, DEFAULT => 'TRUE'},
      extern_id      => {TYPE => 'varchar(64)'},
      is_enabled     => {TYPE => 'BOOLEAN',      NOTNULL => 1, DEFAULT => 'TRUE'},
      last_seen_date => {TYPE => 'DATETIME'},
      password_change_required =>
        {TYPE => 'BOOLEAN', NOTNULL => 1, DEFAULT => 'FALSE'},
      password_change_reason => {TYPE => 'varchar(64)'},
      mfa                    => {TYPE => 'varchar(8)', DEFAULT => "''"},
      mfa_required_date      => {TYPE => 'DATETIME'},
      forget_after_date      => {TYPE => 'DATETIME'},
      bounce_count           => {TYPE => 'INT1', NOTNULL => 1, DEFAULT => 0},
    ],
    INDEXES => [
      profiles_login_name_idx  => {FIELDS => ['login_name'], TYPE => 'UNIQUE'},
      profiles_extern_id_idx   => {FIELDS => ['extern_id'],  TYPE => 'UNIQUE'},
      profiles_nickname_idx    => ['nickname'],
      profiles_realname_ft_idx => {FIELDS => ['realname'],   TYPE => 'FULLTEXT'},
    ],
  },

  profile_search => {
    FIELDS => [
      id      => {TYPE => 'INTSERIAL', NOTNULL => 1, PRIMARYKEY => 1},
      user_id => {
        TYPE       => 'INT3',
        NOTNULL    => 1,
        REFERENCES => {TABLE => 'profiles', COLUMN => 'userid', DELETE => 'CASCADE'}
      },
      bug_list   => {TYPE => 'MEDIUMTEXT', NOTNULL => 1},
      list_order => {TYPE => 'MEDIUMTEXT'},
    ],
    INDEXES => [profile_search_user_id_idx => [qw(user_id)],],
  },

  profiles_activity => {
    FIELDS => [
      id     => {TYPE => 'MEDIUMSERIAL', NOTNULL => 1, PRIMARYKEY => 1},
      userid => {
        TYPE       => 'INT3',
        NOTNULL    => 1,
        REFERENCES => {TABLE => 'profiles', COLUMN => 'userid', DELETE => 'CASCADE'}
      },
      who => {
        TYPE       => 'INT3',
        NOTNULL    => 1,
        REFERENCES => {TABLE => 'profiles', COLUMN => 'userid'}
      },
      profiles_when => {TYPE => 'DATETIME', NOTNULL => 1},
      fieldid       => {
        TYPE       => 'INT3',
        NOTNULL    => 1,
        REFERENCES => {TABLE => 'fielddefs', COLUMN => 'id'}
      },
      oldvalue => {TYPE => 'TINYTEXT'},
      newvalue => {TYPE => 'TINYTEXT'},
    ],
    INDEXES => [
      profiles_activity_userid_idx        => ['userid'],
      profiles_activity_profiles_when_idx => ['profiles_when'],
      profiles_activity_fieldid_idx       => ['fieldid'],
    ],
  },

  profile_mfa => {
    FIELDS => [
      id      => {TYPE => 'INTSERIAL', NOTNULL => 1, PRIMARYKEY => 1},
      user_id => {
        TYPE       => 'INT3',
        NOTNULL    => 1,
        REFERENCES => {TABLE => 'profiles', COLUMN => 'userid', DELETE => 'CASCADE'}
      },
      name  => {TYPE => 'varchar(16)', NOTNULL => 1},
      value => {TYPE => 'varchar(255)'},
    ],
    INDEXES => [
      profile_mfa_userid_name_idx =>
        {FIELDS => ['user_id', 'name'], TYPE => 'UNIQUE'},
    ],
  },

  email_setting => {
    FIELDS => [
      user_id => {
        TYPE       => 'INT3',
        NOTNULL    => 1,
        REFERENCES => {TABLE => 'profiles', COLUMN => 'userid', DELETE => 'CASCADE'}
      },
      relationship => {TYPE => 'INT1', NOTNULL => 1},
      event        => {TYPE => 'INT1', NOTNULL => 1},
    ],
    INDEXES => [
      email_setting_user_id_idx =>
        {FIELDS => [qw(user_id relationship event)], TYPE => 'UNIQUE'},
    ],
  },

  email_bug_ignore => {
    FIELDS => [
      user_id => {
        TYPE       => 'INT3',
        NOTNULL    => 1,
        REFERENCES => {TABLE => 'profiles', COLUMN => 'userid', DELETE => 'CASCADE'}
      },
      bug_id => {
        TYPE       => 'INT3',
        NOTNULL    => 1,
        REFERENCES => {TABLE => 'bugs', COLUMN => 'bug_id', DELETE => 'CASCADE'}
      },
    ],
    INDEXES => [
      email_bug_ignore_user_id_idx =>
        {FIELDS => [qw(user_id bug_id)], TYPE => 'UNIQUE'},
    ],
  },

  watch => {
    FIELDS => [
      watcher => {
        TYPE       => 'INT3',
        NOTNULL    => 1,
        REFERENCES => {TABLE => 'profiles', COLUMN => 'userid', DELETE => 'CASCADE'}
      },
      watched => {
        TYPE       => 'INT3',
        NOTNULL    => 1,
        REFERENCES => {TABLE => 'profiles', COLUMN => 'userid', DELETE => 'CASCADE'}
      },
    ],
    INDEXES => [
      watch_watcher_idx => {FIELDS => [qw(watcher watched)], TYPE => 'UNIQUE'},
      watch_watched_idx => ['watched'],
    ],
  },

  namedqueries => {
    FIELDS => [
      id     => {TYPE => 'MEDIUMSERIAL', NOTNULL => 1, PRIMARYKEY => 1},
      userid => {
        TYPE       => 'INT3',
        NOTNULL    => 1,
        REFERENCES => {TABLE => 'profiles', COLUMN => 'userid', DELETE => 'CASCADE'}
      },
      name  => {TYPE => 'varchar(64)', NOTNULL => 1},
      query => {TYPE => 'LONGTEXT',    NOTNULL => 1},
    ],
    INDEXES =>
      [namedqueries_userid_idx => {FIELDS => [qw(userid name)], TYPE => 'UNIQUE'},],
  },

  namedqueries_link_in_footer => {
    FIELDS => [
      namedquery_id => {
        TYPE       => 'INT3',
        NOTNULL    => 1,
        REFERENCES => {TABLE => 'namedqueries', COLUMN => 'id', DELETE => 'CASCADE'}
      },
      user_id => {
        TYPE       => 'INT3',
        NOTNULL    => 1,
        REFERENCES => {TABLE => 'profiles', COLUMN => 'userid', DELETE => 'CASCADE'}
      },
    ],
    INDEXES => [
      namedqueries_link_in_footer_id_idx =>
        {FIELDS => [qw(namedquery_id user_id)], TYPE => 'UNIQUE'},
      namedqueries_link_in_footer_userid_idx => ['user_id'],
    ],
  },

  tag => {
    FIELDS => [
      id      => {TYPE => 'MEDIUMSERIAL', NOTNULL => 1, PRIMARYKEY => 1},
      name    => {TYPE => 'varchar(64)',  NOTNULL => 1},
      user_id => {
        TYPE       => 'INT3',
        NOTNULL    => 1,
        REFERENCES => {TABLE => 'profiles', COLUMN => 'userid', DELETE => 'CASCADE'}
      },
    ],
    INDEXES =>
      [tag_user_id_idx => {FIELDS => [qw(user_id name)], TYPE => 'UNIQUE'},],
  },

  bug_tag => {
    FIELDS => [
      bug_id => {
        TYPE       => 'INT3',
        NOTNULL    => 1,
        REFERENCES => {TABLE => 'bugs', COLUMN => 'bug_id', DELETE => 'CASCADE'}
      },
      tag_id => {
        TYPE       => 'INT3',
        NOTNULL    => 1,
        REFERENCES => {TABLE => 'tag', COLUMN => 'id', DELETE => 'CASCADE'}
      },
    ],
    INDEXES =>
      [bug_tag_bug_id_idx => {FIELDS => [qw(bug_id tag_id)], TYPE => 'UNIQUE'},],
  },

  component_cc => {

    FIELDS => [
      user_id => {
        TYPE       => 'INT3',
        NOTNULL    => 1,
        REFERENCES => {TABLE => 'profiles', COLUMN => 'userid', DELETE => 'CASCADE'}
      },
      component_id => {
        TYPE       => 'INT2',
        NOTNULL    => 1,
        REFERENCES => {TABLE => 'components', COLUMN => 'id', DELETE => 'CASCADE'}
      },
    ],
    INDEXES => [
      component_cc_user_id_idx =>
        {FIELDS => [qw(component_id user_id)], TYPE => 'UNIQUE'},
    ],
  },

  # Authentication
  # --------------

  logincookies => {
    FIELDS => [
      cookie => {TYPE => 'varchar(22)', NOTNULL => 1},
      userid => {
        TYPE       => 'INT3',
        NOTNULL    => 1,
        REFERENCES => {TABLE => 'profiles', COLUMN => 'userid', DELETE => 'CASCADE'}
      },
      ipaddr          => {TYPE => 'varchar(40)'},
      lastused        => {TYPE => 'DATETIME', NOTNULL => 1},
      id              => {TYPE => 'INTSERIAL', NOTNULL => 1, PRIMARYKEY => 1},
      restrict_ipaddr => {TYPE => 'BOOLEAN', NOTNULL => 1, DEFAULT => 0},
    ],
    INDEXES => [
      logincookies_lastused_idx => ['lastused'],
      logincookies_cookie_idx   => {FIELDS => ['cookie'], TYPE => 'UNIQUE'},
    ],
  },

  login_failure => {
    FIELDS => [
      user_id => {
        TYPE       => 'INT3',
        NOTNULL    => 1,
        REFERENCES => {TABLE => 'profiles', COLUMN => 'userid', DELETE => 'CASCADE'}
      },
      login_time => {TYPE => 'DATETIME',    NOTNULL => 1},
      ip_addr    => {TYPE => 'varchar(40)', NOTNULL => 1},
    ],
    INDEXES => [

      # We do lookups by every item in the table simultaneously, but
      # having an index with all three items would be the same size as
      # the table. So instead we have an index on just the smallest item,
      # to speed lookups.
      login_failure_user_id_idx => ['user_id'],
    ],
  },


  # "tokens" stores the tokens users receive when a password or email
  #     change is requested.  Tokens provide an extra measure of security
  #     for these changes.
  tokens => {
    FIELDS => [
      userid => {
        TYPE       => 'INT3',
        REFERENCES => {TABLE => 'profiles', COLUMN => 'userid', DELETE => 'CASCADE'}
      },
      issuedate => {TYPE => 'DATETIME',    NOTNULL => 1},
      token     => {TYPE => 'varchar(22)', NOTNULL => 1, PRIMARYKEY => 1},
      tokentype => {TYPE => 'varchar(16)', NOTNULL => 1},
      eventdata => {TYPE => 'TINYTEXT'},
    ],
    INDEXES => [tokens_userid_idx => ['userid'],],
  },

  token_data => {
    FIELDS => [
      id    => {TYPE => 'INTSERIAL', NOTNULL => 1, PRIMARYKEY => 1},
      token => {
        TYPE       => 'varchar(22)',
        NOTNULL    => 1,
        REFERENCES => {TABLE => 'tokens', COLUMN => 'token', DELETE => 'CASCADE'}
      },
      extra_data => {TYPE => 'MEDIUMTEXT', NOTNULL => 1},
    ],
    INDEXES => [token_data_idx => {FIELDS => ['token'], TYPE => 'UNIQUE'},],
  },

  # GROUPS
  # ------

  groups => {
    FIELDS => [
      id          => {TYPE => 'MEDIUMSERIAL', NOTNULL => 1, PRIMARYKEY => 1},
      name        => {TYPE => 'varchar(255)', NOTNULL => 1},
      description => {TYPE => 'MEDIUMTEXT',   NOTNULL => 1},
      isbuggroup  => {TYPE => 'BOOLEAN',      NOTNULL => 1},
      userregexp  => {TYPE => 'TINYTEXT',     NOTNULL => 1, DEFAULT => "''"},
      isactive    => {TYPE => 'BOOLEAN',      NOTNULL => 1, DEFAULT => 'TRUE'},
      icon_url    => {TYPE => 'TINYTEXT'},
      owner_user_id =>
        {TYPE => 'INT3', REFERENCES => {TABLE => 'profiles', COLUMN => 'userid'}},
      idle_member_removal => {TYPE => 'INT2', NOTNULL => 1, DEFAULT => '0'}
    ],
    INDEXES => [groups_name_idx => {FIELDS => ['name'], TYPE => 'UNIQUE'},],
  },

  group_control_map => {
    FIELDS => [
      group_id => {
        TYPE       => 'INT3',
        NOTNULL    => 1,
        REFERENCES => {TABLE => 'groups', COLUMN => 'id', DELETE => 'CASCADE'}
      },
      product_id => {
        TYPE       => 'INT2',
        NOTNULL    => 1,
        REFERENCES => {TABLE => 'products', COLUMN => 'id', DELETE => 'CASCADE'}
      },
      entry          => {TYPE => 'BOOLEAN', NOTNULL => 1, DEFAULT => 'FALSE'},
      membercontrol  => {TYPE => 'INT1',    NOTNULL => 1, DEFAULT => CONTROLMAPNA},
      othercontrol   => {TYPE => 'INT1',    NOTNULL => 1, DEFAULT => CONTROLMAPNA},
      canedit        => {TYPE => 'BOOLEAN', NOTNULL => 1, DEFAULT => 'FALSE'},
      editcomponents => {TYPE => 'BOOLEAN', NOTNULL => 1, DEFAULT => 'FALSE'},
      editbugs       => {TYPE => 'BOOLEAN', NOTNULL => 1, DEFAULT => 'FALSE'},
      canconfirm     => {TYPE => 'BOOLEAN', NOTNULL => 1, DEFAULT => 'FALSE'},
    ],
    INDEXES => [
      group_control_map_product_id_idx =>
        {FIELDS => [qw(product_id group_id)], TYPE => 'UNIQUE'},
      group_control_map_group_id_idx => ['group_id'],
    ],
  },

  # "user_group_map" determines the groups that a user belongs to
  # directly or due to regexp and which groups can be blessed by a user.
  #
  # grant_type:
  # if GRANT_DIRECT - record was explicitly granted
  # if GRANT_DERIVED - record was derived from expanding a group hierarchy
  # if GRANT_REGEXP - record was created by evaluating a regexp
  user_group_map => {
    FIELDS => [
      user_id => {
        TYPE       => 'INT3',
        NOTNULL    => 1,
        REFERENCES => {TABLE => 'profiles', COLUMN => 'userid', DELETE => 'CASCADE'}
      },
      group_id => {
        TYPE       => 'INT3',
        NOTNULL    => 1,
        REFERENCES => {TABLE => 'groups', COLUMN => 'id', DELETE => 'CASCADE'}
      },
      isbless    => {TYPE => 'BOOLEAN', NOTNULL => 1, DEFAULT => 'FALSE'},
      grant_type => {TYPE => 'INT1',    NOTNULL => 1, DEFAULT => GRANT_DIRECT},
    ],
    INDEXES => [
      user_group_map_user_id_idx =>
        {FIELDS => [qw(user_id group_id grant_type isbless)], TYPE => 'UNIQUE'},
    ],
  },

  # This table determines which groups are made a member of another
  # group, given the ability to bless another group, or given
  # visibility to another groups existence and membership
  # grant_type:
  # if GROUP_MEMBERSHIP - member groups are made members of grantor
  # if GROUP_BLESS - member groups may grant membership in grantor
  # if GROUP_VISIBLE - member groups may see grantor group
  group_group_map => {
    FIELDS => [
      member_id => {
        TYPE       => 'INT3',
        NOTNULL    => 1,
        REFERENCES => {TABLE => 'groups', COLUMN => 'id', DELETE => 'CASCADE'}
      },
      grantor_id => {
        TYPE       => 'INT3',
        NOTNULL    => 1,
        REFERENCES => {TABLE => 'groups', COLUMN => 'id', DELETE => 'CASCADE'}
      },
      grant_type => {TYPE => 'INT1', NOTNULL => 1, DEFAULT => GROUP_MEMBERSHIP},
    ],
    INDEXES => [
      group_group_map_member_id_idx =>
        {FIELDS => [qw(member_id grantor_id grant_type)], TYPE => 'UNIQUE'},
    ],
  },

  # This table determines which groups a user must be a member of
  # in order to see a bug.
  bug_group_map => {
    FIELDS => [
      bug_id => {
        TYPE       => 'INT3',
        NOTNULL    => 1,
        REFERENCES => {TABLE => 'bugs', COLUMN => 'bug_id', DELETE => 'CASCADE'}
      },
      group_id => {
        TYPE       => 'INT3',
        NOTNULL    => 1,
        REFERENCES => {TABLE => 'groups', COLUMN => 'id', DELETE => 'CASCADE'}
      },
    ],
    INDEXES => [
      bug_group_map_bug_id_idx => {FIELDS => [qw(bug_id group_id)], TYPE => 'UNIQUE'},
      bug_group_map_group_id_idx => ['group_id'],
    ],
  },

  # This table determines which groups a user must be a member of
  # in order to see a named query somebody else shares.
  namedquery_group_map => {
    FIELDS => [
      namedquery_id => {
        TYPE       => 'INT3',
        NOTNULL    => 1,
        REFERENCES => {TABLE => 'namedqueries', COLUMN => 'id', DELETE => 'CASCADE'}
      },
      group_id => {
        TYPE       => 'INT3',
        NOTNULL    => 1,
        REFERENCES => {TABLE => 'groups', COLUMN => 'id', DELETE => 'CASCADE'}
      },
    ],
    INDEXES => [
      namedquery_group_map_namedquery_id_idx =>
        {FIELDS => [qw(namedquery_id)], TYPE => 'UNIQUE'},
      namedquery_group_map_group_id_idx => ['group_id'],
    ],
  },

  category_group_map => {
    FIELDS => [
      category_id => {
        TYPE    => 'INT2',
        NOTNULL => 1,
        REFERENCES =>
          {TABLE => 'series_categories', COLUMN => 'id', DELETE => 'CASCADE'}
      },
      group_id => {
        TYPE       => 'INT3',
        NOTNULL    => 1,
        REFERENCES => {TABLE => 'groups', COLUMN => 'id', DELETE => 'CASCADE'}
      },
    ],
    INDEXES => [
      category_group_map_category_id_idx =>
        {FIELDS => [qw(category_id group_id)], TYPE => 'UNIQUE'},
    ],
  },


  # PRODUCTS
  # --------

  classifications => {
    FIELDS => [
      id          => {TYPE => 'SMALLSERIAL', NOTNULL => 1, PRIMARYKEY => 1},
      name        => {TYPE => 'varchar(64)', NOTNULL => 1},
      description => {TYPE => 'MEDIUMTEXT'},
      sortkey     => {TYPE => 'INT2',        NOTNULL => 1, DEFAULT => '0'},
    ],
    INDEXES =>
      [classifications_name_idx => {FIELDS => ['name'], TYPE => 'UNIQUE'},],
  },

  products => {
    FIELDS => [
      id                => {TYPE => 'SMALLSERIAL', NOTNULL => 1, PRIMARYKEY => 1},
      name              => {TYPE => 'varchar(64)', NOTNULL => 1},
      classification_id => {
        TYPE       => 'INT2',
        NOTNULL    => 1,
        DEFAULT    => '1',
        REFERENCES => {TABLE => 'classifications', COLUMN => 'id', DELETE => 'CASCADE'}
      },
      description        => {TYPE => 'MEDIUMTEXT',  NOTNULL => 1},
      isactive           => {TYPE => 'BOOLEAN',     NOTNULL => 1, DEFAULT => 1},
      defaultmilestone   => {TYPE => 'varchar(20)', NOTNULL => 1, DEFAULT => "'---'"},
      allows_unconfirmed => {TYPE => 'BOOLEAN',     NOTNULL => 1, DEFAULT => 'TRUE'},
      bug_description_template => {TYPE => 'MEDIUMTEXT'},
      default_bug_type  => {TYPE => 'varchar(20)'},
    ],
    INDEXES => [products_name_idx => {FIELDS => ['name'], TYPE => 'UNIQUE'},],
  },

  components => {
    FIELDS => [
      id         => {TYPE => 'SMALLSERIAL', NOTNULL => 1, PRIMARYKEY => 1},
      name       => {TYPE => 'varchar(64)', NOTNULL => 1},
      product_id => {
        TYPE       => 'INT2',
        NOTNULL    => 1,
        REFERENCES => {TABLE => 'products', COLUMN => 'id', DELETE => 'CASCADE'}
      },
      initialowner => {
        TYPE       => 'INT3',
        NOTNULL    => 1,
        REFERENCES => {TABLE => 'profiles', COLUMN => 'userid'}
      },
      initialqacontact => {
        TYPE       => 'INT3',
        REFERENCES => {TABLE => 'profiles', COLUMN => 'userid', DELETE => 'SET NULL'}
      },
      description => {TYPE => 'MEDIUMTEXT', NOTNULL => 1},
      isactive    => {TYPE => 'BOOLEAN',    NOTNULL => 1, DEFAULT => 'TRUE'},
      triage_owner_id => {
        TYPE       => 'INT3',
        REFERENCES => {TABLE => 'profiles', COLUMN => 'userid', DELETE => 'SET NULL'}
      },
      bug_description_template => {TYPE => 'MEDIUMTEXT'},
      default_bug_type  => {TYPE => 'varchar(20)'},
    ],
    INDEXES => [
      components_product_id_idx =>
        {FIELDS => [qw(product_id name)], TYPE => 'UNIQUE'},
      components_name_idx => ['name'],
    ],
  },

  # CHARTS
  # ------

  series => {
    FIELDS => [
      series_id => {TYPE => 'MEDIUMSERIAL', NOTNULL => 1, PRIMARYKEY => 1},
      creator   => {
        TYPE       => 'INT3',
        REFERENCES => {TABLE => 'profiles', COLUMN => 'userid', DELETE => 'CASCADE'}
      },
      category => {
        TYPE    => 'INT2',
        NOTNULL => 1,
        REFERENCES =>
          {TABLE => 'series_categories', COLUMN => 'id', DELETE => 'CASCADE'}
      },
      subcategory => {
        TYPE    => 'INT2',
        NOTNULL => 1,
        REFERENCES =>
          {TABLE => 'series_categories', COLUMN => 'id', DELETE => 'CASCADE'}
      },
      name      => {TYPE => 'varchar(64)', NOTNULL => 1},
      frequency => {TYPE => 'INT2',        NOTNULL => 1},
      query     => {TYPE => 'MEDIUMTEXT',  NOTNULL => 1},
      is_public => {TYPE => 'BOOLEAN',     NOTNULL => 1, DEFAULT => 'FALSE'},
    ],
    INDEXES => [
      series_creator_idx => ['creator'],
      series_category_idx =>
        {FIELDS => [qw(category subcategory name)], TYPE => 'UNIQUE'},
    ],
  },

  series_data => {
    FIELDS => [
      series_id => {
        TYPE       => 'INT3',
        NOTNULL    => 1,
        REFERENCES => {TABLE => 'series', COLUMN => 'series_id', DELETE => 'CASCADE'}
      },
      series_date  => {TYPE => 'DATETIME', NOTNULL => 1},
      series_value => {TYPE => 'INT3',     NOTNULL => 1},
    ],
    INDEXES => [
      series_data_series_id_idx =>
        {FIELDS => [qw(series_id series_date)], TYPE => 'UNIQUE'},
    ],
  },

  series_categories => {
    FIELDS => [
      id   => {TYPE => 'SMALLSERIAL', NOTNULL => 1, PRIMARYKEY => 1},
      name => {TYPE => 'varchar(64)', NOTNULL => 1},
    ],
    INDEXES =>
      [series_categories_name_idx => {FIELDS => ['name'], TYPE => 'UNIQUE'},],
  },

  # WHINE SYSTEM
  # ------------

  whine_queries => {
    FIELDS => [
      id      => {TYPE => 'MEDIUMSERIAL', PRIMARYKEY => 1, NOTNULL => 1},
      eventid => {
        TYPE       => 'INT3',
        NOTNULL    => 1,
        REFERENCES => {TABLE => 'whine_events', COLUMN => 'id', DELETE => 'CASCADE'}
      },
      query_name    => {TYPE => 'varchar(64)',  NOTNULL => 1, DEFAULT => "''"},
      sortkey       => {TYPE => 'INT2',         NOTNULL => 1, DEFAULT => '0'},
      onemailperbug => {TYPE => 'BOOLEAN',      NOTNULL => 1, DEFAULT => 'FALSE'},
      title         => {TYPE => 'varchar(128)', NOTNULL => 1, DEFAULT => "''"},
    ],
    INDEXES => [whine_queries_eventid_idx => ['eventid'],],
  },

  whine_schedules => {
    FIELDS => [
      id      => {TYPE => 'MEDIUMSERIAL', PRIMARYKEY => 1, NOTNULL => 1},
      eventid => {
        TYPE       => 'INT3',
        NOTNULL    => 1,
        REFERENCES => {TABLE => 'whine_events', COLUMN => 'id', DELETE => 'CASCADE'}
      },
      run_day     => {TYPE => 'varchar(32)'},
      run_time    => {TYPE => 'varchar(32)'},
      run_next    => {TYPE => 'DATETIME'},
      mailto      => {TYPE => 'INT3', NOTNULL => 1},
      mailto_type => {TYPE => 'INT2', NOTNULL => 1, DEFAULT => '0'},
    ],
    INDEXES => [
      whine_schedules_run_next_idx => ['run_next'],
      whine_schedules_eventid_idx  => ['eventid'],
    ],
  },

  whine_events => {
    FIELDS => [
      id           => {TYPE => 'MEDIUMSERIAL', PRIMARYKEY => 1, NOTNULL => 1},
      owner_userid => {
        TYPE       => 'INT3',
        NOTNULL    => 1,
        REFERENCES => {TABLE => 'profiles', COLUMN => 'userid', DELETE => 'CASCADE'}
      },
      subject      => {TYPE => 'varchar(128)'},
      body         => {TYPE => 'MEDIUMTEXT'},
      mailifnobugs => {TYPE => 'BOOLEAN', NOTNULL => 1, DEFAULT => 'FALSE'},
    ],
  },

  # QUIPS
  # -----

  quips => {
    FIELDS => [
      quipid => {TYPE => 'MEDIUMSERIAL', NOTNULL => 1, PRIMARYKEY => 1},
      userid => {
        TYPE       => 'INT3',
        REFERENCES => {TABLE => 'profiles', COLUMN => 'userid', DELETE => 'SET NULL'}
      },
      quip     => {TYPE => 'MEDIUMTEXT', NOTNULL => 1},
      approved => {TYPE => 'BOOLEAN',    NOTNULL => 1, DEFAULT => 'TRUE'},
    ],
  },

  # SETTINGS
  # --------
  # setting          - each global setting will have exactly one entry
  #                    in this table.
  # setting_value    - stores the list of acceptable values for each
  #                    setting, and a sort index that controls the order
  #                    in which the values are displayed.
  # profile_setting  - If a user has chosen to use a value other than the
  #                    global default for a given setting, it will be
  #                    stored in this table. Note: even if a setting is
  #                    later changed so is_enabled = false, the stored
  #                    value will remain in case it is ever enabled again.
  #
  setting => {
    FIELDS => [
      name          => {TYPE => 'varchar(32)', NOTNULL => 1, PRIMARYKEY => 1},
      default_value => {TYPE => 'varchar(32)', NOTNULL => 1},
      is_enabled    => {TYPE => 'BOOLEAN',     NOTNULL => 1, DEFAULT => 'TRUE'},
      subclass      => {TYPE => 'varchar(32)'},
      category      => {TYPE => 'varchar(64)', NOTNULL => 1, DEFAULT => "'General'"}
    ],
  },

  setting_value => {
    FIELDS => [
      name => {
        TYPE       => 'varchar(32)',
        NOTNULL    => 1,
        REFERENCES => {TABLE => 'setting', COLUMN => 'name', DELETE => 'CASCADE'}
      },
      value     => {TYPE => 'varchar(32)', NOTNULL => 1},
      sortindex => {TYPE => 'INT2',        NOTNULL => 1},
    ],
    INDEXES => [
      setting_value_nv_unique_idx => {FIELDS => [qw(name value)], TYPE => 'UNIQUE'},
      setting_value_ns_unique_idx =>
        {FIELDS => [qw(name sortindex)], TYPE => 'UNIQUE'},
    ],
  },

  profile_setting => {
    FIELDS => [
      user_id => {
        TYPE       => 'INT3',
        NOTNULL    => 1,
        REFERENCES => {TABLE => 'profiles', COLUMN => 'userid', DELETE => 'CASCADE'}
      },
      setting_name => {
        TYPE       => 'varchar(32)',
        NOTNULL    => 1,
        REFERENCES => {TABLE => 'setting', COLUMN => 'name', DELETE => 'CASCADE'}
      },
      setting_value => {TYPE => 'varchar(32)', NOTNULL => 1},
    ],
    INDEXES => [
      profile_setting_value_unique_idx =>
        {FIELDS => [qw(user_id setting_name)], TYPE => 'UNIQUE'},
    ],
  },

  email_rates => {
    FIELDS => [
      id         => {TYPE => 'INTSERIAL',    NOTNULL => 1, PRIMARYKEY => 1},
      recipient  => {TYPE => 'varchar(255)', NOTNULL => 1},
      message_ts => {TYPE => 'DATETIME',     NOTNULL => 1},
    ],
    INDEXES => [
      email_rates_idx            => [qw(recipient message_ts)],
      email_rates_message_ts_idx => ['message_ts'],
    ],
  },

  # THESCHWARTZ TABLES
  # ------------------
  # Note: In the standard TheSchwartz schema, most integers are unsigned,
  # but we didn't implement unsigned ints for Bugzilla schemas, so we
  # just create signed ints, which should be fine.

  ts_funcmap => {
    FIELDS => [
      funcid   => {TYPE => 'INTSERIAL',    PRIMARYKEY => 1, NOTNULL => 1},
      funcname => {TYPE => 'varchar(255)', NOTNULL    => 1},
    ],
    INDEXES =>
      [ts_funcmap_funcname_idx => {FIELDS => ['funcname'], TYPE => 'UNIQUE'},],
  },

  ts_job => {
    FIELDS => [

      # In a standard TheSchwartz schema, this is a BIGINT, but we
      # don't have those and I didn't want to add them just for this.
      jobid  => {TYPE => 'INTSERIAL', PRIMARYKEY => 1, NOTNULL => 1},
      funcid => {TYPE => 'INT4',      NOTNULL    => 1},

      # In standard TheSchwartz, this is a MEDIUMBLOB.
      arg           => {TYPE => 'LONGBLOB'},
      uniqkey       => {TYPE => 'varchar(255)'},
      insert_time   => {TYPE => 'INT4'},
      run_after     => {TYPE => 'INT4', NOTNULL => 1},
      grabbed_until => {TYPE => 'INT4', NOTNULL => 1},
      priority      => {TYPE => 'INT2'},
      coalesce      => {TYPE => 'varchar(255)'},
    ],
    INDEXES => [
      ts_job_funcid_idx => {FIELDS => [qw(funcid uniqkey)], TYPE => 'UNIQUE'},

      # In a standard TheSchewartz schema, these both go in the other
      # direction, but there's no reason to have three indexes that
      # all start with the same column, and our naming scheme doesn't
      # allow it anyhow.
      ts_job_run_after_idx => [qw(run_after funcid)],
      ts_job_coalesce_idx  => [qw(coalesce funcid)],
    ],
  },

  ts_note => {
    FIELDS => [

      # This is a BIGINT in standard TheSchwartz schemas.
      jobid   => {TYPE => 'INT4', NOTNULL => 1},
      notekey => {TYPE => 'varchar(255)'},
      value   => {TYPE => 'LONGBLOB'},
    ],
    INDEXES =>
      [ts_note_jobid_idx => {FIELDS => [qw(jobid notekey)], TYPE => 'UNIQUE'},],
  },

  ts_error => {
    FIELDS => [
      error_time => {TYPE => 'INT4',         NOTNULL => 1},
      jobid      => {TYPE => 'INT4',         NOTNULL => 1},
      message    => {TYPE => 'varchar(255)', NOTNULL => 1},
      funcid     => {TYPE => 'INT4',         NOTNULL => 1, DEFAULT => 0},
    ],
    INDEXES => [
      ts_error_funcid_idx     => [qw(funcid error_time)],
      ts_error_error_time_idx => ['error_time'],
      ts_error_jobid_idx      => ['jobid'],
    ],
  },

  ts_exitstatus => {
    FIELDS => [
      jobid           => {TYPE => 'INTSERIAL', PRIMARYKEY => 1, NOTNULL => 1},
      funcid          => {TYPE => 'INT4',      NOTNULL    => 1, DEFAULT => 0},
      status          => {TYPE => 'INT2'},
      completion_time => {TYPE => 'INT4'},
      delete_after    => {TYPE => 'INT4'},
    ],
    INDEXES => [
      ts_exitstatus_funcid_idx       => ['funcid'],
      ts_exitstatus_delete_after_idx => ['delete_after'],
    ],
  },

  # SCHEMA STORAGE
  # --------------

  bz_schema => {
    FIELDS => [
      schema_data => {TYPE => 'LONGBLOB',     NOTNULL => 1},
      version     => {TYPE => 'decimal(3,2)', NOTNULL => 1},
    ],
  },

  bug_user_last_visit => {
    FIELDS => [
      id      => {TYPE => 'INTSERIAL', NOTNULL => 1, PRIMARYKEY => 1},
      user_id => {
        TYPE       => 'INT3',
        NOTNULL    => 1,
        REFERENCES => {TABLE => 'profiles', COLUMN => 'userid', DELETE => 'CASCADE'}
      },
      bug_id => {
        TYPE       => 'INT3',
        NOTNULL    => 1,
        REFERENCES => {TABLE => 'bugs', COLUMN => 'bug_id', DELETE => 'CASCADE'}
      },
      last_visit_ts => {TYPE => 'DATETIME', NOTNULL => 1},
    ],
    INDEXES => [
      bug_user_last_visit_idx => {FIELDS => ['user_id', 'bug_id'], TYPE => 'UNIQUE'},
      bug_user_last_visit_last_visit_ts_idx => ['last_visit_ts'],
    ],
  },

  user_api_keys => {
    FIELDS => [
      id      => {TYPE => 'INTSERIAL', NOTNULL => 1, PRIMARYKEY => 1},
      user_id => {
        TYPE       => 'INT3',
        NOTNULL    => 1,
        REFERENCES => {TABLE => 'profiles', COLUMN => 'userid', DELETE => 'CASCADE'}
      },
      api_key      => {TYPE => 'varchar(40)', NOTNULL => 1},
      description  => {TYPE => 'varchar(255)'},
      revoked      => {TYPE => 'BOOLEAN', NOTNULL => 1, DEFAULT => 'FALSE'},
      creation_ts  => {TYPE => 'DATETIME', NOTNULL => 1},
      last_used    => {TYPE => 'DATETIME'},
      last_used_ip => {TYPE => 'varchar(40)'},
      app_id       => {TYPE => 'varchar(64)'},
      sticky       => {TYPE => 'BOOLEAN', NOTNULL => 1, DEFAULT => 'FALSE'}
    ],
    INDEXES => [
      user_api_keys_api_key_idx        => {FIELDS => ['api_key'], TYPE => 'UNIQUE'},
      user_api_keys_user_id_idx        => ['user_id'],
      user_api_keys_user_id_app_id_idx => ['user_id', 'app_id'],
    ],
  },

  user_request_log => {
    FIELDS => [
      id          => {TYPE => 'INTSERIAL',   NOTNULL => 1, PRIMARYKEY => 1},
      user_id     => {TYPE => 'INT3',        NOTNULL => 1},
      ip_address  => {TYPE => 'varchar(40)', NOTNULL => 1},
      user_agent  => {TYPE => 'TINYTEXT',    NOTNULL => 1},
      timestamp   => {TYPE => 'DATETIME',    NOTNULL => 1},
      bug_id      => {TYPE => 'INT3',        NOTNULL => 0},
      attach_id   => {TYPE => 'INT5',        NOTNULL => 0},
      request_url => {TYPE => 'TINYTEXT',    NOTNULL => 1},
      method      => {TYPE => 'TINYTEXT',    NOTNULL => 1},
      action      => {TYPE => 'varchar(20)', NOTNULL => 1},
      server      => {TYPE => 'varchar(7)',  NOTNULL => 1},
    ],
    INDEXES => [user_user_request_log_user_id_idx => ['user_id'],],
  },

  # OAuth2 Tables
  # -------------

  oauth2_client => {
    FIELDS => [
      id            => {TYPE => 'INTSERIAL',    NOTNULL => 1, PRIMARYKEY => 1},
      client_id     => {TYPE => 'varchar(255)', NOTNULL => 1},
      description   => {TYPE => 'varchar(255)', NOTNULL => 1},
      secret        => {TYPE => 'varchar(255)', NOTNULL => 1},
      active        => {TYPE => 'BOOLEAN',      NOTNULL => 1, DEFAULT => 'TRUE'},
      last_modified => {TYPE => 'DATETIME'},
    ],
  },

  oauth2_scope => {
    FIELDS => [
      id          => {TYPE => 'INTSERIAL',    NOTNULL => 1, PRIMARYKEY => 1},
      name        => {TYPE => 'varchar(255)', NOTNULL => 1},
      description => {TYPE => 'TINYTEXT',     NOTNULL => 1},
    ],
    INDEXES => [
      oauth2_scope_idx =>
        {FIELDS => ['name'], TYPE => 'UNIQUE'},
    ],
  },

  oauth2_client_scope => {
    FIELDS => [
      id        => {TYPE => 'INTSERIAL', NOTNULL => 1, PRIMARYKEY => 1},
      client_id => {
        TYPE       => 'INT4',
        NOTNULL    => 1,
        REFERENCES => {
          TABLE  => 'oauth2_client',
          COLUMN => 'id',
          UPDATE => 'CASCADE',
          DELETE => 'CASCADE',
        }
      },
      scope_id => {
        TYPE       => 'INT4',
        NOTNULL    => 1,
        REFERENCES => {
          TABLE  => 'oauth2_scope',
          COLUMN => 'id',
          UPDATE => 'CASCADE',
          DELETE => 'CASCADE',
        },
      },
    ],
    INDEXES => [
      oauth2_client_scope_idx =>
        {FIELDS => ['client_id', 'scope_id'], TYPE => 'UNIQUE'},
    ],
  },

  oauth2_jwt => {
    FIELDS => [
      id      => {TYPE => 'INTSERIAL', NOTNULL => 1, PRIMARYKEY => 1},
      jti     => {TYPE => 'varchar(255)', NOTNULL => 1},
      type    => {TYPE => 'INT2', NOTNULL => 1},
      client_id => {
        TYPE       => 'INT4',
        NOTNULL    => 1,
        REFERENCES => {
          TABLE  => 'oauth2_client',
          COLUMN => 'id',
          UPDATE => 'CASCADE',
          DELETE => 'CASCADE',
        }
      },
      user_id => {
        TYPE       => 'INT3',
        NOTNULL    => 1,
        REFERENCES => {
          TABLE  => 'profiles',
          COLUMN => 'userid',
          UPDATE => 'CASCADE',
          DELETE => 'CASCADE',
        },
      },
      expires => {TYPE => 'DATETIME'},
    ],
    INDEXES => [
      oauth2_jwt_jti_type_idx => {FIELDS => [qw(jti type)], TYPE => 'UNIQUE'},
    ],
  },

  # Report Ping Table
  # -----------------

  report_ping => {
    FIELDS => [
      id           => {TYPE => 'INTSERIAL', NOTNULL => 1, PRIMARYKEY => 1},
      class        => {TYPE => 'varchar(255)', NOTNULL => 1},
      last_ping_ts => {TYPE => 'DATETIME', NOTNULL => 1},
    ]
  }

};

# Foreign Keys are added in Bugzilla::DB::bz_add_field_tables
use constant MULTI_SELECT_VALUE_TABLE => {
  FIELDS => [
    bug_id => {TYPE => 'INT3',        NOTNULL => 1},
    value  => {TYPE => 'varchar(64)', NOTNULL => 1},
  ],
  INDEXES => [bug_id_idx => {FIELDS => [qw( bug_id value)], TYPE => 'UNIQUE'},],
};


has 'db' => (is => 'ro', required => 1, weak_ref => 1);

has 'abstract_schema' => (is => 'lazy');

sub _build_abstract_schema {

  # While ABSTRACT_SCHEMA cannot be modified, $abstract_schema can be.
  # So, we dclone it to prevent anything from mucking with the constant.
  my $abstract_schema = dclone(ABSTRACT_SCHEMA);

  # Let extensions add tables, but make sure they can't modify existing
  # tables. If we don't lock/unlock keys, lock_value complains.
  lock_keys(%$abstract_schema);
  foreach my $table (keys %{ABSTRACT_SCHEMA()}) {
    lock_value(%$abstract_schema, $table) if exists $abstract_schema->{$table};
  }
  unlock_keys(%$abstract_schema);
  Bugzilla::Hook::process('db_schema_abstract_schema',
    {schema => $abstract_schema});
  unlock_hash(%$abstract_schema);

  return $abstract_schema;
}

has 'schema' => (is => 'lazy');
sub _build_schema {
  my ($self) = @_;
  return dclone($self->abstract_schema);
}

sub BUILD {
  my $self = shift;

  $self->_adjust_schema;
};

has 'db_specific' => (is => 'lazy');

#--------------------------------------------------------------------------
sub _adjust_schema {

  my $self = shift;
  my $schema = $self->schema;

  # The _initialize method has already set up the db_specific hash with
  # the information on how to implement the abstract data types for the
  # instantiated DBMS-specific subclass.
  my $db_specific = $self->db_specific;

  # Loop over each table in the abstract database schema.
  foreach my $table (keys %$schema) {
    my %fields = (@{$schema->{$table}{FIELDS}});

    # Loop over the field definitions in each table.
    foreach my $field_def (values %fields) {

      # If the field type is an abstract data type defined in the
      # $db_specific hash, replace it with the DBMS-specific data type
      # that implements it.
      if (exists($db_specific->{$field_def->{TYPE}})) {
        $field_def->{TYPE} = $db_specific->{$field_def->{TYPE}};
      }

      # Replace abstract default values (such as 'TRUE' and 'FALSE')
      # with their database-specific implementations.
      if ( exists($field_def->{DEFAULT})
        && exists($db_specific->{$field_def->{DEFAULT}}))
      {
        $field_def->{DEFAULT} = $db_specific->{$field_def->{DEFAULT}};
      }
    }
  }

  return $self;

}    #eosub--_adjust_schema

#--------------------------------------------------------------------------
sub get_type_ddl {

  my $self  = shift;
  my $finfo = (@_ == 1 && ref($_[0]) eq 'HASH') ? $_[0] : {@_};
  my $type  = $finfo->{TYPE};
  confess "A valid TYPE was not specified for this column (got "
    . Dumper($finfo) . ")"
    unless ($type);

  my $default = $finfo->{DEFAULT};

  # Replace any abstract default value (such as 'TRUE' or 'FALSE')
  # with its database-specific implementation.
  if (defined $default && exists($self->{db_specific}->{$default})) {
    $default = $self->{db_specific}->{$default};
  }

  my $type_ddl = $self->convert_type($type);

  # DEFAULT attribute must appear before any column constraints
  # (e.g., NOT NULL), for Oracle
  $type_ddl .= " DEFAULT $default" if (defined($default));

  # PRIMARY KEY must appear before NOT NULL for SQLite.
  $type_ddl .= " PRIMARY KEY" if ($finfo->{PRIMARYKEY});
  $type_ddl .= " NOT NULL"    if ($finfo->{NOTNULL});

  return ($type_ddl);

}    #eosub--get_type_ddl


sub get_fk_ddl {

  my ($self, $table, $column, $references) = @_;
  return "" if !$references;

  my $update    = $references->{UPDATE} || 'CASCADE';
  my $delete    = $references->{DELETE} || 'RESTRICT';
  my $to_table  = $references->{TABLE}  || confess "No table in reference";
  my $to_column = $references->{COLUMN} || confess "No column in reference";
  my $fk_name = $self->_get_fk_name($table, $column, $references);

  my $q = $self->db->quote_expr;
  return
      "\n     CONSTRAINT $q->{$fk_name} FOREIGN KEY ($q->{$column})\n"
    . "     REFERENCES $q->{$to_table}($q->{$to_column})\n"
    . "      ON UPDATE $update ON DELETE $delete";
}

# Generates a name for a Foreign Key. It's separate from get_fk_ddl
# so that certain databases can override it (for shorter identifiers or
# other reasons).
sub _get_fk_name {
  my ($self, $table, $column, $references) = @_;
  my $to_table  = $references->{TABLE};
  my $to_column = $references->{COLUMN};
  my $name      = "fk_${table}_${column}_${to_table}_${to_column}";

  if (length($name) > $self->MAX_IDENTIFIER_LEN) {
    $name = 'fk_' . $self->_hash_identifier($name);
  }

  return $name;
}

sub _hash_identifier {
  my ($invocant, $value) = @_;

  # We do -7 to allow prefixes like "idx_" or "fk_", or perhaps something
  # longer in the future.
  return substr(md5_hex($value), 0, $invocant->MAX_IDENTIFIER_LEN - 7);
}


sub get_add_fks_sql {
  my ($self, $table, $column_fks) = @_;

  my @add = $self->_column_fks_to_ddl($table, $column_fks);

  my $q = $self->db->quote_expr;
  my @sql;
  if ($self->MULTIPLE_FKS_IN_ALTER) {
    my $alter = "ALTER TABLE $q->{$table} ADD " . join(', ADD ', @add);
    push(@sql, $alter);
  }
  else {
    foreach my $fk_string (@add) {
      push(@sql, "ALTER TABLE $q->{$table} ADD $fk_string");
    }
  }
  return @sql;
}

sub _column_fks_to_ddl {
  my ($self, $table, $column_fks) = @_;
  my @ddl;
  foreach my $column (keys %$column_fks) {
    my $def = $column_fks->{$column};
    my $fk_string = $self->get_fk_ddl($table, $column, $def);
    push(@ddl, $fk_string);
  }
  return @ddl;
}

sub get_drop_fk_sql {
  my ($self, $table, $column, $references) = @_;
  my $fk_name = $self->_get_fk_name($table, $column, $references);

  return ("ALTER TABLE $table DROP CONSTRAINT $fk_name");
}

sub convert_type {

  my ($self, $type) = @_;
  return $self->{db_specific}->{$type} || $type;
}

sub get_column {

  my ($self, $table, $column) = @_;

  # Prevent a possible dereferencing of an undef hash, if the
  # table doesn't exist.
  if (exists $self->{schema}->{$table}) {
    my %fields = (@{$self->{schema}{$table}{FIELDS}});
    return $fields{$column};
  }
  return undef;
}    #eosub--get_column

sub get_table_list {

  my $self = shift;
  return sort keys %{$self->{schema}};
}

sub get_table_columns {

  my ($self, $table) = @_;
  my @ddl = ();

  my $thash = $self->{schema}{$table};
  die "Table $table does not exist in the database schema." unless (ref($thash));

  my @columns = ();
  my @fields  = @{$thash->{FIELDS}};
  while (@fields) {
    push(@columns, shift(@fields));
    shift(@fields);
  }

  return @columns;

}    #eosub--get_table_columns

sub get_table_indexes_abstract {
  my ($self, $table) = @_;
  my $table_def = $self->get_table_abstract($table);
  my %indexes = @{$table_def->{INDEXES} || []};
  return \%indexes;
}

sub get_create_database_sql {
  my ($self, $name) = @_;
  return ("CREATE DATABASE $name");
}

sub get_table_ddl {

  my ($self, $table) = @_;
  my @ddl = ();

  die "Table $table does not exist in the database schema."
    unless (ref($self->{schema}{$table}));

  my $create_table = $self->_get_create_table_ddl($table);
  push(@ddl, $create_table) if $create_table;

  my @indexes = @{$self->{schema}{$table}{INDEXES} || []};
  while (@indexes) {
    my $index_name = shift(@indexes);
    my $index_info = shift(@indexes);
    my $index_sql  = $self->get_add_index_ddl($table, $index_name, $index_info);
    push(@ddl, $index_sql) if $index_sql;
  }

  push(@ddl, @{$self->{schema}{$table}{DB_EXTRAS}})
    if (ref($self->{schema}{$table}{DB_EXTRAS}));

  return @ddl;

}    #eosub--get_table_ddl

sub _get_create_table_ddl {

  my ($self, $table) = @_;

  my $thash = $self->{schema}{$table};
  die "Table $table does not exist in the database schema." unless ref $thash;

  my (@col_lines, @fk_lines);
  my @fields = @{$thash->{FIELDS}};
  my $q = $self->db->quote_expr;
  while (@fields) {
    my $field = shift(@fields);
    my $finfo = shift(@fields);
    push(@col_lines, "\t$q->{$field}\t" . $self->get_type_ddl($finfo));
    if ($self->FK_ON_CREATE and $finfo->{REFERENCES}) {
      my $fk = $finfo->{REFERENCES};
      my $fk_ddl = $self->get_fk_ddl($table, $field, $fk);
      push(@fk_lines, $fk_ddl);
    }
  }

  my $sql
    = "CREATE TABLE $q->{$table} (\n" . join(",\n", @col_lines, @fk_lines) . "\n)";
  return $sql;

}

sub _get_create_index_ddl {

  my ($self, $table_name, $index_name, $index_fields, $index_type) = @_;

  my $q = $self->db->quote_expr;
  my $sql = "CREATE ";
  $sql .= "$q->{$index_type} " if ($index_type && $index_type eq 'UNIQUE');
  $sql
    .= "INDEX $q->{$index_name} ON $q->{$table_name} \(" . $q->{join(", ", @$index_fields)} . "\)";

  return ($sql);

}    #eosub--_get_create_index_ddl

#--------------------------------------------------------------------------

sub get_add_column_ddl {

  my ($self, $table, $column, $definition, $init_value) = @_;
  my @statements;
  push(@statements,
        "ALTER TABLE $table "
      . $self->ADD_COLUMN
      . " $column "
      . $self->get_type_ddl($definition));

  # XXX - Note that although this works for MySQL, most databases will fail
  # before this point, if we haven't set a default.
  (push(@statements, "UPDATE $table SET $column = $init_value"))
    if defined $init_value;

  if (defined $definition->{REFERENCES}) {
    push(@statements,
      $self->get_add_fks_sql($table, {$column => $definition->{REFERENCES}}));
  }

  return (@statements);
}

sub get_add_index_ddl {

  my ($self, $table, $name, $definition) = @_;

  my ($index_fields, $index_type);

  # Index defs can be arrays or hashes
  if (ref($definition) eq 'HASH') {
    $index_fields = $definition->{FIELDS};
    $index_type   = $definition->{TYPE};
  }
  else {
    $index_fields = $definition;
    $index_type   = '';
  }

  return $self->_get_create_index_ddl($table, $name, $index_fields, $index_type);
}

sub get_alter_column_ddl {

  my $self = shift;
  my ($table, $column, $new_def, $set_nulls_to) = @_;

  my @statements;
  my $old_def = $self->get_column_abstract($table, $column);
  my $specific = $self->{db_specific};

  # If the types have changed, we have to deal with that.
  if (uc(trim($old_def->{TYPE})) ne uc(trim($new_def->{TYPE}))) {
    push(@statements,
      $self->_get_alter_type_sql($table, $column, $new_def, $old_def));
  }

  my $default     = $new_def->{DEFAULT};
  my $default_old = $old_def->{DEFAULT};

  if (defined $default) {
    $default = $specific->{$default} if exists $specific->{$default};
  }

  # This first condition prevents "uninitialized value" errors.
  if (!defined $default && !defined $default_old) {

    # Do Nothing
  }

  # If we went from having a default to not having one
  elsif (!defined $default && defined $default_old) {
    push(@statements, "ALTER TABLE $table ALTER COLUMN $column" . " DROP DEFAULT");
  }

  # If we went from no default to a default, or we changed the default.
  elsif ((defined $default && !defined $default_old)
    || ($default ne $default_old))
  {
    push(@statements,
      "ALTER TABLE $table ALTER COLUMN $column " . " SET DEFAULT $default");
  }

  # If we went from NULL to NOT NULL.
  if (!$old_def->{NOTNULL} && $new_def->{NOTNULL}) {
    push(@statements, $self->_set_nulls_sql(@_));
    push(@statements, "ALTER TABLE $table ALTER COLUMN $column" . " SET NOT NULL");
  }

  # If we went from NOT NULL to NULL
  elsif ($old_def->{NOTNULL} && !$new_def->{NOTNULL}) {
    push(@statements, "ALTER TABLE $table ALTER COLUMN $column" . " DROP NOT NULL");
  }

  # If we went from not being a PRIMARY KEY to being a PRIMARY KEY.
  if (!$old_def->{PRIMARYKEY} && $new_def->{PRIMARYKEY}) {
    push(@statements, "ALTER TABLE $table ADD PRIMARY KEY ($column)");
  }

  # If we went from being a PK to not being a PK
  elsif ($old_def->{PRIMARYKEY} && !$new_def->{PRIMARYKEY}) {
    push(@statements, "ALTER TABLE $table DROP PRIMARY KEY");
  }

  return @statements;
}

# Helps handle any fields that were NULL before, if we have a default,
# when doing an ALTER COLUMN.
sub _set_nulls_sql {
  my ($self, $table, $column, $new_def, $set_nulls_to) = @_;
  my $default = $new_def->{DEFAULT};

  # If we have a set_nulls_to, that overrides the DEFAULT
  # (although nobody would usually specify both a default and
  # a set_nulls_to.)
  $default = $set_nulls_to if defined $set_nulls_to;
  if (defined $default) {
    my $specific = $self->{db_specific};
    $default = $specific->{$default} if exists $specific->{$default};
  }
  my @sql;
  if (defined $default) {
    push(@sql, "UPDATE $table SET $column = $default" . "  WHERE $column IS NULL");
  }
  return @sql;
}

sub get_drop_index_ddl {

  my ($self, $table, $name) = @_;

  # Although ANSI SQL-92 doesn't specify a method of dropping an index,
  # many DBs support this syntax.
  return ("DROP INDEX $name");
}

sub get_drop_column_ddl {

  my ($self, $table, $column) = @_;
  return ("ALTER TABLE $table DROP COLUMN $column");
}

sub get_drop_table_ddl {
  my ($self, $table) = @_;
  return ("DROP TABLE $table");
}

sub get_rename_column_ddl {

  die "ANSI SQL has no way to rename a column, and your database driver\n"
    . " has not implemented a method.";
}


sub get_rename_table_sql {

  my ($self, $old_name, $new_name) = @_;
  return ("ALTER TABLE $old_name RENAME TO $new_name");
}

sub delete_table {
  my ($self, $name) = @_;

  die "Attempted to delete nonexistent table '$name'."
    unless $self->get_table_abstract($name);

  delete $self->{abstract_schema}->{$name};
  delete $self->{schema}->{$name};
}

sub get_column_abstract {

  my ($self, $table, $column) = @_;

  # Prevent a possible dereferencing of an undef hash, if the
  # table doesn't exist.
  if ($self->get_table_abstract($table)) {
    my %fields = (@{$self->{abstract_schema}{$table}{FIELDS}});
    return $fields{$column};
  }
  return undef;
}

sub get_indexes_on_column_abstract {
  my ($self, $table, $column) = @_;
  my %ret_hash;

  my $table_def = $self->get_table_abstract($table);
  if ($table_def && exists $table_def->{INDEXES}) {
    my %indexes = (@{$table_def->{INDEXES}});
    foreach my $index_name (keys %indexes) {
      my $col_list;

      # Get the column list, depending on whether the index
      # is in hashref or arrayref format.
      if (ref($indexes{$index_name}) eq 'HASH') {
        $col_list = $indexes{$index_name}->{FIELDS};
      }
      else {
        $col_list = $indexes{$index_name};
      }

      if (grep($_ eq $column, @$col_list)) {
        $ret_hash{$index_name} = dclone($indexes{$index_name});
      }
    }
  }

  return %ret_hash;
}

sub get_index_abstract {

  my ($self, $table, $index) = @_;

  # Prevent a possible dereferencing of an undef hash, if the
  # table doesn't exist.
  my $index_table = $self->get_table_abstract($table);
  if ($index_table && exists $index_table->{INDEXES}) {
    my %indexes = (@{$index_table->{INDEXES}});
    return $indexes{$index};
  }
  return undef;
}

sub get_table_abstract {
  my ($self, $table) = @_;
  return $self->{abstract_schema}->{$table};
}

sub add_table {
  my ($self, $name, $definition) = @_;
  (die "Table already exists: $name") if exists $self->{abstract_schema}->{$name};
  if ($definition) {
    $self->{abstract_schema}->{$name} = dclone($definition);
    $self->{schema} = dclone($self->{abstract_schema});
    $self->_adjust_schema();
  }
  else {
    $self->{abstract_schema}->{$name} = {FIELDS => []};
    $self->{schema}->{$name}          = {FIELDS => []};
  }
}


sub rename_table {


  my ($self, $old_name, $new_name) = @_;
  my $table = $self->get_table_abstract($old_name);
  $self->delete_table($old_name);
  $self->add_table($new_name, $table);
}

sub delete_column {

  my ($self, $table, $column) = @_;

  my $abstract_fields = $self->{abstract_schema}{$table}{FIELDS};
  my $name_position = firstidx { $_ eq $column } @$abstract_fields;
  die "Attempted to delete nonexistent column ${table}.${column}"
    if $name_position == -1;

  # Delete the key/value pair from the array.
  splice(@$abstract_fields, $name_position, 2);

  $self->{schema} = dclone($self->{abstract_schema});
  $self->_adjust_schema();
}

sub rename_column {

  my ($self, $table, $old_name, $new_name) = @_;
  my $def = $self->get_column_abstract($table, $old_name);
  die "Renaming a column that doesn't exist" if !$def;
  $self->delete_column($table, $old_name);
  $self->set_column($table, $new_name, $def);
}

sub set_column {

  my ($self, $table, $column, $new_def) = @_;

  my $fields = $self->{abstract_schema}{$table}{FIELDS};
  $self->_set_object($table, $column, $new_def, $fields);
}

sub set_fk {
  my ($self, $table, $column, $fk_def) = @_;

  # Don't want to modify the source def before we explicitly set it below.
  # This is just us being extra-cautious.
  my $column_def = dclone($self->get_column_abstract($table, $column));
  die "Tried to set an fk on $table.$column, but that column doesn't exist"
    if !$column_def;
  if ($fk_def) {
    $column_def->{REFERENCES} = $fk_def;
  }
  else {
    delete $column_def->{REFERENCES};
  }
  $self->set_column($table, $column, $column_def);
}

sub set_index {

  my ($self, $table, $name, $definition) = @_;

  if (exists $self->{abstract_schema}{$table}
    && !exists $self->{abstract_schema}{$table}{INDEXES})
  {
    $self->{abstract_schema}{$table}{INDEXES} = [];
  }

  my $indexes = $self->{abstract_schema}{$table}{INDEXES};
  $self->_set_object($table, $name, $definition, $indexes);
}

# A private helper for set_index and set_column.
# This does the actual "work" of those two functions.
# $array_to_change is an arrayref.
sub _set_object {
  my ($self, $table, $name, $definition, $array_to_change) = @_;

  my $obj_position = (firstidx { $_ eq $name } @$array_to_change) + 1;

  # If the object doesn't exist, then add it.
  if (!$obj_position) {
    push(@$array_to_change, $name);
    push(@$array_to_change, $definition);
  }

  # We're modifying an existing object in the Schema.
  else {
    splice(@$array_to_change, $obj_position, 1, $definition);
  }

  $self->{schema} = dclone($self->{abstract_schema});
  $self->_adjust_schema();
}

sub delete_index {
  my ($self, $table, $name) = @_;

  my $indexes = $self->{abstract_schema}{$table}{INDEXES};
  my $name_position = firstidx { $_ eq $name } @$indexes;
  die "Attempted to delete nonexistent index $name on the $table table"
    if $name_position == -1;

  # Delete the key/value pair from the array.
  splice(@$indexes, $name_position, 2);
  $self->{schema} = dclone($self->{abstract_schema});
  $self->_adjust_schema();
}

sub columns_equal {

  my $self    = shift;
  my $col_one = dclone(shift);
  my $col_two = dclone(shift);

  $col_one->{TYPE} = uc($col_one->{TYPE});
  $col_two->{TYPE} = uc($col_two->{TYPE});

  # We don't care about foreign keys when comparing column definitions.
  delete $col_one->{REFERENCES};
  delete $col_two->{REFERENCES};

  my @col_one_array = %$col_one;
  my @col_two_array = %$col_two;

  my ($removed, $added) = diff_arrays(\@col_one_array, \@col_two_array);

  # If there are no differences between the arrays, then they are equal.
  return !scalar(@$removed) && !scalar(@$added) ? 1 : 0;
}


sub serialize_abstract {
  my ($self) = @_;

  # Make it ok to eval
  local $Data::Dumper::Purity = 1;

  # Avoid cross-refs
  local $Data::Dumper::Deepcopy = 1;

  # Always sort keys to allow textual compare
  local $Data::Dumper::Sortkeys = 1;

  return Dumper($self->{abstract_schema});
}

sub deserialize_abstract {
  my ($self, $serialized, $version) = @_;

  my $thawed_hash;
  if ($version < 2) {
    $thawed_hash = thaw($serialized);
  }
  else {
    my $cpt = new Safe;
    $cpt->reval($serialized) || die "Unable to restore cached schema: " . $@;
    $thawed_hash = ${$cpt->varglob('VAR1')};
  }

  # Version 2 didn't have the "created" key for REFERENCES items.
  if ($version < 3) {
    my $standard = $self->new(db => $self->db)->{abstract_schema};
    foreach my $table_name (keys %$thawed_hash) {
      my %standard_fields = @{$standard->{$table_name}->{FIELDS} || []};
      my $table           = $thawed_hash->{$table_name};
      my %fields          = @{$table->{FIELDS} || []};
      while (my ($field, $def) = each %fields) {
        if (exists $def->{REFERENCES}) {
          $def->{REFERENCES}->{created} = 1;
        }
      }
    }
  }

  return $self->new(db => $self->db, abstract_schema => $thawed_hash);
}

#####################################################################
# Class Methods
#####################################################################

sub get_empty_schema {
  my ($self) = @_;
  return $self->deserialize_abstract(Dumper({}), SCHEMA_VERSION);
}

1;

__END__

