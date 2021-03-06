#!/usr/bin/env perl
package HTTP::HttpServerRequests;
use strict "vars"; use warnings;

#use experimental qw(smartmatch);
# ix for dima's perl
no if $] >= 5.018, warnings => "experimental::smartmatch";

use File::Basename;
use Cwd;
use Data::Dumper;
use Exporter qw(import);
our @ISA = qw(Exporter);
our @EXPORT = qw(
                get_remote_revisions get_remote_plain_diff
                get_remote_checkout post_remote_checkin
                get_remote_repo_content post_create_remote_repo
                delete_remote_repo delete_remote_repo_perm
                post_remote_repo_perm post_remote_add_user
                post_remote_user_del get_remote_listrepos
                get_remote_repo_members get_remote_timestamp get_remote_last_user
                post_remote_backup_repo post_remote_backup_db
                post_remote_restore_repo post_remote_restore_db
                get_remote_repo_backup_list get_remote_db_backup_list
                );

# Internal libs
use lib qw(../);
use HTTP::Tiny;
use RepoManagement::Init;
use VersionManagement::Impl;
use RepoManagement::Configuration qw($MYCVS_REMOTE_SUFFIX);

our %http_options = (
                    timeout => 10
                    );
our %get_commands = (
                get_revision     => '/repo/revision',
                checkout         => '/repo/checkout',
                get_all_revisions=> '/repo/revisions',
                get_timestamp    => '/repo/timestamp',
                get_filelist     => '/repo/filelist',
                get_listrepos    => '/repo/listrepos',
                get_repo_members => '/repo/members',
                get_last_user    => '/repo/lastuser',
                repo_backup_list => '/backup/repolist',
                db_backup_list   => '/backup/dblist'
                );
our %post_commands = (
                checkin          => '/repo/checkin',
                add_repo         => '/repo/add',
                add_user_to_repo => '/repo/user/add',
                unlock_file      => '/repo/unlock',
                backup_repo      => '/backup/backuprepo',
                restore_repo     => '/backup/restorerepo',
                restore_db       => '/backup/restoredb',
                backup_db        => '/backup/backupdb',
                create_user      => '/user/add'
                );
our %delete_commands = (
                delete_repo      => '/repo/del',
                delete_user      => '/user/del',
                remove_repo_perm => '/repo/user/del'
                );

sub send_http_request {
    my ($method, $command, $vars, $data, $timestamp) = @_;
    my $response;
    my $http = HTTP::Tiny->new(%http_options);
    my %options = parse_config_line(getcwd().'/.');
    my $uri = "http://$options{user}:$options{pass}@";
    
    $uri .= "$options{host}:$options{port}";
    $uri .= "$command";
    if (defined($vars)) {
        $uri .= "?$vars";    
    }
    
    if (!defined($data)) {
        #$response = $http->request($method, $uri);
        $response = $http->request(
                                $method,
                                $uri => {
                                    headers => {
                                        "User-Agent" => "MyCVS Client"
                                    }
                                }
                            );
    } else {
        $timestamp = 0 if !defined($timestamp);
        $response = $http->request(
                                $method,
                                $uri => {
                                    agent   => "MyCVSClient",
                                    content => $data,
                                    headers => {
                                        "User-Agent"   => "MyCVS Client",
                                        "Content-Type" => "text/plain",
                                        "Time-Stamp"   => "$timestamp"
                                    }
                                }
                            );
    }
    
    return ($response->{content}, %{$response->{headers}}) if $response->{status} eq 200;
    die "Requested resourse not Found.\n" if $response->{status} eq 404;
    die $response->{content}."\n" if $response->{status} eq 409;
    die "You not Authorized\n" if $response->{status} eq 401;
    die "Action Forbidden. ".$response->{content}."\n" if $response->{status} eq 403;
    die "Not Implemented. ".$response->{content}."\n" if $response->{status} eq 501;
    die $response->{content}."\n" if $response->{status};
}

