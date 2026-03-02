module chess::chess_lobby {
    use std::signer;
    use std::vector;
    use aptos_framework::timestamp;
    use aptos_framework::event;
    use chess::chess_leaderboard;
    use chess::chess_game;

    // ============================================
    // CONSTANTS
    // ============================================
    const CHALLENGE_STATUS_OPEN: u8 = 0;
    const CHALLENGE_STATUS_ACCEPTED: u8 = 1;
    const CHALLENGE_STATUS_CANCELLED: u8 = 2;
    const CHALLENGE_STATUS_EXPIRED: u8 = 3;

    const COLOR_RANDOM: u8 = 0;
    const COLOR_WHITE: u8 = 1;
    const COLOR_BLACK: u8 = 2;

    // Default expiration: 1 hour
    const DEFAULT_EXPIRATION_SECONDS: u64 = 3600;

    // Error codes
    const E_NOT_INITIALIZED: u64 = 1;
    const E_CHALLENGE_NOT_FOUND: u64 = 2;
    const E_NOT_CHALLENGER: u64 = 3;
    const E_CANNOT_ACCEPT_OWN: u64 = 4;
    const E_CHALLENGE_NOT_OPEN: u64 = 5;
    const E_CHALLENGE_EXPIRED: u64 = 6;
    const E_NOT_REGISTERED: u64 = 7;
    const E_RATING_OUT_OF_RANGE: u64 = 8;
    const E_WRONG_OPPONENT: u64 = 9;
    const E_CANNOT_CHALLENGE_SELF: u64 = 10;
    const E_NOT_THE_OPPONENT: u64 = 11;
    const E_TOO_MANY_CHALLENGES: u64 = 12;

    // Limits
    const MAX_CHALLENGES_PER_PLAYER: u64 = 5;

    // ============================================
    // STRUCTS
    // ============================================

    /// Represents a game challenge
    struct Challenge has store, copy, drop {
        challenge_id: u64,
        challenger: address,
        opponent: address,                  // @0x0 for open challenge
        time_control_base_seconds: u64,     // Base time in seconds
        time_control_increment_seconds: u64, // Increment per move in seconds
        challenger_color_pref: u8,          // COLOR_RANDOM, COLOR_WHITE, or COLOR_BLACK
        status: u8,
        created_at_ms: u64,
        expires_at_ms: u64,
        min_rating: u64,                    // 0 = no minimum
        max_rating: u64,                    // 0 = no maximum
        game_id: u64,                       // Set when challenge is accepted
    }

    /// Global lobby state
    struct Lobby has key {
        next_challenge_id: u64,
        challenges: vector<Challenge>,
    }

    // Events
    #[event]
    struct ChallengeCreatedEvent has drop, store {
        challenge_id: u64,
        challenger: address,
        opponent: address,
        time_control_base: u64,
        time_control_increment: u64,
        color_preference: u8,
        min_rating: u64,
        max_rating: u64,
        expires_at_ms: u64,
    }

    #[event]
    struct ChallengeAcceptedEvent has drop, store {
        challenge_id: u64,
        challenger: address,
        accepter: address,
        game_id: u64,
        white_player: address,
        black_player: address,
    }

    #[event]
    struct ChallengeCancelledEvent has drop, store {
        challenge_id: u64,
        challenger: address,
    }

    #[event]
    struct ChallengeDeclinedEvent has drop, store {
        challenge_id: u64,
        challenger: address,
        declined_by: address,
    }

    // ============================================
    // INITIALIZATION
    // ============================================

    /// Automatically called when module is published
    fun init_module(deployer: &signer) {
        move_to(deployer, Lobby {
            next_challenge_id: 1,
            challenges: vector::empty(),
        });
    }

    #[test_only]
    /// Initialize for testing
    public fun init_module_for_test(deployer: &signer) {
        init_module(deployer);
    }

    // ============================================
    // ENTRY FUNCTIONS
    // ============================================

    /// Create an open challenge (anyone can accept)
    public entry fun create_open_challenge(
        challenger: &signer,
        time_base_seconds: u64,
        time_increment_seconds: u64,
        color_preference: u8,
        min_rating: u64,
        max_rating: u64,
        expires_in_seconds: u64,
    ) acquires Lobby {
        let challenger_addr = signer::address_of(challenger);

        // Verify player is registered
        assert!(chess_leaderboard::is_registered(challenger_addr), E_NOT_REGISTERED);

        // Check challenge limit
        let lobby_ref = borrow_global<Lobby>(@chess);
        let open_count = count_player_open_challenges(&lobby_ref.challenges, challenger_addr);
        assert!(open_count < MAX_CHALLENGES_PER_PLAYER, E_TOO_MANY_CHALLENGES);

        let lobby = borrow_global_mut<Lobby>(@chess);
        let now_ms = timestamp::now_microseconds() / 1000;
        let expires_in = if (expires_in_seconds == 0) { DEFAULT_EXPIRATION_SECONDS } else { expires_in_seconds };

        let challenge = Challenge {
            challenge_id: lobby.next_challenge_id,
            challenger: challenger_addr,
            opponent: @0x0,  // Open to anyone
            time_control_base_seconds: time_base_seconds,
            time_control_increment_seconds: time_increment_seconds,
            challenger_color_pref: color_preference,
            status: CHALLENGE_STATUS_OPEN,
            created_at_ms: now_ms,
            expires_at_ms: now_ms + (expires_in * 1000),
            min_rating,
            max_rating,
            game_id: 0,
        };

        // Emit event
        event::emit(ChallengeCreatedEvent {
            challenge_id: lobby.next_challenge_id,
            challenger: challenger_addr,
            opponent: @0x0,
            time_control_base: time_base_seconds,
            time_control_increment: time_increment_seconds,
            color_preference,
            min_rating,
            max_rating,
            expires_at_ms: now_ms + (expires_in * 1000),
        });

        vector::push_back(&mut lobby.challenges, challenge);
        lobby.next_challenge_id = lobby.next_challenge_id + 1;
    }

    /// Create a direct challenge to a specific player
    public entry fun create_direct_challenge(
        challenger: &signer,
        opponent: address,
        time_base_seconds: u64,
        time_increment_seconds: u64,
        color_preference: u8,
        expires_in_seconds: u64,
    ) acquires Lobby {
        let challenger_addr = signer::address_of(challenger);

        // Cannot challenge yourself
        assert!(challenger_addr != opponent, E_CANNOT_CHALLENGE_SELF);

        // Verify both players are registered
        assert!(chess_leaderboard::is_registered(challenger_addr), E_NOT_REGISTERED);
        assert!(chess_leaderboard::is_registered(opponent), E_NOT_REGISTERED);

        // Check challenge limit
        let lobby = borrow_global<Lobby>(@chess);
        let open_count = count_player_open_challenges(&lobby.challenges, challenger_addr);
        assert!(open_count < MAX_CHALLENGES_PER_PLAYER, E_TOO_MANY_CHALLENGES);

        let lobby = borrow_global_mut<Lobby>(@chess);
        let now_ms = timestamp::now_microseconds() / 1000;
        let expires_in = if (expires_in_seconds == 0) { DEFAULT_EXPIRATION_SECONDS } else { expires_in_seconds };

        let challenge = Challenge {
            challenge_id: lobby.next_challenge_id,
            challenger: challenger_addr,
            opponent,
            time_control_base_seconds: time_base_seconds,
            time_control_increment_seconds: time_increment_seconds,
            challenger_color_pref: color_preference,
            status: CHALLENGE_STATUS_OPEN,
            created_at_ms: now_ms,
            expires_at_ms: now_ms + (expires_in * 1000),
            min_rating: 0,
            max_rating: 0,
            game_id: 0,
        };

        // Emit event
        event::emit(ChallengeCreatedEvent {
            challenge_id: lobby.next_challenge_id,
            challenger: challenger_addr,
            opponent,
            time_control_base: time_base_seconds,
            time_control_increment: time_increment_seconds,
            color_preference,
            min_rating: 0,
            max_rating: 0,
            expires_at_ms: now_ms + (expires_in * 1000),
        });

        vector::push_back(&mut lobby.challenges, challenge);
        lobby.next_challenge_id = lobby.next_challenge_id + 1;
    }

    /// Accept a challenge - creates the actual game and returns the game_id
    public entry fun accept_challenge(
        accepter: &signer,
        challenge_id: u64,
    ) acquires Lobby {
        let accepter_addr = signer::address_of(accepter);

        // Verify accepter is registered
        assert!(chess_leaderboard::is_registered(accepter_addr), E_NOT_REGISTERED);

        let lobby = borrow_global_mut<Lobby>(@chess);
        let now_ms = timestamp::now_microseconds() / 1000;

        // Find the challenge
        let (found, idx) = find_challenge_index(&lobby.challenges, challenge_id);
        assert!(found, E_CHALLENGE_NOT_FOUND);

        let challenge = vector::borrow_mut(&mut lobby.challenges, idx);

        // Validate challenge state
        assert!(challenge.status == CHALLENGE_STATUS_OPEN, E_CHALLENGE_NOT_OPEN);
        assert!(now_ms < challenge.expires_at_ms, E_CHALLENGE_EXPIRED);
        assert!(accepter_addr != challenge.challenger, E_CANNOT_ACCEPT_OWN);

        // Check if direct challenge
        if (challenge.opponent != @0x0) {
            assert!(accepter_addr == challenge.opponent, E_WRONG_OPPONENT);
        };

        // Check rating requirements for open challenges
        if (challenge.min_rating > 0 || challenge.max_rating > 0) {
            let accepter_rating = chess_leaderboard::get_rating(accepter_addr);
            if (challenge.min_rating > 0) {
                assert!(accepter_rating >= challenge.min_rating, E_RATING_OUT_OF_RANGE);
            };
            if (challenge.max_rating > 0) {
                assert!(accepter_rating <= challenge.max_rating, E_RATING_OUT_OF_RANGE);
            };
        };

        // Determine colors
        let (white_player, black_player) = if (challenge.challenger_color_pref == COLOR_WHITE) {
            (challenge.challenger, accepter_addr)
        } else if (challenge.challenger_color_pref == COLOR_BLACK) {
            (accepter_addr, challenge.challenger)
        } else {
            // Random based on timestamp
            if ((now_ms % 2) == 0) {
                (challenge.challenger, accepter_addr)
            } else {
                (accepter_addr, challenge.challenger)
            }
        };

        // Create the actual game via chess_game module
        let game_id = chess_game::create_game_internal(
            white_player,
            black_player,
            challenge.time_control_base_seconds,
            challenge.time_control_increment_seconds,
        );

        // Mark challenge as accepted and store game_id
        challenge.status = CHALLENGE_STATUS_ACCEPTED;
        challenge.game_id = game_id;

        // Emit event
        event::emit(ChallengeAcceptedEvent {
            challenge_id,
            challenger: challenge.challenger,
            accepter: accepter_addr,
            game_id,
            white_player,
            black_player,
        });
    }

    /// Cancel own challenge
    public entry fun cancel_challenge(
        challenger: &signer,
        challenge_id: u64,
    ) acquires Lobby {
        let challenger_addr = signer::address_of(challenger);
        let lobby = borrow_global_mut<Lobby>(@chess);

        let (found, idx) = find_challenge_index(&lobby.challenges, challenge_id);
        assert!(found, E_CHALLENGE_NOT_FOUND);

        let challenge = vector::borrow_mut(&mut lobby.challenges, idx);
        assert!(challenge.challenger == challenger_addr, E_NOT_CHALLENGER);
        assert!(challenge.status == CHALLENGE_STATUS_OPEN, E_CHALLENGE_NOT_OPEN);

        challenge.status = CHALLENGE_STATUS_CANCELLED;

        // Emit event
        event::emit(ChallengeCancelledEvent {
            challenge_id,
            challenger: challenger_addr,
        });
    }

    /// Decline a direct challenge (only the targeted opponent can decline)
    public entry fun decline_challenge(
        player: &signer,
        challenge_id: u64,
    ) acquires Lobby {
        let player_addr = signer::address_of(player);
        let lobby = borrow_global_mut<Lobby>(@chess);

        let (found, idx) = find_challenge_index(&lobby.challenges, challenge_id);
        assert!(found, E_CHALLENGE_NOT_FOUND);

        let challenge = vector::borrow_mut(&mut lobby.challenges, idx);

        // Must be a direct challenge targeting this player
        assert!(challenge.opponent == player_addr, E_NOT_THE_OPPONENT);
        assert!(challenge.status == CHALLENGE_STATUS_OPEN, E_CHALLENGE_NOT_OPEN);

        challenge.status = CHALLENGE_STATUS_CANCELLED;

        // Emit event
        event::emit(ChallengeDeclinedEvent {
            challenge_id,
            challenger: challenge.challenger,
            declined_by: player_addr,
        });
    }

    /// Clean up expired challenges (can be called by anyone)
    public entry fun cleanup_expired_challenges() acquires Lobby {
        let lobby = borrow_global_mut<Lobby>(@chess);
        let now_ms = timestamp::now_microseconds() / 1000;

        let len = vector::length(&lobby.challenges);
        let i = 0;
        while (i < len) {
            let challenge = vector::borrow_mut(&mut lobby.challenges, i);
            if (challenge.status == CHALLENGE_STATUS_OPEN && now_ms >= challenge.expires_at_ms) {
                challenge.status = CHALLENGE_STATUS_EXPIRED;
            };
            i = i + 1;
        };
    }

    // ============================================
    // VIEW FUNCTIONS
    // ============================================

    #[view]
    /// Get all open challenges
    public fun get_open_challenges(): vector<Challenge> acquires Lobby {
        let lobby = borrow_global<Lobby>(@chess);
        let now_ms = timestamp::now_microseconds() / 1000;
        let result = vector::empty<Challenge>();

        let len = vector::length(&lobby.challenges);
        let i = 0;
        while (i < len) {
            let c = vector::borrow(&lobby.challenges, i);
            if (c.status == CHALLENGE_STATUS_OPEN && now_ms < c.expires_at_ms) {
                vector::push_back(&mut result, *c);
            };
            i = i + 1;
        };

        result
    }

    #[view]
    /// Get a specific challenge by ID
    public fun get_challenge(challenge_id: u64): Challenge acquires Lobby {
        let lobby = borrow_global<Lobby>(@chess);
        let (found, idx) = find_challenge_index(&lobby.challenges, challenge_id);
        assert!(found, E_CHALLENGE_NOT_FOUND);
        *vector::borrow(&lobby.challenges, idx)
    }

    #[view]
    /// Get challenges created by a player
    public fun get_player_challenges(player: address): vector<Challenge> acquires Lobby {
        let lobby = borrow_global<Lobby>(@chess);
        let result = vector::empty<Challenge>();

        let len = vector::length(&lobby.challenges);
        let i = 0;
        while (i < len) {
            let c = vector::borrow(&lobby.challenges, i);
            if (c.challenger == player && c.status == CHALLENGE_STATUS_OPEN) {
                vector::push_back(&mut result, *c);
            };
            i = i + 1;
        };

        result
    }

    #[view]
    /// Get direct challenges for a player (where they are the opponent)
    public fun get_challenges_for_player(player: address): vector<Challenge> acquires Lobby {
        let lobby = borrow_global<Lobby>(@chess);
        let now_ms = timestamp::now_microseconds() / 1000;
        let result = vector::empty<Challenge>();

        let len = vector::length(&lobby.challenges);
        let i = 0;
        while (i < len) {
            let c = vector::borrow(&lobby.challenges, i);
            if (c.opponent == player && c.status == CHALLENGE_STATUS_OPEN && now_ms < c.expires_at_ms) {
                vector::push_back(&mut result, *c);
            };
            i = i + 1;
        };

        result
    }

    #[view]
    /// Get challenges by time control
    public fun get_challenges_by_time_control(
        base_seconds: u64,
        increment_seconds: u64,
    ): vector<Challenge> acquires Lobby {
        let lobby = borrow_global<Lobby>(@chess);
        let now_ms = timestamp::now_microseconds() / 1000;
        let result = vector::empty<Challenge>();

        let len = vector::length(&lobby.challenges);
        let i = 0;
        while (i < len) {
            let c = vector::borrow(&lobby.challenges, i);
            if (c.status == CHALLENGE_STATUS_OPEN &&
                now_ms < c.expires_at_ms &&
                c.time_control_base_seconds == base_seconds &&
                c.time_control_increment_seconds == increment_seconds) {
                vector::push_back(&mut result, *c);
            };
            i = i + 1;
        };

        result
    }

    #[view]
    /// Get total number of open challenges
    public fun get_open_challenge_count(): u64 acquires Lobby {
        let lobby = borrow_global<Lobby>(@chess);
        let now_ms = timestamp::now_microseconds() / 1000;
        let count: u64 = 0;

        let len = vector::length(&lobby.challenges);
        let i = 0;
        while (i < len) {
            let c = vector::borrow(&lobby.challenges, i);
            if (c.status == CHALLENGE_STATUS_OPEN && now_ms < c.expires_at_ms) {
                count = count + 1;
            };
            i = i + 1;
        };

        count
    }

    #[view]
    /// Get the game_id for an accepted challenge
    public fun get_game_id_for_challenge(challenge_id: u64): u64 acquires Lobby {
        let lobby = borrow_global<Lobby>(@chess);
        let (found, idx) = find_challenge_index(&lobby.challenges, challenge_id);
        assert!(found, E_CHALLENGE_NOT_FOUND);
        let challenge = vector::borrow(&lobby.challenges, idx);
        challenge.game_id
    }

    // ============================================
    // HELPER FUNCTIONS
    // ============================================

    /// Find challenge index by ID
    fun find_challenge_index(challenges: &vector<Challenge>, id: u64): (bool, u64) {
        let len = vector::length(challenges);
        let i = 0;
        while (i < len) {
            if (vector::borrow(challenges, i).challenge_id == id) {
                return (true, i)
            };
            i = i + 1;
        };
        (false, 0)
    }

    /// Count open challenges by a player
    fun count_player_open_challenges(challenges: &vector<Challenge>, player: address): u64 {
        let count: u64 = 0;
        let len = vector::length(challenges);
        let i = 0;
        while (i < len) {
            let c = vector::borrow(challenges, i);
            if (c.challenger == player && c.status == CHALLENGE_STATUS_OPEN) {
                count = count + 1;
            };
            i = i + 1;
        };
        count
    }

    // ============================================
    // ACCESSOR FUNCTIONS FOR CHALLENGE STRUCT
    // ============================================

    #[view]
    /// Get challenge details
    public fun get_challenge_details(challenge_id: u64): (
        address,  // challenger
        address,  // opponent
        u64,      // time_base
        u64,      // time_increment
        u8,       // color_pref
        u8,       // status
        u64,      // expires_at_ms
        u64,      // min_rating
        u64,      // max_rating
        u64,      // game_id
    ) acquires Lobby {
        let challenge = get_challenge(challenge_id);
        (
            challenge.challenger,
            challenge.opponent,
            challenge.time_control_base_seconds,
            challenge.time_control_increment_seconds,
            challenge.challenger_color_pref,
            challenge.status,
            challenge.expires_at_ms,
            challenge.min_rating,
            challenge.max_rating,
            challenge.game_id,
        )
    }

    // ============================================
    // UNIT TESTS
    // ============================================

    #[test_only]
    use aptos_framework::account;

    #[test_only]
    fun setup_test(deployer: &signer) {
        timestamp::set_time_has_started_for_testing(&account::create_signer_for_test(@0x1));
        init_module_for_test(deployer);
        chess_leaderboard::init_module_for_test(deployer);
        chess_game::init_module_for_test(deployer);
    }

    #[test(deployer = @chess, player1 = @0x123)]
    fun test_create_open_challenge(deployer: &signer, player1: &signer) acquires Lobby {
        setup_test(deployer);
        chess_leaderboard::register_player(player1);

        create_open_challenge(player1, 300, 5, COLOR_RANDOM, 0, 0, 3600);

        let challenges = get_open_challenges();
        assert!(vector::length(&challenges) == 1, 1);

        let challenge = vector::borrow(&challenges, 0);
        assert!(challenge.challenger == signer::address_of(player1), 2);
        assert!(challenge.time_control_base_seconds == 300, 3);
        assert!(challenge.time_control_increment_seconds == 5, 4);
        assert!(challenge.status == CHALLENGE_STATUS_OPEN, 5);
    }

    #[test(deployer = @chess, player1 = @0x123, player2 = @0x456)]
    fun test_create_direct_challenge(deployer: &signer, player1: &signer, player2: &signer) acquires Lobby {
        setup_test(deployer);
        chess_leaderboard::register_player(player1);
        chess_leaderboard::register_player(player2);

        let p2_addr = signer::address_of(player2);
        create_direct_challenge(player1, p2_addr, 600, 0, COLOR_WHITE, 3600);

        let challenges = get_challenges_for_player(p2_addr);
        assert!(vector::length(&challenges) == 1, 1);

        let challenge = vector::borrow(&challenges, 0);
        assert!(challenge.opponent == p2_addr, 2);
        assert!(challenge.challenger_color_pref == COLOR_WHITE, 3);
    }

    #[test(deployer = @chess, player1 = @0x123)]
    #[expected_failure(abort_code = E_CANNOT_CHALLENGE_SELF)]
    fun test_create_direct_challenge_self_fails(deployer: &signer, player1: &signer) acquires Lobby {
        setup_test(deployer);
        chess_leaderboard::register_player(player1);

        let p1_addr = signer::address_of(player1);
        // Should fail - can't challenge yourself
        create_direct_challenge(player1, p1_addr, 300, 0, COLOR_RANDOM, 3600);
    }

    #[test(deployer = @chess, player1 = @0x123, player2 = @0x456)]
    fun test_accept_challenge(deployer: &signer, player1: &signer, player2: &signer) acquires Lobby {
        setup_test(deployer);
        chess_leaderboard::register_player(player1);
        chess_leaderboard::register_player(player2);

        create_open_challenge(player1, 300, 5, COLOR_RANDOM, 0, 0, 3600);

        // Get challenge ID
        let challenges = get_open_challenges();
        let challenge_id = vector::borrow(&challenges, 0).challenge_id;

        // Accept challenge
        accept_challenge(player2, challenge_id);

        // Challenge should no longer be open
        let open_challenges = get_open_challenges();
        assert!(vector::length(&open_challenges) == 0, 1);

        // Game should be created
        let game_id = get_game_id_for_challenge(challenge_id);
        assert!(game_id > 0, 2);
        assert!(chess_game::game_exists(game_id), 3);
    }

    #[test(deployer = @chess, player1 = @0x123)]
    #[expected_failure(abort_code = E_CANNOT_ACCEPT_OWN)]
    fun test_accept_own_challenge_fails(deployer: &signer, player1: &signer) acquires Lobby {
        setup_test(deployer);
        chess_leaderboard::register_player(player1);

        create_open_challenge(player1, 300, 5, COLOR_RANDOM, 0, 0, 3600);

        let challenges = get_open_challenges();
        let challenge_id = vector::borrow(&challenges, 0).challenge_id;

        // Should fail - can't accept own challenge
        accept_challenge(player1, challenge_id);
    }

    #[test(deployer = @chess, player1 = @0x123)]
    fun test_cancel_challenge(deployer: &signer, player1: &signer) acquires Lobby {
        setup_test(deployer);
        chess_leaderboard::register_player(player1);

        create_open_challenge(player1, 300, 5, COLOR_RANDOM, 0, 0, 3600);

        let challenges = get_open_challenges();
        let challenge_id = vector::borrow(&challenges, 0).challenge_id;

        cancel_challenge(player1, challenge_id);

        // Challenge should no longer be open
        let open_challenges = get_open_challenges();
        assert!(vector::length(&open_challenges) == 0, 1);
    }

    #[test(deployer = @chess, player1 = @0x123, player2 = @0x456)]
    #[expected_failure(abort_code = E_NOT_CHALLENGER)]
    fun test_cancel_other_challenge_fails(deployer: &signer, player1: &signer, player2: &signer) acquires Lobby {
        setup_test(deployer);
        chess_leaderboard::register_player(player1);
        chess_leaderboard::register_player(player2);

        create_open_challenge(player1, 300, 5, COLOR_RANDOM, 0, 0, 3600);

        let challenges = get_open_challenges();
        let challenge_id = vector::borrow(&challenges, 0).challenge_id;

        // Should fail - player2 is not the challenger
        cancel_challenge(player2, challenge_id);
    }

    #[test(deployer = @chess, player1 = @0x123, player2 = @0x456)]
    fun test_decline_direct_challenge(deployer: &signer, player1: &signer, player2: &signer) acquires Lobby {
        setup_test(deployer);
        chess_leaderboard::register_player(player1);
        chess_leaderboard::register_player(player2);

        let p2_addr = signer::address_of(player2);
        create_direct_challenge(player1, p2_addr, 300, 0, COLOR_RANDOM, 3600);

        let challenges = get_challenges_for_player(p2_addr);
        let challenge_id = vector::borrow(&challenges, 0).challenge_id;

        decline_challenge(player2, challenge_id);

        // Challenge should no longer be open
        let challenges = get_challenges_for_player(p2_addr);
        assert!(vector::length(&challenges) == 0, 1);
    }

    #[test(deployer = @chess, player1 = @0x123, player2 = @0x456)]
    #[expected_failure(abort_code = E_NOT_THE_OPPONENT)]
    fun test_decline_open_challenge_fails(deployer: &signer, player1: &signer, player2: &signer) acquires Lobby {
        setup_test(deployer);
        chess_leaderboard::register_player(player1);
        chess_leaderboard::register_player(player2);

        // Create open challenge (not directed at player2)
        create_open_challenge(player1, 300, 5, COLOR_RANDOM, 0, 0, 3600);

        let challenges = get_open_challenges();
        let challenge_id = vector::borrow(&challenges, 0).challenge_id;

        // Should fail - open challenges can't be declined, only accepted
        decline_challenge(player2, challenge_id);
    }

    #[test(deployer = @chess, player1 = @0x123, player2 = @0x456, player3 = @0x789)]
    #[expected_failure(abort_code = E_WRONG_OPPONENT)]
    fun test_accept_direct_challenge_wrong_player_fails(deployer: &signer, player1: &signer, player2: &signer, player3: &signer) acquires Lobby {
        setup_test(deployer);
        chess_leaderboard::register_player(player1);
        chess_leaderboard::register_player(player2);
        chess_leaderboard::register_player(player3);

        let p2_addr = signer::address_of(player2);
        create_direct_challenge(player1, p2_addr, 300, 0, COLOR_RANDOM, 3600);

        let challenges = get_challenges_for_player(p2_addr);
        let challenge_id = vector::borrow(&challenges, 0).challenge_id;

        // Should fail - player3 is not the designated opponent
        accept_challenge(player3, challenge_id);
    }

    #[test(deployer = @chess, player1 = @0x123)]
    fun test_challenge_limit(deployer: &signer, player1: &signer) acquires Lobby {
        setup_test(deployer);
        chess_leaderboard::register_player(player1);

        // Create 5 challenges (the limit)
        let i = 0;
        while (i < 5) {
            create_open_challenge(player1, 300, 5, COLOR_RANDOM, 0, 0, 3600);
            i = i + 1;
        };

        let challenges = get_player_challenges(signer::address_of(player1));
        assert!(vector::length(&challenges) == 5, 1);
    }

    #[test(deployer = @chess, player1 = @0x123)]
    #[expected_failure(abort_code = E_TOO_MANY_CHALLENGES)]
    fun test_challenge_limit_exceeded_fails(deployer: &signer, player1: &signer) acquires Lobby {
        setup_test(deployer);
        chess_leaderboard::register_player(player1);

        // Create 5 challenges (the limit)
        let i = 0;
        while (i < 5) {
            create_open_challenge(player1, 300, 5, COLOR_RANDOM, 0, 0, 3600);
            i = i + 1;
        };

        // 6th challenge should fail
        create_open_challenge(player1, 300, 5, COLOR_RANDOM, 0, 0, 3600);
    }

    #[test(deployer = @chess, player1 = @0x123)]
    #[expected_failure(abort_code = E_NOT_REGISTERED)]
    fun test_unregistered_player_cannot_create_challenge(deployer: &signer, player1: &signer) acquires Lobby {
        setup_test(deployer);
        // player1 is not registered

        // Should fail
        create_open_challenge(player1, 300, 5, COLOR_RANDOM, 0, 0, 3600);
    }

    #[test(deployer = @chess, player1 = @0x123)]
    fun test_get_open_challenge_count(deployer: &signer, player1: &signer) acquires Lobby {
        setup_test(deployer);
        chess_leaderboard::register_player(player1);

        assert!(get_open_challenge_count() == 0, 1);

        create_open_challenge(player1, 300, 5, COLOR_RANDOM, 0, 0, 3600);
        assert!(get_open_challenge_count() == 1, 2);

        create_open_challenge(player1, 600, 10, COLOR_RANDOM, 0, 0, 3600);
        assert!(get_open_challenge_count() == 2, 3);
    }

    #[test(deployer = @chess, player1 = @0x123)]
    fun test_get_challenges_by_time_control(deployer: &signer, player1: &signer) acquires Lobby {
        setup_test(deployer);
        chess_leaderboard::register_player(player1);

        create_open_challenge(player1, 300, 5, COLOR_RANDOM, 0, 0, 3600);
        create_open_challenge(player1, 600, 10, COLOR_RANDOM, 0, 0, 3600);
        create_open_challenge(player1, 300, 5, COLOR_RANDOM, 0, 0, 3600);

        let blitz_challenges = get_challenges_by_time_control(300, 5);
        assert!(vector::length(&blitz_challenges) == 2, 1);

        let rapid_challenges = get_challenges_by_time_control(600, 10);
        assert!(vector::length(&rapid_challenges) == 1, 2);
    }

    #[test(deployer = @chess)]
    #[expected_failure(abort_code = E_CHALLENGE_NOT_FOUND)]
    fun test_get_nonexistent_challenge_fails(deployer: &signer) acquires Lobby {
        setup_test(deployer);

        // Challenge 999 doesn't exist - access it to trigger the error
        let challenge = get_challenge(999);
        // Use the value to avoid unused warning
        assert!(challenge.challenge_id == 999, 1);
    }

    #[test(deployer = @chess, player1 = @0x123, player2 = @0x456)]
    fun test_color_assignment_white_preference(deployer: &signer, player1: &signer, player2: &signer) acquires Lobby {
        setup_test(deployer);
        chess_leaderboard::register_player(player1);
        chess_leaderboard::register_player(player2);

        // Create challenge with white color preference
        create_open_challenge(player1, 300, 5, COLOR_WHITE, 0, 0, 3600);

        let challenges = get_open_challenges();
        let challenge_id = vector::borrow(&challenges, 0).challenge_id;

        accept_challenge(player2, challenge_id);

        // Verify game was created with correct colors
        let game_id = get_game_id_for_challenge(challenge_id);
        let (_, white_player, black_player, _, _, _, _, _, _, _, _, _) = chess_game::get_game_state(game_id);
        assert!(white_player == signer::address_of(player1), 1);
        assert!(black_player == signer::address_of(player2), 2);
    }

    #[test(deployer = @chess, player1 = @0x123, player2 = @0x456)]
    fun test_color_assignment_black_preference(deployer: &signer, player1: &signer, player2: &signer) acquires Lobby {
        setup_test(deployer);
        chess_leaderboard::register_player(player1);
        chess_leaderboard::register_player(player2);

        // Create challenge with black color preference
        create_open_challenge(player1, 300, 5, COLOR_BLACK, 0, 0, 3600);

        let challenges = get_open_challenges();
        let challenge_id = vector::borrow(&challenges, 0).challenge_id;

        accept_challenge(player2, challenge_id);

        // Verify game was created with correct colors
        let game_id = get_game_id_for_challenge(challenge_id);
        let (_, white_player, black_player, _, _, _, _, _, _, _, _, _) = chess_game::get_game_state(game_id);
        assert!(white_player == signer::address_of(player2), 1);
        assert!(black_player == signer::address_of(player1), 2);
    }
}
