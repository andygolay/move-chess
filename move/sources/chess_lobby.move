module chess::chess_lobby {
    use std::signer;
    use std::vector;
    use aptos_framework::timestamp;
    use aptos_framework::event;
    use chess::chess_leaderboard;

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

        // Verify both players are registered
        assert!(chess_leaderboard::is_registered(challenger_addr), E_NOT_REGISTERED);
        assert!(chess_leaderboard::is_registered(opponent), E_NOT_REGISTERED);

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

    /// Accept a challenge - returns the game_id
    /// Note: The actual game creation happens in chess_game module
    /// This function validates and marks the challenge as accepted
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

        // Mark challenge as accepted
        // The game_id will be set by chess_game module
        challenge.status = CHALLENGE_STATUS_ACCEPTED;

        // For now, use challenge_id as game_id placeholder
        // The actual game creation should be done by calling chess_game::create_game
        let game_id = challenge_id; // Placeholder - real implementation calls chess_game
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
        )
    }
}
