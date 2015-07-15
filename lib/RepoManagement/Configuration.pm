#!/bin/env perl
package RepoManagement::Configuration;

use Exporter qw(import);
our @ISA = 'Exporter';
our @EXPORT_OK = qw(
                    $MYCVS_GLOBAL_BASEDIR $MYCVS_GLOBAL_CONFIG_LOC
                    $MYCVS_USERS_DB $MYCVS_GROUPS_DB $MYCVS_DB_FOLDER
                    $MYCVS_HTTP_PORT $MYCVS_REPO_STORE
                    );

##################Server Configuration Vars###################
# MYCVS_GLOBAL_BASEDIR repository independent
our $MYCVS_GLOBAL_BASEDIR = $ENV{HOME}.qw(/mycvs);
#our $MYCVS_GLOBAL_BASEDIR = qw(/opt/.mycvs);
our $MYCVS_DB_FOLDER = $MYCVS_GLOBAL_BASEDIR.qw(/db);
# User DB file location
our $MYCVS_USERS_DB = $MYCVS_DB_FOLDER.qw(/users.db);
# User DB file location
our $MYCVS_GROUPS_DB = $MYCVS_DB_FOLDER.qw(/groups.db);
# Repository DB file location
our $MYCVS_REPO_DB = $MYCVS_DB_FOLDER.qw(/repo.db);
# Sessions DB file location
our $MYCVS_SESSIONS_DB = $MYCVS_DB_FOLDER.qw(/session);

our $MYCVS_HTTP_PORT = 8080;
our $MYCVS_REPO_STORE = $MYCVS_GLOBAL_BASEDIR.qw(/repo);

1;