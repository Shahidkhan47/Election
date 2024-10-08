module my_addr::election {
    use std::error;
    use std::signer;
    use std::string::String;
    use aptos_std::table::{Self, Table};
    use aptos_framework::timestamp;

    #[test_only]
    use std::string;
    #[test_only]
    use aptos_std::debug;

    ///only owner can call this function
    const EONLY_OWNER: u64 = 1;

    //election has not started yet
    const EHAS_NOT_STARTED: u64 = 2;

    ///election has already started
    const EHAS_ALREADY_STARTED: u64 = 3;

    ///voter has already voted
    const EALREADY_VOTED: u64 = 4;

    ///candidate with input key is not found
    const ECANDIDATE_NOT_EXISTED: u64 = 5;

    ///enter expiration time
    const EINVALID_EXPIRATION_TIME: u64 = 6;

    ///can not see votes during election
    const ECANNOT_SEE_VOTE_COUNT: u64 = 7;

    ///No data found on this address
    const ENO_DATA_FOUND: u64 = 8;

    struct Candidate has copy, key, store, drop {
        name: String,
        proposal: String,
        total_votes: u64
    }

    struct TimingDetails has key, store {
        expiration_time: u64,
        has_not_started: bool,
        has_started: bool,
    }

    struct Election has key {
        candidates: Table<u64, Candidate>,
        voters: Table<address, bool>,
        next_candidate_key: u64,
        timing_detail: TimingDetails
    }

    fun init_module(account: &signer) {
        let timing_detail = TimingDetails {
            expiration_time: 0,
            has_not_started: true,
            has_started: false,
        };
        let election = Election {
            candidates: table::new<u64, Candidate>(),
            voters: table::new<address, bool>(),
            next_candidate_key: 1,
            timing_detail
        };

        move_to(account, election);
    }

    ///add candidates before starting election by module owner
    public entry fun add_candidate(election_addr: &signer, name: String, proposal: String) acquires Election {
        let onlyOwner = signer::address_of(election_addr);
        assert!(exists<Election>(onlyOwner), error::permission_denied(EONLY_OWNER));
        let election_data = borrow_global_mut<Election>(onlyOwner);
        assert!(
            election_data.timing_detail.has_not_started && !election_data.timing_detail.has_started,
            error::invalid_state(EHAS_ALREADY_STARTED)
        );

        let candidate = Candidate {
            name,
            proposal,
            total_votes: 0
        };
        let key = election_data.next_candidate_key;
        table::add(&mut election_data.candidates, key, candidate);
        election_data.next_candidate_key = key + 1;
    }

    ///start election by only module owner after adding candidates in addCandidate function
    public entry fun start_election(election_addr: &signer, expiration_time: u64) acquires Election {
        let onlyOwner = signer::address_of(election_addr);
        assert!(exists<Election>(onlyOwner), error::permission_denied(EONLY_OWNER));
        let election_data = borrow_global_mut<Election>(onlyOwner);
        assert!(election_data.timing_detail.expiration_time == 0, error::already_exists(EHAS_ALREADY_STARTED));
        assert!(
            expiration_time > 0,
            error::invalid_argument(EINVALID_EXPIRATION_TIME)
        );
        assert!(
            election_data.timing_detail.has_not_started && !election_data.timing_detail.has_started,
            error::invalid_state(EHAS_ALREADY_STARTED)
        );
        election_data.timing_detail.expiration_time = timestamp::now_seconds() + expiration_time;
        election_data.timing_detail.has_started = true;
        election_data.timing_detail.has_not_started = false;
    }

    ///casting votes by different addresses after election starts by module owner
    public entry fun cast_vote(account_voter: &signer, election_addr: address, key: u64) acquires Election {
        let voter_addr = signer::address_of(account_voter);
        let election_data = borrow_global_mut<Election>(election_addr);
        if (election_data.timing_detail.expiration_time < timestamp::now_seconds()) {
            election_data.timing_detail.has_started = false;
            election_data.timing_detail.has_not_started == false;
        };
        assert!(!table::contains(&election_data.voters, voter_addr), error::already_exists(EALREADY_VOTED));
        assert!(table::contains(&election_data.candidates, key), error::not_found(ECANDIDATE_NOT_EXISTED));
        assert!(
            election_data.timing_detail.has_started && !election_data.timing_detail.has_not_started,
            error::invalid_state(
                EHAS_NOT_STARTED
            )
        );
        table::add(&mut election_data.voters, voter_addr, true);
        let votes = table::borrow_mut(&mut election_data.candidates, key);
        votes.total_votes = votes.total_votes + 1;
    }


    #[view]
    ///get candidate details like name , proposal by entering key
    public fun check_candidates(election_addr: address, key: u64): (String, String) acquires Election {
        assert!(exists<Election>(election_addr), error::not_found(ENO_DATA_FOUND));
        let election_data = borrow_global<Election>(election_addr);
        let candidate_data = table::borrow(&election_data.candidates, key);
        (candidate_data.name, candidate_data.proposal)
    }

    #[view]
    ///getting vote counts of candidates by entering key
    public fun check_votes(election_addr: address, key: u64): u64 acquires Election {
        assert!(exists<Election>(election_addr), error::not_found(ENO_DATA_FOUND));
        let election_data = borrow_global<Election>(election_addr);
        assert!(
            election_data.timing_detail.expiration_time < timestamp::now_seconds(),
            error::permission_denied(ECANNOT_SEE_VOTE_COUNT)
        );
        let candidate_data = table::borrow(&election_data.candidates, key);
        candidate_data.total_votes
    }


    #[test(
        owner = @0x1234,
        voter1 = @0x222,
        voter2 = @0x3333,
        voter3 = @0x444,
        voter4 = @0x555,
        aptos_framework = @aptos_framework
    )]

    public fun test_election(
        owner: signer,
        voter1: signer,
        voter2: signer,
        voter3: signer,
        voter4: signer,
        aptos_framework: signer
    ) acquires Election {
        let owner_addr = signer::address_of(&owner);
        let voter1_addr = signer::address_of(&voter1);
        aptos_framework::account::create_account_for_test(voter1_addr);
        let voter2_addr = signer::address_of(&voter2);
        aptos_framework::account::create_account_for_test(voter2_addr);
        let voter3_addr = signer::address_of(&voter3);
        aptos_framework::account::create_account_for_test(voter3_addr);
        let voter4_addr = signer::address_of(&voter4);
        aptos_framework::account::create_account_for_test(voter4_addr);

        init_module(&owner);

        timestamp::set_time_has_started_for_testing(&aptos_framework);
        timestamp::update_global_time_for_test_secs(500);

        timestamp::fast_forward_seconds(20);
        let candidate1_name = std::string::utf8(b"Sukirat");
        let candidate1_proposal = std::string::utf8(b"education");
        add_candidate(&owner, candidate1_name, candidate1_proposal);

        timestamp::fast_forward_seconds(25);
        let candidate2_name = std::string::utf8(b"Priyanshu");
        let candidate2_proposal = std::string::utf8(b"Water");
        add_candidate(&owner, candidate2_name, candidate2_proposal);

        let (getting_output1, getting_output2) = check_candidates(owner_addr, 1);
        debug::print(&string::utf8(b"candidate1 detail - 1"));
        debug::print(&getting_output1);
        debug::print(&string::utf8(b"candidate1 detail - 2"));
        debug::print(&getting_output2);

        timestamp::fast_forward_seconds(50);
        start_election(&owner, 1000);

        timestamp::fast_forward_seconds(100);
        cast_vote(&voter1, owner_addr, 1);

        timestamp::fast_forward_seconds(100);
        cast_vote(&voter2, owner_addr, 1);

        timestamp::fast_forward_seconds(100);
        cast_vote(&voter3, owner_addr, 2);

        timestamp::fast_forward_seconds(150);
        cast_vote(&voter4, owner_addr, 1);

        timestamp::fast_forward_seconds(1500);
        let see_votes1 = check_votes(owner_addr, 1);
        debug::print(&string::utf8(b"Sukirat's votes"));
        debug::print(&see_votes1);

        timestamp::fast_forward_seconds(1500);
        let see_votes2 = check_votes(owner_addr, 2);
        debug::print(&string::utf8(b"Priyanshu's votes"));
        debug::print(&see_votes2);
    }

    #[test(
        owner = @0x1234,
        voter1 = @0x222,
        aptos_framework = @aptos_framework
    )]
    #[expected_failure(abort_code = 327681, location = Self
    )]

    public entry fun testfail_for_addcandidate_owner(owner: signer, voter1: signer,
                                                     aptos_framework: signer
    ) acquires Election {
        let voter1_addr = signer::address_of(&voter1);
        aptos_framework::account::create_account_for_test(voter1_addr);

        init_module(&owner);

        timestamp::set_time_has_started_for_testing(&aptos_framework);
        timestamp::update_global_time_for_test_secs(500);

        timestamp::fast_forward_seconds(20);
        let candidate1_name = std::string::utf8(b"Sukirat");
        let candidate1_proposal = std::string::utf8(b"education");
        add_candidate(&voter1, candidate1_name, candidate1_proposal);
    }

    #[test(
        owner = @0x1234,
        voter1 = @0x222,
        aptos_framework = @aptos_framework
    )]
    #[expected_failure(abort_code = 196611, location = Self
    )]

    public entry fun testfail_for_addcandidate_endedtime(owner: signer, voter1: signer,
                                                         aptos_framework: signer
    ) acquires Election {
        let voter1_addr = signer::address_of(&voter1);
        aptos_framework::account::create_account_for_test(voter1_addr);

        init_module(&owner);

        timestamp::set_time_has_started_for_testing(&aptos_framework);
        timestamp::update_global_time_for_test_secs(500);

        timestamp::fast_forward_seconds(50);
        start_election(&owner, 1000);

        timestamp::fast_forward_seconds(1500);
        let candidate1_name = std::string::utf8(b"Sukirat");
        let candidate1_proposal = std::string::utf8(b"education");
        add_candidate(&owner, candidate1_name, candidate1_proposal);
    }

    #[test(
        owner = @0x1234,
        aptos_framework = @aptos_framework
    )]
    #[expected_failure(abort_code = 196611, location = Self
    )]

    public entry fun testfail_add_during_election(owner: signer,
                                                  aptos_framework: signer
    ) acquires Election {
        init_module(&owner);

        timestamp::set_time_has_started_for_testing(&aptos_framework);
        timestamp::update_global_time_for_test_secs(500);

        timestamp::fast_forward_seconds(50);
        start_election(&owner, 1000);

        timestamp::fast_forward_seconds(20);
        let candidate1_name = std::string::utf8(b"Sukirat");
        let candidate1_proposal = std::string::utf8(b"education");
        add_candidate(&owner, candidate1_name, candidate1_proposal);
    }

    #[test(
        owner = @0x1234,
        voter1 = @0x222,
        aptos_framework = @aptos_framework
    )]
    #[expected_failure(abort_code = 327681, location = Self
    )]

    public entry fun testfail_for_startelection_owner(owner: signer, voter1: signer,
                                                      aptos_framework: signer
    ) acquires Election {
        init_module(&owner);

        timestamp::set_time_has_started_for_testing(&aptos_framework);
        timestamp::update_global_time_for_test_secs(500);

        timestamp::fast_forward_seconds(20);
        let candidate1_name = std::string::utf8(b"Sukirat");
        let candidate1_proposal = std::string::utf8(b"education");
        add_candidate(&owner, candidate1_name, candidate1_proposal);

        timestamp::fast_forward_seconds(50);
        start_election(&voter1, 1000);
    }

    #[test(
        owner = @0x1234,
        aptos_framework = @aptos_framework
    )]
    #[expected_failure(abort_code = 524291, location = Self
    )]

    public entry fun testfail_for_startelection_secondtime(owner: signer,
                                                           aptos_framework: signer
    ) acquires Election {
        init_module(&owner);

        timestamp::set_time_has_started_for_testing(&aptos_framework);
        timestamp::update_global_time_for_test_secs(500);

        timestamp::fast_forward_seconds(20);
        let candidate1_name = std::string::utf8(b"Sukirat");
        let candidate1_proposal = std::string::utf8(b"education");
        add_candidate(&owner, candidate1_name, candidate1_proposal);

        timestamp::fast_forward_seconds(50);
        start_election(&owner, 1000);

        timestamp::fast_forward_seconds(100);
        start_election(&owner, 1500);
    }

    #[test(
        owner = @0x1234,
        voter1 = @0x222,
        aptos_framework = @aptos_framework
    )]
    #[expected_failure(abort_code = 196610, location = Self
    )]
    public entry fun testfail_for_castvote_endedtime(owner: signer,
                                                     voter1: signer,
                                                     aptos_framework: signer
    ) acquires Election {
        let owner_addr = signer::address_of(&owner);
        let voter1_addr = signer::address_of(&voter1);
        aptos_framework::account::create_account_for_test(voter1_addr);
        init_module(&owner);
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        timestamp::update_global_time_for_test_secs(500);
        timestamp::fast_forward_seconds(20);
        let candidate1_name = std::string::utf8(b"Sukirat");
        let candidate1_proposal = std::string::utf8(b"education");
        add_candidate(&owner, candidate1_name, candidate1_proposal);

        timestamp::fast_forward_seconds(25);
        let candidate2_name = std::string::utf8(b"Priyanshu");
        let candidate2_proposal = std::string::utf8(b"Water");
        add_candidate(&owner, candidate2_name, candidate2_proposal);

        timestamp::fast_forward_seconds(50);
        start_election(&owner, 1000);

        timestamp::fast_forward_seconds(10000);
        cast_vote(&voter1, owner_addr, 1);
    }

    #[test(
        owner = @0x1234,
        voter1 = @0x222,
        aptos_framework = @aptos_framework
    )]
    #[expected_failure(abort_code = 393221, location = Self
    )]
    public entry fun testfail_for_castvote_key(owner: signer,
                                               voter1: signer,
                                               aptos_framework: signer
    ) acquires Election {
        let owner_addr = signer::address_of(&owner);
        let voter1_addr = signer::address_of(&voter1);
        aptos_framework::account::create_account_for_test(voter1_addr);
        init_module(&owner);
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        timestamp::update_global_time_for_test_secs(500);
        timestamp::fast_forward_seconds(20);
        let candidate1_name = std::string::utf8(b"Sukirat");
        let candidate1_proposal = std::string::utf8(b"education");
        add_candidate(&owner, candidate1_name, candidate1_proposal);

        timestamp::fast_forward_seconds(25);
        let candidate2_name = std::string::utf8(b"Priyanshu");
        let candidate2_proposal = std::string::utf8(b"Water");
        add_candidate(&owner, candidate2_name, candidate2_proposal);
        timestamp::fast_forward_seconds(50);
        start_election(&owner, 1000);

        timestamp::fast_forward_seconds(100);
        cast_vote(&voter1, owner_addr, 3);
    }

    #[test(
        owner = @0x1234,
        voter1 = @0x222,
        aptos_framework = @aptos_framework
    )]
    #[expected_failure(abort_code = 524292, location = Self
    )]

    public entry fun testfail_vote_secondtime(owner: signer,
                                              voter1: signer,
                                              aptos_framework: signer
    ) acquires Election {
        let owner_addr = signer::address_of(&owner);

        init_module(&owner);

        timestamp::set_time_has_started_for_testing(&aptos_framework);
        timestamp::update_global_time_for_test_secs(500);

        timestamp::fast_forward_seconds(20);
        let candidate1_name = std::string::utf8(b"Sukirat");
        let candidate1_proposal = std::string::utf8(b"education");
        add_candidate(&owner, candidate1_name, candidate1_proposal);

        timestamp::fast_forward_seconds(25);
        let candidate2_name = std::string::utf8(b"Priyanshu");
        let candidate2_proposal = std::string::utf8(b"Water");
        add_candidate(&owner, candidate2_name, candidate2_proposal);

        timestamp::fast_forward_seconds(50);
        start_election(&owner, 1000);

        timestamp::fast_forward_seconds(100);
        cast_vote(&voter1, owner_addr, 1);

        timestamp::fast_forward_seconds(200);
        cast_vote(&voter1, owner_addr, 1);
    }

    #[test(
        owner = @0x1234,
        voter1 = @0x222,
        aptos_framework = @aptos_framework
    )]
    #[expected_failure(abort_code = 393224, location = Self
    )]
    public entry fun testfail_checkcandidates_owner(owner: signer, voter1: signer,
                                                    aptos_framework: signer
    ) acquires Election {
        let voter1_addr = signer::address_of(&voter1);

        init_module(&owner);

        timestamp::set_time_has_started_for_testing(&aptos_framework);
        timestamp::update_global_time_for_test_secs(500);

        timestamp::fast_forward_seconds(20);
        let candidate1_name = std::string::utf8(b"Sukirat");
        let candidate1_proposal = std::string::utf8(b"education");
        add_candidate(&owner, candidate1_name, candidate1_proposal);

        check_candidates(voter1_addr, 1);
    }

    #[test(
        owner = @0x1234,
        voter1 = @0x222,
        voter2 = @0x3333,
        aptos_framework = @aptos_framework
    )]
    #[expected_failure(abort_code = 327687, location = Self
    )]

    public entry fun testfail_checkvotes_time(owner: signer, voter1: signer, voter2: signer,
                                              aptos_framework: signer
    ) acquires Election {
        let owner_addr = signer::address_of(&owner);

        init_module(&owner);

        timestamp::set_time_has_started_for_testing(&aptos_framework);
        timestamp::update_global_time_for_test_secs(500);

        timestamp::fast_forward_seconds(20);
        let candidate1_name = std::string::utf8(b"Sukirat");
        let candidate1_proposal = std::string::utf8(b"education");
        add_candidate(&owner, candidate1_name, candidate1_proposal);

        timestamp::fast_forward_seconds(50);
        start_election(&owner, 1000);

        timestamp::fast_forward_seconds(100);
        cast_vote(&voter1, owner_addr, 1);

        timestamp::fast_forward_seconds(100);
        cast_vote(&voter2, owner_addr, 1);

        timestamp::fast_forward_seconds(150);
        let see_votes1 = check_votes(owner_addr, 1);
        debug::print(&see_votes1);
    }

    #[test(
        owner = @0x1234,
        voter1 = @0x222,
        voter2 = @0x3333,
        aptos_framework = @aptos_framework
    )]
    #[expected_failure(abort_code = 393224, location = Self
    )]
    public entry fun testfail_checkvotes_owner(owner: signer, voter1: signer, voter2: signer,
                                               aptos_framework: signer
    ) acquires Election {
        let owner_addr = signer::address_of(&owner);
        let voter1_addr = signer::address_of(&voter1);

        init_module(&owner);

        timestamp::set_time_has_started_for_testing(&aptos_framework);
        timestamp::update_global_time_for_test_secs(500);

        timestamp::fast_forward_seconds(20);
        let candidate1_name = std::string::utf8(b"Sukirat");
        let candidate1_proposal = std::string::utf8(b"education");
        add_candidate(&owner, candidate1_name, candidate1_proposal);

        timestamp::fast_forward_seconds(50);
        start_election(&owner, 1000);

        timestamp::fast_forward_seconds(100);
        cast_vote(&voter1, owner_addr, 1);

        timestamp::fast_forward_seconds(100);
        cast_vote(&voter2, owner_addr, 1);

        timestamp::fast_forward_seconds(1500);
        let see_votes1 = check_votes(voter1_addr, 1);
        debug::print(&see_votes1);
    }
}