sub check_http_prerequisites {
    my ($file_path) = @_;
    if (!defined($file_path)) {
        return 0;
    }
    
    my %options = parse_config_line($file_path);
    
    if (!defined($options{reponame})) {
        return 0;
    }
    return 1;
}

sub convert_response_to_array {
    my ($response) = @_;
    return split('\n', $response);
}

sub get_remote_revisions {
    my ($file_path) = @_;
    my ($vars, $response, @revisions, %headers);
    
    if (! check_http_prerequisites($file_path)) {
        return;
    }
    
    my %options = parse_config_line($file_path);
    my $reporoot = get_repo_root($file_path);
    
    $file_path =~ s/${reporoot}//;
    $vars = "reponame=".$options{reponame}."&filename=".$file_path;
    
    ($response, %headers) = send_http_request('GET',$get_commands{get_all_revisions}, $vars);
    @revisions = convert_response_to_array($response);
    
    return @revisions;
}

sub get_remote_plain_diff {
    my ($file_path, $revision) = @_;
    my ($vars, $response, $temp_file_path, $local_file_path);
    my (@diff, @file_lines, %headers);
    if (! check_http_prerequisites($file_path)) {
        return;
    }
    my %options = parse_config_line($file_path);
    my $reporoot = get_repo_root($file_path);
    
    $local_file_path = $file_path;
    $temp_file_path = $file_path.'.'.$MYCVS_REMOTE_SUFFIX;
    $file_path =~ s/${reporoot}//;
    $vars = "reponame=".$options{reponame}."&filename=".$file_path;
    
    if (defined($revision)) {
        $vars .= "&revision=$revision";
    }
    
    ($response, %headers) = send_http_request('GET',$get_commands{get_revision}, $vars);
    return if ! defined($response);
    
    save_string_to_new_file($response, $temp_file_path);
    @diff = get_diff_on_two_files($local_file_path, $temp_file_path);
    
    delete_file($temp_file_path);
    return @diff;
}

sub get_remote_checkout {
    my ($file_path, $revision) = @_;
    my ($vars, $response, $temp_file_path, $local_file_path, @file_lines, %headers);
    
    if (! check_http_prerequisites(getcwd().'/.')) {
        return;
    }
    my %options = parse_config_line(getcwd().'/.');
    my $reporoot = get_repo_root(getcwd().'/.');
    my $timestamp;
    
    $local_file_path = $file_path;
    $temp_file_path = $file_path.'.'.$MYCVS_REMOTE_SUFFIX;
    $file_path =~ s/${reporoot}//;
    $vars = "reponame=".$options{reponame}."&filename=".$file_path;
    
    if (defined($revision)) {
        $vars .= "&revision=$revision";
    }
    ($response, %headers) = send_http_request('GET',$get_commands{checkout}, $vars);
    return if ! defined($response);
    
    if ($temp_file_path !~ /^${reporoot}/) {
        $temp_file_path = $reporoot.$temp_file_path;
    }
    
    save_string_to_new_file($response, $temp_file_path);
    set_file_time($temp_file_path, $headers{'time-stamp'});
    return $response;
}

sub get_remote_listrepos {
    my ($response, %headers);
    my $file_path = getcwd().'/.';
    if (! check_http_prerequisites($file_path)) {
        return;
    }
    my %options = parse_config_line($file_path);
    
    ($response, %headers) = send_http_request('GET',$get_commands{get_listrepos}, "");
    return if ! defined($response);
    
    return convert_response_to_array($response);
}

sub get_remote_repo_members {
    my ($reponame) = @_;
    my ($vars, $response, @file_lines, %headers);
    my $file_path = getcwd().'/.';
    if (! check_http_prerequisites($file_path)) {
        return;
    }
    my %options = parse_config_line($file_path);
    $vars = "reponame=".$reponame;
    
    ($response, %headers) = send_http_request('GET',
                                              $get_commands{get_repo_members},
                                              $vars);
    return if !defined($response);
    
    return convert_response_to_array($response);
}

