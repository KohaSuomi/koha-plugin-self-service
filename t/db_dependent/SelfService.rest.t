#!/usr/bin/env perl

# This file is part of Koha.
#
# Koha is free software; you can redistribute it and/or modify it under the
# terms of the GNU General Public License as published by the Free Software
# Foundation; either version 3 of the License, or (at your option) any later
# version.
#
# Koha is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with Koha; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

BEGIN {
    #$ENV{LOG4PERL_VERBOSITY_CHANGE} = 6;
    #$ENV{MOJO_OPENAPI_DEBUG} = 1;
    #$ENV{MOJO_LOG_LEVEL} = 'debug';
    $ENV{VERBOSE} = 1;
}

use Modern::Perl;
use utf8;

use Test::More tests => 1;
use Test::Deep;
use Test::Mojo;

use t::lib::TestBuilder;
use t::lib::Mocks;
use t::db_dependent::Util qw(build_patron);
use t::db_dependent::opening_hours_context;
use Mojo::Cookie::Request;

use Koha::Database;

my $schema = Koha::Database->schema;
my $builder = t::lib::TestBuilder->new;
$t::db_dependent::Util::builder = $builder;

my $t = Test::Mojo->new('Koha::REST::V1');
t::lib::Mocks::mock_preference( 'RESTBasicAuth', 1 );


subtest("Scenario: Simple test REST API calls.", sub {
    $schema->storage->txn_begin;
    plan tests => 4;

    my ($patron, $host) = build_patron({
        permissions => [],
    });
    my ($librarian, $librarian_host) = build_patron({
        permissions => [
            { module => 4, subpermission => 'get_self_service_status' },
        ]
    });

    subtest("Set opening hours", sub {
        plan tests => 1;

        my $hours = t::db_dependent::opening_hours_context::createContext;
        C4::Context->set_preference("OpeningHours",$hours);
        ok(1, $hours);
    });
    subtest("Given a system preference 'SSRules'", sub {
        plan tests => 1;

        C4::Context->set_preference("SSRules",
            "---\n".
            "TaC: 1\n".
            "Permission: 1\n".
            "BorrowerCategories: PT S\n".
            "MinimumAge: 15\n".
            "MaxFines: 1\n".
            "CardExpired: 1\n".
            "CardLost: 1\n".
            "Debarred: 1\n".
            "OpeningHours: 1\n".
            "BranchBlock: 1\n".
            "\n");
        Koha::Caches->get_instance()->clear_from_cache('SSRules');
        ok(1, "Step ok");
    });


    subtest "GET /borrowers/ssstatus, terms and conditions not accepted." => sub {
        plan tests => 7;

        $t->get_ok($host.'/api/v1/contrib/kohasuomi/borrowers/ssstatus')
        ->status_is('403')
        ->json_like('/error', qr/Missing required permission/, 'List: No permission');

        # GET Request with formdata body. Test::Mojo clobbers formdata to query params no matter what. So we cheat it a bit here.
        $t->ua->on(start => sub { my ($ua, $tx) = @_; $tx->req->method('GET') });
        $t->post_ok($librarian_host.'/api/v1/contrib/kohasuomi/borrowers/ssstatus' => form => {cardnumber => $patron->userid(), branchcode => 'IPT'})
        ->status_is('200')
        ->json_like('/permission', qr/0/, "Permission denied")
        ->json_like('/error', qr/Koha::Plugin::Fi::KohaSuomi::SelfService::Exception::TACNotAccepted/);
    };

    subtest("GET /borrowers/ssstatus, terms and conditions accepted", sub {
        plan tests => 5;

        ok($patron->extended_attributes(
            $patron->extended_attributes->merge_and_replace_with([{ code => 'SST&C', attribute => '1' }])
        ), "Terms and conditions accepted for the end-user");

        # GET Request with formdata body. Test::Mojo clobbers formdata to query params no matter what. So we cheat it a bit here.
        $t->post_ok($librarian_host.'/api/v1/contrib/kohasuomi/borrowers/ssstatus' => form => {cardnumber => $patron->userid(), branchcode => 'IPT'})
        ->status_is('200')
        ->json_like('/permission', qr/0/, "Permission denied")
        ->json_like('/error', qr/Koha::Plugin::Fi::KohaSuomi::SelfService::Exception::BlockedBorrowerCategory/);
    });

    $schema->storage->txn_rollback;
});

sub prepareBasicAuthHeader {
    my ($username, $password) = @_;
    print "HELLO!\n";
    return 'Basic '.MIME::Base64::encode($username.':'.$password, '');
}

1;
