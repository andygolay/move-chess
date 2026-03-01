module chess::chess_leaderboard {
    use std::signer;
    use std::vector;
    use aptos_framework::timestamp;
    use aptos_framework::event;

    // ============================================
    // CONSTANTS
    // ============================================
    const INITIAL_RATING: u64 = 1200;
    const K_FACTOR_NEW: u64 = 40;       // < 30 games
    const K_FACTOR_NORMAL: u64 = 20;    // 30+ games
    const K_FACTOR_HIGH: u64 = 10;      // 2400+ rating
    const NEW_PLAYER_THRESHOLD: u64 = 30;
    const HIGH_RATING_THRESHOLD: u64 = 2400;
    const MIN_RATING: u64 = 100;

    // Game result constants
    const RESULT_WHITE_WIN: u8 = 1;
    const RESULT_BLACK_WIN: u8 = 2;
    const RESULT_DRAW: u8 = 3;

    // Error codes
    const E_ALREADY_REGISTERED: u64 = 1;
    const E_NOT_REGISTERED: u64 = 2;
    const E_NOT_INITIALIZED: u64 = 3;

    // ============================================
    // STRUCTS
    // ============================================

    /// Player statistics and rating
    struct PlayerStats has key, store, copy, drop {
        player: address,
        rating: u64,
        games_played: u64,
        wins: u64,
        losses: u64,
        draws: u64,
        highest_rating: u64,
        current_win_streak: u64,
        current_loss_streak: u64,
        best_win_streak: u64,
        registered_at_ms: u64,
        last_game_at_ms: u64,
    }

    /// Global leaderboard state
    struct Leaderboard has key {
        players: vector<address>,
        total_games_played: u64,
    }

    // Events
    #[event]
    struct PlayerRegisteredEvent has drop, store {
        player: address,
        initial_rating: u64,
        timestamp_ms: u64,
    }

    #[event]
    struct RatingUpdatedEvent has drop, store {
        player: address,
        old_rating: u64,
        new_rating: u64,
        game_result: u8,
        timestamp_ms: u64,
    }

    // ============================================
    // INITIALIZATION
    // ============================================

    /// Automatically called when module is published
    fun init_module(deployer: &signer) {
        move_to(deployer, Leaderboard {
            players: vector::empty(),
            total_games_played: 0,
        });
    }

    // ============================================
    // ENTRY FUNCTIONS
    // ============================================

    /// Register a new player with initial rating
    public entry fun register_player(player: &signer) acquires Leaderboard {
        let player_addr = signer::address_of(player);
        assert!(!exists<PlayerStats>(player_addr), E_ALREADY_REGISTERED);

        let now_ms = timestamp::now_microseconds() / 1000;

        let stats = PlayerStats {
            player: player_addr,
            rating: INITIAL_RATING,
            games_played: 0,
            wins: 0,
            losses: 0,
            draws: 0,
            highest_rating: INITIAL_RATING,
            current_win_streak: 0,
            current_loss_streak: 0,
            best_win_streak: 0,
            registered_at_ms: now_ms,
            last_game_at_ms: 0,
        };

        move_to(player, stats);

        // Add to leaderboard
        let leaderboard = borrow_global_mut<Leaderboard>(@chess);
        vector::push_back(&mut leaderboard.players, player_addr);

        // Emit event
        event::emit(PlayerRegisteredEvent {
            player: player_addr,
            initial_rating: INITIAL_RATING,
            timestamp_ms: now_ms,
        });
    }

    // ============================================
    // FRIEND/PUBLIC FUNCTIONS (called by chess_game)
    // ============================================

    /// Update ratings after a game completes
    /// result: 1 = white wins, 2 = black wins, 3 = draw
    public entry fun update_ratings_after_game(
        _caller: &signer,
        white_player: address,
        black_player: address,
        result: u8,
    ) acquires PlayerStats, Leaderboard {
        update_ratings_internal(white_player, black_player, result);
    }

    /// Internal function to update ratings (can be called by friend modules)
    public fun update_ratings_internal(
        white_player: address,
        black_player: address,
        result: u8,
    ) acquires PlayerStats, Leaderboard {
        assert!(exists<PlayerStats>(white_player), E_NOT_REGISTERED);
        assert!(exists<PlayerStats>(black_player), E_NOT_REGISTERED);

        // First, read black player's data into local variables (to avoid borrow conflict)
        let black_old_rating;
        let black_games_played;
        {
            let black_stats_ref = borrow_global<PlayerStats>(black_player);
            black_old_rating = black_stats_ref.rating;
            black_games_played = black_stats_ref.games_played;
        };

        // Now read and update white player
        let white_old_rating;
        let white_new;
        let black_new;
        let white_won;
        let black_won;
        let now_ms = timestamp::now_microseconds() / 1000;

        {
            let white_stats = borrow_global_mut<PlayerStats>(white_player);
            white_old_rating = white_stats.rating;

            // Calculate expected scores (scaled by 100)
            let (white_expected, black_expected) = calculate_expected_scores(white_old_rating, black_old_rating);

            // Get K-factors
            let white_k = get_k_factor_internal(white_stats.games_played, white_stats.rating);
            let black_k = get_k_factor_internal(black_games_played, black_old_rating);

            // Determine actual scores (scaled by 100)
            let (white_actual, black_actual, w_won, b_won, _is_draw) = if (result == RESULT_WHITE_WIN) {
                (100u64, 0u64, true, false, false)
            } else if (result == RESULT_BLACK_WIN) {
                (0u64, 100u64, false, true, false)
            } else {
                (50u64, 50u64, false, false, true)
            };
            white_won = w_won;
            black_won = b_won;

            // Calculate new ratings
            white_new = calculate_new_rating(white_old_rating, white_k, white_expected, white_actual);
            black_new = calculate_new_rating(black_old_rating, black_k, black_expected, black_actual);

            // Update white stats
            white_stats.rating = white_new;
            white_stats.games_played = white_stats.games_played + 1;
            white_stats.last_game_at_ms = now_ms;
            if (white_new > white_stats.highest_rating) {
                white_stats.highest_rating = white_new;
            };
            if (white_won) {
                white_stats.wins = white_stats.wins + 1;
                white_stats.current_win_streak = white_stats.current_win_streak + 1;
                white_stats.current_loss_streak = 0;
                if (white_stats.current_win_streak > white_stats.best_win_streak) {
                    white_stats.best_win_streak = white_stats.current_win_streak;
                };
            } else if (black_won) {
                white_stats.losses = white_stats.losses + 1;
                white_stats.current_loss_streak = white_stats.current_loss_streak + 1;
                white_stats.current_win_streak = 0;
            } else {
                white_stats.draws = white_stats.draws + 1;
                white_stats.current_win_streak = 0;
                white_stats.current_loss_streak = 0;
            };
        };

        // Emit white rating event
        event::emit(RatingUpdatedEvent {
            player: white_player,
            old_rating: white_old_rating,
            new_rating: white_new,
            game_result: if (white_won) { 1 } else if (black_won) { 0 } else { 2 },
            timestamp_ms: now_ms,
        });

        // Now update black stats
        let black_stats = borrow_global_mut<PlayerStats>(black_player);
        black_stats.rating = black_new;
        black_stats.games_played = black_stats.games_played + 1;
        black_stats.last_game_at_ms = now_ms;
        if (black_new > black_stats.highest_rating) {
            black_stats.highest_rating = black_new;
        };
        if (black_won) {
            black_stats.wins = black_stats.wins + 1;
            black_stats.current_win_streak = black_stats.current_win_streak + 1;
            black_stats.current_loss_streak = 0;
            if (black_stats.current_win_streak > black_stats.best_win_streak) {
                black_stats.best_win_streak = black_stats.current_win_streak;
            };
        } else if (white_won) {
            black_stats.losses = black_stats.losses + 1;
            black_stats.current_loss_streak = black_stats.current_loss_streak + 1;
            black_stats.current_win_streak = 0;
        } else {
            black_stats.draws = black_stats.draws + 1;
            black_stats.current_win_streak = 0;
            black_stats.current_loss_streak = 0;
        };

        // Emit black rating event
        event::emit(RatingUpdatedEvent {
            player: black_player,
            old_rating: black_old_rating,
            new_rating: black_new,
            game_result: if (black_won) { 1 } else if (white_won) { 0 } else { 2 },
            timestamp_ms: now_ms,
        });

        // Update total games
        let leaderboard = borrow_global_mut<Leaderboard>(@chess);
        leaderboard.total_games_played = leaderboard.total_games_played + 1;
    }

    // ============================================
    // VIEW FUNCTIONS
    // ============================================

    #[view]
    /// Get player statistics
    public fun get_player_stats(player: address): PlayerStats acquires PlayerStats {
        assert!(exists<PlayerStats>(player), E_NOT_REGISTERED);
        *borrow_global<PlayerStats>(player)
    }

    #[view]
    /// Get player rating
    public fun get_rating(player: address): u64 acquires PlayerStats {
        assert!(exists<PlayerStats>(player), E_NOT_REGISTERED);
        borrow_global<PlayerStats>(player).rating
    }

    #[view]
    /// Check if player is registered
    public fun is_registered(player: address): bool {
        exists<PlayerStats>(player)
    }

    #[view]
    /// Get top N players by rating
    public fun get_top_players(limit: u64): vector<PlayerStats> acquires Leaderboard, PlayerStats {
        let leaderboard = borrow_global<Leaderboard>(@chess);
        let result = vector::empty<PlayerStats>();

        // Collect all player stats
        let all_stats = vector::empty<PlayerStats>();
        let len = vector::length(&leaderboard.players);
        let i = 0;
        while (i < len) {
            let addr = *vector::borrow(&leaderboard.players, i);
            if (exists<PlayerStats>(addr)) {
                vector::push_back(&mut all_stats, *borrow_global<PlayerStats>(addr));
            };
            i = i + 1;
        };

        // Sort by rating (descending) - simple bubble sort
        let total = vector::length(&all_stats);
        if (total > 1) {
            let i = 0;
            while (i < total - 1) {
                let j = 0;
                while (j < total - 1 - i) {
                    let a_rating = vector::borrow(&all_stats, j).rating;
                    let b_rating = vector::borrow(&all_stats, j + 1).rating;
                    if (a_rating < b_rating) {
                        vector::swap(&mut all_stats, j, j + 1);
                    };
                    j = j + 1;
                };
                i = i + 1;
            };
        };

        // Take top N
        let count = if (limit < total) { limit } else { total };
        let i = 0;
        while (i < count) {
            vector::push_back(&mut result, *vector::borrow(&all_stats, i));
            i = i + 1;
        };

        result
    }

    #[view]
    /// Get player's rank on leaderboard
    public fun get_player_rank(player: address): u64 acquires Leaderboard, PlayerStats {
        assert!(exists<PlayerStats>(player), E_NOT_REGISTERED);
        let player_rating = borrow_global<PlayerStats>(player).rating;
        let leaderboard = borrow_global<Leaderboard>(@chess);

        let rank: u64 = 1;
        let len = vector::length(&leaderboard.players);
        let i = 0;
        while (i < len) {
            let addr = *vector::borrow(&leaderboard.players, i);
            if (addr != player && exists<PlayerStats>(addr)) {
                let other_rating = borrow_global<PlayerStats>(addr).rating;
                if (other_rating > player_rating) {
                    rank = rank + 1;
                };
            };
            i = i + 1;
        };

        rank
    }

    #[view]
    /// Get total registered players
    public fun get_total_players(): u64 acquires Leaderboard {
        let leaderboard = borrow_global<Leaderboard>(@chess);
        vector::length(&leaderboard.players)
    }

    #[view]
    /// Get total games played
    public fun get_total_games(): u64 acquires Leaderboard {
        let leaderboard = borrow_global<Leaderboard>(@chess);
        leaderboard.total_games_played
    }

    // ============================================
    // INTERNAL FUNCTIONS
    // ============================================

    /// Calculate expected scores using ELO formula
    /// Returns (white_expected, black_expected) scaled by 100
    fun calculate_expected_scores(white_rating: u64, black_rating: u64): (u64, u64) {
        let diff = if (white_rating > black_rating) {
            white_rating - black_rating
        } else {
            black_rating - white_rating
        };

        // Lookup table for expected score based on rating difference
        let expected_higher = if (diff >= 800) { 99 }
            else if (diff >= 600) { 97 }
            else if (diff >= 500) { 95 }
            else if (diff >= 400) { 91 }
            else if (diff >= 350) { 88 }
            else if (diff >= 300) { 85 }
            else if (diff >= 250) { 81 }
            else if (diff >= 200) { 76 }
            else if (diff >= 150) { 70 }
            else if (diff >= 100) { 64 }
            else if (diff >= 50) { 57 }
            else { 50 };

        if (white_rating >= black_rating) {
            (expected_higher, 100 - expected_higher)
        } else {
            (100 - expected_higher, expected_higher)
        }
    }

    /// Get K-factor based on games played and rating
    fun get_k_factor_internal(games_played: u64, rating: u64): u64 {
        if (games_played < NEW_PLAYER_THRESHOLD) {
            K_FACTOR_NEW
        } else if (rating >= HIGH_RATING_THRESHOLD) {
            K_FACTOR_HIGH
        } else {
            K_FACTOR_NORMAL
        }
    }

    /// Calculate new rating after a game
    fun calculate_new_rating(
        current: u64,
        k: u64,
        expected: u64,
        actual: u64,
    ): u64 {
        if (actual >= expected) {
            let gain = (k * (actual - expected)) / 100;
            current + gain
        } else {
            let loss = (k * (expected - actual)) / 100;
            if (loss >= current || current - loss < MIN_RATING) {
                MIN_RATING
            } else {
                current - loss
            }
        }
    }
}