sub post_remote_checkin {
    my ($file_path) = @_;
    my ($data, $vars, $response, $local_file_path, @file_lines, %headers);
    
    if (! check_http_prerequisites($file_path)) {
        return;
    }
    my %options   = parse_config_line($file_path);
    my $reporoot  = get_repo_root($file_path);
    my $timestamp = get_file_time($file_path);
    my $remote_timestamp = get_remote_timestamp($file_path);
    
    if ($timestamp eq $remote_timestamp) {
        return "TimeStamp not changed. Nothing to checkin.\n";
    } elsif ($timestamp lt $remote_timestamp) {
        return "Your file is older than server. Please checkout first.\n";
    }
    
    $local_file_path = $file_path;
    $file_path =~ s/${reporoot}//;
    $vars = "reponame=".$options{reponame}."&filename=".$file_path;
    
    @file_lines = read_lines_from_file($local_file_path);
    if (! @file_lines) {
        print "You are checking in an empty file\n.";
        $data = "\n";
    }
    $data = join('', @file_lines);
    
    
    ($response, %headers) = send_http_request('POST',
                                              $post_commands{checkin},
                                              $vars, $data, $timestamp);
    return $response;
}

sub get_remote_timestamp {
    my ($file_path) = @_;
    my ($vars, $response, %headers);
    
    if (! check_http_prerequisites($file_path)) {
        return;
    }
    my %options = parse_config_line($file_path);
    my $reporoot = get_repo_root($file_path);
    my $timestamp;
    
    $file_path =~ s/${reporoot}//;
    $vars = "reponame=".$options{reponame}."&filename=".$file_path;
    
    ($response, %headers) = send_http_request('GET',
                                              $get_commands{get_timestamp},
                                              $vars);
    return $headers{'time-stamp'};
}

sub get_remote_last_user {
    my ($file_path) = @_;
    my ($vars, $response, %headers);
    
    if (! check_http_prerequisites($file_path)) {
        return;
    }
    my %options = parse_config_line($file_path);
    my $reporoot = get_repo_root($file_path);
    
    $file_path =~ s/${reporoot}//;
    $vars = "reponame=".$options{reponame}."&filename=".$file_path;
    
    ($response, %headers) = send_http_request('GET',
                                              $get_commands{get_last_user},
                                              $vars);
    return ($options{user}, $response);
}

sub get_remote_repo_content {
    my ($data, $vars, $response, @file_lines, %headers);
    my $file_path = getcwd().'/.';
    if (! check_http_prerequisites($file_path)) {
        return;
    }
    my %options = parse_config_line($file_path);
    my $reporoot = get_repo_root($file_path);
    
    $vars = "reponame=".$options{reponame};
    
    ($response, %headers) = send_http_request('GET',
                                              $get_commands{get_filelist},
                                              $vars, $data);
    if (!defined($response)) {
        return;
    }
    
    return convert_response_to_array($response);
}

sub post_create_remote_repo {
    my ($reponame) = @_;
    my ($vars, $response, %headers);
    my $file_path = getcwd().'/.';
    
    if (! check_http_prerequisites($file_path)) {
        return;
    }
    
    $vars = "reponame=".$reponame;
       
    
    ($response, %headers) = send_http_request('POST', $post_commands{add_repo}, $vars);
    return $response;
}

sub delete_remote_repo {
    my ($reponame) = @_;
    my ($vars, $response, %headers);
    my $file_path = getcwd().'/.';
    
    if (! check_http_prerequisites($file_path)) {
        return;
    }
    
    $vars = "reponame=".$reponame;
       
    
    ($response, %headers) = send_http_request('DELETE',
                                              $delete_commands{delete_repo},
                                              $vars);
    return $reponame;
}

sub delete_remote_repo_perm {
    my ($reponame, $user) = @_;
    my ($vars, $response, %headers);
    my $file_path = getcwd().'/.';
    
    if (! check_http_prerequisites($file_path)) {
        return;
    }
    if (!defined($reponame) || !defined($user)) {
        return;
    }
    
    $vars = "reponame=".$reponame."&username=".$user;
    
    ($response, %headers) = send_http_request('DELETE',
                                              $delete_commands{remove_repo_perm},
                                              $vars);
    return $response;
}

