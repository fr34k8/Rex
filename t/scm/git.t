#!/usr/bin/env perl

use v5.12.5;
use warnings;

our $VERSION = '9999.99.99_99'; # VERSION

use Test::More;
use Test::Warnings;
use Test::Exception;

use English qw(-no_match_vars);
use File::Spec;
use File::Temp qw(tempdir);
use Rex::Commands;
use Rex::Commands::Run;
use Rex::Commands::SCM;
use Rex::Helper::Run;

$::QUIET = 1;

my $git = can_run('git');

if ( defined $git ) {
  plan tests => 11;
}
else {
  plan skip_all => 'Can not find git command';
}

my $git_user_name  = 'Rex';
my $git_user_email = 'noreply@rexify.org';

my $empty_config_file = $OSNAME eq 'MSWin32' ? q() : File::Spec->devnull();

my $git_environment = {
  GIT_CONFIG_GLOBAL => $empty_config_file,
  GIT_CONFIG_SYSTEM => $empty_config_file,
};

ok( $git, "Found git command at $git" );

my $git_version = i_run 'git version', env => $git_environment;
ok( $git_version, qq(Git version returned as '$git_version') );

my $test_repo_dir = tempdir( CLEANUP => 1 );
ok( -d $test_repo_dir, "$test_repo_dir is the test repo directory now" );

prepare_test_repo($test_repo_dir);
git_repo_ok($test_repo_dir);

my $test_repo_name = 'test_repo';

set repository => $test_repo_name, url => $test_repo_dir;

subtest 'clone into non-existing directory', sub {
  plan tests => 6;

  my $clone_target_dir = init_test();

  ok( -d $clone_target_dir, "$clone_target_dir could be created" );

  rmdir $clone_target_dir;

  ok( !-d $clone_target_dir, "$clone_target_dir does not exist now" );

  lives_ok { checkout $test_repo_name, path => $clone_target_dir }
  'cloning into non-existing directory';

  git_repo_ok($clone_target_dir);
};

subtest 'clone into existing directory', sub {
  plan tests => 5;

  my $clone_target_dir = init_test();

  ok( -d $clone_target_dir,
    "$clone_target_dir is the clone target directory now" );

  lives_ok { checkout $test_repo_name, path => $clone_target_dir }
  'cloning into existing directory';

  git_repo_ok($clone_target_dir);
};

subtest 'checkout new commits', sub {
  plan tests => 4;

  my $clone_target_dir = init_test( clone => TRUE );

  my $test_commit_message = 'new_origin_commit';

  i_run "git commit --allow-empty -m $test_commit_message",
    cwd => $test_repo_dir,
    env => $git_environment;

  lives_ok {
    checkout $test_repo_name,
      path => $clone_target_dir,
  }
  'pulling new commit';

  git_last_commit_message_ok( $clone_target_dir, $test_commit_message );

  reset_test_repo();
};

subtest 'checkout new commits with rebase', sub {
  plan tests => 4; ## no critic (ProhibitDuplicateLiteral)

  my $clone_target_dir = init_test( clone => TRUE );

  i_run 'git commit --allow-empty -m new_origin_commit',
    cwd => $test_repo_dir,
    env => $git_environment;

  my $test_commit_message = 'new_local_commit';

  i_run "git commit --allow-empty -m $test_commit_message",
    cwd => $clone_target_dir,
    env => $git_environment;

  lives_ok {
    checkout $test_repo_name,
      path   => $clone_target_dir,
      rebase => TRUE,
  }
  'pulling new commit with rebase';

  git_last_commit_message_ok( $clone_target_dir, $test_commit_message );

  reset_test_repo();
};

sub prepare_test_repo {
  my $directory = shift;

  i_run 'git init', cwd => $directory, env => $git_environment;

  configure_git_user($directory);

  i_run 'git commit --allow-empty -m commit',
    cwd => $directory,
    env => $git_environment;

  return;
}

sub git_repo_ok {
  my $directory = shift;

  ok( -d $directory, "$directory exists" );
  ok(
    -d File::Spec->join( $directory, q(.git) ),
    "$directory has .git subdirectory"
  );

  lives_ok {
    i_run 'git rev-parse --git-dir', cwd => $directory, env => $git_environment
  }
  "$directory looks like a git repository now";

  return;
}

sub configure_git_user {
  my $directory = shift;

  i_run "git config user.name $git_user_name",
    cwd => $directory,
    env => $git_environment;

  i_run "git config user.email $git_user_email",
    cwd => $directory,
    env => $git_environment;

  return;
}

sub init_test {
  my %opts = @_;

  my $clone_target_dir = tempdir( CLEANUP => 1 );

  if ( $opts{clone} ) {
    lives_ok {
      checkout $test_repo_name,
        path => $clone_target_dir,
    }
    'cloning the repo';

    configure_git_user($clone_target_dir);
  }

  return $clone_target_dir;
}

sub git_last_commit_message_ok {
  my ( $directory, $expected_commit_message ) = @_;

  my $last_commit_message = i_run 'git log --oneline -1 --format=%s',
    cwd => $directory,
    env => $git_environment;

  is( $last_commit_message, $expected_commit_message,
    'got correct last commit message' );

  return;
}

sub reset_test_repo {
  i_run 'git reset --hard HEAD~1',
    cwd => $test_repo_dir,
    env => $git_environment;

  git_last_commit_message_ok( $test_repo_dir, 'commit' );

  return;
}