sub post_remote_repo_perm {
    my ($user, $reponame) = @_;
    my ($vars, $response, %headers);
    my $file_path = getcwd().'/.';
    
    if (! check_http_prerequisites($file_path)) {
        return;
    }
    if (!defined($user) || !defined($reponame)) {
        return;
    }
    
    $vars = "username=".$user."&reponame=".$reponame;
    
    ($response, %headers) = send_http_request('POST',
                                              $post_commands{add_user_to_repo},
                                              $vars);
    return $response;
}

sub post_remote_add_user {
    my ($user, $passhash, $isAdmin) = @_;
    my ($vars, $response, %headers);
    my $file_path = getcwd().'/.';
    
    if (! check_http_prerequisites($file_path)) {
        return;
    }
    if (!defined($user) || !defined($passhash)) {
        return;
    }
    if (!defined($isAdmin)) {
        $isAdmin = 'false';
    }
    
    $vars = "username=".$user."&pass=".$passhash."&admin=".$isAdmin;
    
    ($response, %headers) = send_http_request('POST',
                                              $post_commands{create_user},
                                              $vars);
    return $response;
}

sub post_remote_user_del {
    my ($user) = @_;
    my ($vars, $response, %headers);
    my $file_path = getcwd().'/.';
    
    if (! check_http_prerequisites($file_path)) {
        return;
    }
    if (!defined($user)) {
        return;
    }
    
    $vars = "username=".$user;
    
    ($response, %headers) = send_http_request('DELETE',
                                              $delete_commands{delete_user},
                                              $vars);
    return $response;
}

sub post_remote_backup_repo {
    my ($reponame) = @_;
    my ($vars, $response, %headers);
    my $file_path = getcwd().'/.';
    
    if (! check_http_prerequisites($file_path)) {
        return;
    }
    
    $vars = "reponame=".$reponame;
       
    
    ($response, %headers) = send_http_request('POST', $post_commands{backup_repo}, $vars);
    return $response;
}

sub post_remote_backup_db {
    my ($response, %headers);
    my $file_path = getcwd().'/.';
    
    if (! check_http_prerequisites($file_path)) {
        return;
    }
       
    
    ($response, %headers) = send_http_request('POST', $post_commands{backup_db});
    return $response;
}

sub post_remote_restore_db {
    my ($backupname) = @_;
    my ($vars, $response, %headers);
    my $file_path = getcwd().'/.';
    
    if (! check_http_prerequisites($file_path) || ! defined($backupname)) {
        return;
    }
    
    $vars = "backupname=".$backupname;
       
    
    ($response, %headers) = send_http_request('POST', $post_commands{restore_db}, $vars);
    return $response;
}

sub post_remote_restore_repo {
    my ($reponame, $backupname) = @_;
    my ($vars, $response, %headers);
    my $file_path = getcwd().'/.';
    
    if (! check_http_prerequisites($file_path) || ! defined($backupname) || ! defined($reponame)) {
        return;
    }
    
    $vars = "reponame=".$reponame."&backupname=".$backupname;
       
    
    ($response, %headers) = send_http_request('POST', $post_commands{restore_repo}, $vars);
    return $response;
}

sub get_remote_repo_backup_list {
    my ($reponame) = @_;
    my ($vars, $response, %headers);
    my $file_path = getcwd().'/.';
    
    if (! check_http_prerequisites($file_path) || !defined($reponame)) {
        return;
    }
    
    $vars = "reponame=".$reponame;
       
    
    ($response, %headers) = send_http_request('GET', $get_commands{repo_backup_list}, $vars);
    return $response;
}

sub get_remote_db_backup_list {
    my ($response, %headers);
    my $file_path = getcwd().'/.';
    
    if (! check_http_prerequisites($file_path)) {
        return;
    }     
    
    ($response, %headers) = send_http_request('GET', $get_commands{db_backup_list});
    return $response;
}




1;
