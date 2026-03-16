module chess::chess_game {
    use std::signer;
    use std::vector;
    use aptos_framework::timestamp;
    use aptos_framework::event;
    use aptos_std::big_ordered_map::{Self, BigOrderedMap};
    use chess::chess_leaderboard;

    // ============================================
    // PIECE TYPE CONSTANTS
    // ============================================
    const PIECE_NONE: u8 = 0;
    const PIECE_PAWN: u8 = 1;
    const PIECE_KNIGHT: u8 = 2;
    const PIECE_BISHOP: u8 = 3;
    const PIECE_ROOK: u8 = 4;
    const PIECE_QUEEN: u8 = 5;
    const PIECE_KING: u8 = 6;

    // ============================================
    // COLOR CONSTANTS
    // ============================================
    const COLOR_NONE: u8 = 0;
    const COLOR_WHITE: u8 = 1;
    const COLOR_BLACK: u8 = 2;

    // ============================================
    // GAME STATUS CONSTANTS
    // ============================================
    const STATUS_ACTIVE: u8 = 1;
    const STATUS_WHITE_WIN_CHECKMATE: u8 = 2;
    const STATUS_BLACK_WIN_CHECKMATE: u8 = 3;
    const STATUS_DRAW_STALEMATE: u8 = 4;
    const STATUS_DRAW_AGREEMENT: u8 = 5;
    const STATUS_DRAW_50_MOVE: u8 = 6;
    const STATUS_DRAW_INSUFFICIENT: u8 = 7;
    const STATUS_WHITE_WIN_TIMEOUT: u8 = 8;
    const STATUS_BLACK_WIN_TIMEOUT: u8 = 9;
    const STATUS_WHITE_WIN_RESIGNATION: u8 = 10;
    const STATUS_BLACK_WIN_RESIGNATION: u8 = 11;
    const STATUS_DRAW_REPETITION: u8 = 12;

    // ============================================
    // ERROR CODES
    // ============================================
    const E_NOT_INITIALIZED: u64 = 1;
    const E_ALREADY_INITIALIZED: u64 = 2;
    const E_GAME_NOT_FOUND: u64 = 3;
    const E_NOT_YOUR_TURN: u64 = 4;
    const E_INVALID_MOVE: u64 = 5;
    const E_GAME_NOT_ACTIVE: u64 = 6;
    const E_NOT_A_PLAYER: u64 = 7;
    const E_NO_PIECE_AT_SQUARE: u64 = 8;
    const E_WRONG_COLOR_PIECE: u64 = 9;
    const E_KING_IN_CHECK_AFTER_MOVE: u64 = 10;
    const E_INVALID_PROMOTION: u64 = 11;
    const E_TIMEOUT_NOT_REACHED: u64 = 12;
    const E_NO_DRAW_OFFER: u64 = 13;
    const E_CANNOT_CAPTURE_OWN: u64 = 14;
    const E_SAME_PLAYER: u64 = 15;
    const E_INVALID_TIME_CONTROL: u64 = 16;
    const E_INVALID_SQUARE: u64 = 17;
    const E_PROMOTION_REQUIRED: u64 = 18;
    const E_NO_DRAW_OFFER_TO_CANCEL: u64 = 19;

    // Time control limits
    const MIN_TIME_BASE_SECONDS: u64 = 30;      // 30 seconds minimum
    const MAX_TIME_BASE_SECONDS: u64 = 10800;   // 3 hours maximum
    const MAX_TIME_INCREMENT_SECONDS: u64 = 60; // 60 seconds max increment

    // ============================================
    // STRONGLY-TYPED STRUCTS
    // ============================================

    /// Represents a single square on the chess board
    struct Square has store, copy, drop {
        piece_type: u8,
        color: u8,
    }

    /// Castling rights for both players
    struct CastlingRights has store, copy, drop {
        white_kingside: bool,
        white_queenside: bool,
        black_kingside: bool,
        black_queenside: bool,
    }

    /// Time control state
    struct TimeControl has store, copy, drop {
        base_time_ms: u64,
        increment_ms: u64,
        white_time_remaining_ms: u64,
        black_time_remaining_ms: u64,
        last_move_timestamp_ms: u64,
    }

    /// Move record for history
    struct MoveRecord has store, copy, drop {
        from_square: u8,
        to_square: u8,
        piece_type: u8,
        captured_piece: u8,
        promotion_piece: u8,
        is_castling: bool,
        is_en_passant: bool,
    }

    /// Complete game state
    struct Game has store, copy, drop {
        game_id: u64,
        white_player: address,
        black_player: address,
        board: vector<Square>,
        active_color: u8,
        status: u8,
        castling_rights: CastlingRights,
        en_passant_target: u8,
        halfmove_clock: u64,
        fullmove_number: u64,
        time_control: TimeControl,
        move_history: vector<MoveRecord>,
        created_at_ms: u64,
        draw_offer_by: u8,
        position_history: vector<u64>,  // Simple position hashes for repetition detection
    }

    /// Global game registry using BigOrderedMap for efficient game storage
    struct GameRegistry has key {
        next_game_id: u64,
        games: BigOrderedMap<u64, Game>,
    }

    // Events
    #[event]
    struct GameCreatedEvent has drop, store {
        game_id: u64,
        white_player: address,
        black_player: address,
        time_base_ms: u64,
        time_increment_ms: u64,
    }

    #[event]
    struct MoveMadeEvent has drop, store {
        game_id: u64,
        player: address,
        from_square: u8,
        to_square: u8,
        piece_type: u8,
        is_capture: bool,
        is_check: bool,
        promotion_piece: u8,
    }

    #[event]
    struct GameEndedEvent has drop, store {
        game_id: u64,
        status: u8,
        winner: address,
    }

    #[event]
    struct DrawOfferedEvent has drop, store {
        game_id: u64,
        offered_by: address,
        color: u8,
    }

    #[event]
    struct DrawOfferCancelledEvent has drop, store {
        game_id: u64,
        cancelled_by: address,
    }

    // ============================================
    // INITIALIZATION
    // ============================================

    /// Automatically called when module is published
    fun init_module(deployer: &signer) {
        move_to(deployer, GameRegistry {
            next_game_id: 1,
            // Use new_with_config with 0,0 to let it auto-compute degrees based on key/value sizes
            games: big_ordered_map::new_with_config(0, 0, false),
        });
    }

    #[test_only]
    /// Initialize for testing
    public fun init_module_for_test(deployer: &signer) {
        init_module(deployer);
    }

    // ============================================
    // BOARD HELPERS
    // ============================================

    fun empty_square(): Square {
        Square { piece_type: PIECE_NONE, color: COLOR_NONE }
    }

    fun new_square(piece_type: u8, color: u8): Square {
        Square { piece_type, color }
    }

    fun is_empty(square: &Square): bool {
        square.piece_type == PIECE_NONE
    }

    fun get_square(board: &vector<Square>, index: u8): Square {
        assert!(index < 64, E_INVALID_SQUARE);
        *vector::borrow(board, (index as u64))
    }

    fun set_square(board: &mut vector<Square>, index: u8, square: Square) {
        assert!(index < 64, E_INVALID_SQUARE);
        *vector::borrow_mut(board, (index as u64)) = square;
    }

    fun coords_to_index(row: u8, col: u8): u8 {
        row * 8 + col
    }

    fun index_to_row(index: u8): u8 {
        index / 8
    }

    fun index_to_col(index: u8): u8 {
        index % 8
    }

    fun abs_diff(a: u8, b: u8): u8 {
        if (a > b) { a - b } else { b - a }
    }

    // ============================================
    // INITIAL BOARD SETUP
    // ============================================

    fun initial_board(): vector<Square> {
        let board = vector::empty<Square>();

        // Row 0 (rank 8): Black back rank
        vector::push_back(&mut board, new_square(PIECE_ROOK, COLOR_BLACK));
        vector::push_back(&mut board, new_square(PIECE_KNIGHT, COLOR_BLACK));
        vector::push_back(&mut board, new_square(PIECE_BISHOP, COLOR_BLACK));
        vector::push_back(&mut board, new_square(PIECE_QUEEN, COLOR_BLACK));
        vector::push_back(&mut board, new_square(PIECE_KING, COLOR_BLACK));
        vector::push_back(&mut board, new_square(PIECE_BISHOP, COLOR_BLACK));
        vector::push_back(&mut board, new_square(PIECE_KNIGHT, COLOR_BLACK));
        vector::push_back(&mut board, new_square(PIECE_ROOK, COLOR_BLACK));

        // Row 1 (rank 7): Black pawns
        let i = 0;
        while (i < 8) {
            vector::push_back(&mut board, new_square(PIECE_PAWN, COLOR_BLACK));
            i = i + 1;
        };

        // Rows 2-5 (ranks 6-3): Empty squares
        let i = 0;
        while (i < 32) {
            vector::push_back(&mut board, empty_square());
            i = i + 1;
        };

        // Row 6 (rank 2): White pawns
        let i = 0;
        while (i < 8) {
            vector::push_back(&mut board, new_square(PIECE_PAWN, COLOR_WHITE));
            i = i + 1;
        };

        // Row 7 (rank 1): White back rank
        vector::push_back(&mut board, new_square(PIECE_ROOK, COLOR_WHITE));
        vector::push_back(&mut board, new_square(PIECE_KNIGHT, COLOR_WHITE));
        vector::push_back(&mut board, new_square(PIECE_BISHOP, COLOR_WHITE));
        vector::push_back(&mut board, new_square(PIECE_QUEEN, COLOR_WHITE));
        vector::push_back(&mut board, new_square(PIECE_KING, COLOR_WHITE));
        vector::push_back(&mut board, new_square(PIECE_BISHOP, COLOR_WHITE));
        vector::push_back(&mut board, new_square(PIECE_KNIGHT, COLOR_WHITE));
        vector::push_back(&mut board, new_square(PIECE_ROOK, COLOR_WHITE));

        board
    }

    fun initial_castling_rights(): CastlingRights {
        CastlingRights {
            white_kingside: true,
            white_queenside: true,
            black_kingside: true,
            black_queenside: true,
        }
    }

    // ============================================
    // POSITION HASHING (for repetition detection)
    // ============================================

    /// Simple hash function for position (not cryptographically secure, just for equality checking)
    fun hash_position(board: &vector<Square>, active_color: u8, castling: &CastlingRights, en_passant: u8): u64 {
        let hash: u64 = 0;
        let i: u64 = 0;
        while (i < 64) {
            let sq = vector::borrow(board, i);
            // Combine piece type and color into hash
            hash = hash ^ (((sq.piece_type as u64) * 7 + (sq.color as u64)) << (((i % 8) * 4) as u8));
            if (i % 8 == 7) {
                hash = ((hash << 13) | (hash >> 51)); // Rotate
            };
            i = i + 1;
        };
        // Include game state in hash
        hash = hash ^ ((active_color as u64) << 60);
        hash = hash ^ ((if (castling.white_kingside) { 1u64 } else { 0u64 }) << 56);
        hash = hash ^ ((if (castling.white_queenside) { 1u64 } else { 0u64 }) << 57);
        hash = hash ^ ((if (castling.black_kingside) { 1u64 } else { 0u64 }) << 58);
        hash = hash ^ ((if (castling.black_queenside) { 1u64 } else { 0u64 }) << 59);
        hash = hash ^ ((en_passant as u64) << 48);
        hash
    }

    /// Check for three-fold repetition
    fun is_threefold_repetition(position_history: &vector<u64>, current_hash: u64): bool {
        let count: u64 = 0;
        let len = vector::length(position_history);
        let i = 0;
        while (i < len) {
            if (*vector::borrow(position_history, i) == current_hash) {
                count = count + 1;
                if (count >= 2) {
                    // Current position + 2 previous = 3 total
                    return true
                };
            };
            i = i + 1;
        };
        false
    }

    // ============================================
    // INSUFFICIENT MATERIAL DETECTION
    // ============================================

    /// Check if the position has insufficient material for checkmate
    fun is_insufficient_material(board: &vector<Square>): bool {
        let white_pieces = vector::empty<u8>();
        let black_pieces = vector::empty<u8>();

        let i: u8 = 0;
        while (i < 64) {
            let sq = get_square(board, i);
            if (sq.piece_type != PIECE_NONE && sq.piece_type != PIECE_KING) {
                if (sq.color == COLOR_WHITE) {
                    vector::push_back(&mut white_pieces, sq.piece_type);
                } else {
                    vector::push_back(&mut black_pieces, sq.piece_type);
                };
            };
            i = i + 1;
        };

        let white_count = vector::length(&white_pieces);
        let black_count = vector::length(&black_pieces);

        // King vs King
        if (white_count == 0 && black_count == 0) {
            return true
        };

        // King + minor piece vs King
        if (white_count == 0 && black_count == 1) {
            let piece = *vector::borrow(&black_pieces, 0);
            if (piece == PIECE_KNIGHT || piece == PIECE_BISHOP) {
                return true
            };
        };
        if (black_count == 0 && white_count == 1) {
            let piece = *vector::borrow(&white_pieces, 0);
            if (piece == PIECE_KNIGHT || piece == PIECE_BISHOP) {
                return true
            };
        };

        // King + Bishop vs King + Bishop (same color bishops)
        if (white_count == 1 && black_count == 1) {
            let w_piece = *vector::borrow(&white_pieces, 0);
            let b_piece = *vector::borrow(&black_pieces, 0);
            if (w_piece == PIECE_BISHOP && b_piece == PIECE_BISHOP) {
                // Check if bishops are on same color squares
                let w_bishop_sq = find_piece(board, PIECE_BISHOP, COLOR_WHITE);
                let b_bishop_sq = find_piece(board, PIECE_BISHOP, COLOR_BLACK);
                let w_color = (index_to_row(w_bishop_sq) + index_to_col(w_bishop_sq)) % 2;
                let b_color = (index_to_row(b_bishop_sq) + index_to_col(b_bishop_sq)) % 2;
                if (w_color == b_color) {
                    return true
                };
            };
        };

        false
    }

    /// Find the square of a specific piece
    fun find_piece(board: &vector<Square>, piece_type: u8, color: u8): u8 {
        let i: u8 = 0;
        while (i < 64) {
            let sq = get_square(board, i);
            if (sq.piece_type == piece_type && sq.color == color) {
                return i
            };
            i = i + 1;
        };
        255 // Not found
    }

    // ============================================
    // GAME CREATION
    // ============================================

    /// Internal game creation - returns the game_id
    /// Can be called by chess_lobby module
    public fun create_game_internal(
        white_player: address,
        black_player: address,
        time_base_seconds: u64,
        time_increment_seconds: u64,
    ): u64 acquires GameRegistry {
        // Validate players are different
        assert!(white_player != black_player, E_SAME_PLAYER);

        // Validate time control
        assert!(time_base_seconds >= MIN_TIME_BASE_SECONDS, E_INVALID_TIME_CONTROL);
        assert!(time_base_seconds <= MAX_TIME_BASE_SECONDS, E_INVALID_TIME_CONTROL);
        assert!(time_increment_seconds <= MAX_TIME_INCREMENT_SECONDS, E_INVALID_TIME_CONTROL);

        let registry = borrow_global_mut<GameRegistry>(@chess);

        let game_id = registry.next_game_id;
        registry.next_game_id = game_id + 1;

        let base_time_ms = time_base_seconds * 1000;
        let increment_ms = time_increment_seconds * 1000;
        let now_ms = timestamp::now_microseconds() / 1000;

        let board = initial_board();
        let castling_rights = initial_castling_rights();

        // Calculate initial position hash
        let initial_hash = hash_position(&board, COLOR_WHITE, &castling_rights, 64);
        let position_history = vector::empty<u64>();
        vector::push_back(&mut position_history, initial_hash);

        let game = Game {
            game_id,
            white_player,
            black_player,
            board,
            active_color: COLOR_WHITE,
            status: STATUS_ACTIVE,
            castling_rights,
            en_passant_target: 64,
            halfmove_clock: 0,
            fullmove_number: 1,
            time_control: TimeControl {
                base_time_ms,
                increment_ms,
                white_time_remaining_ms: base_time_ms,
                black_time_remaining_ms: base_time_ms,
                last_move_timestamp_ms: now_ms,
            },
            move_history: vector::empty(),
            created_at_ms: now_ms,
            draw_offer_by: COLOR_NONE,
            position_history,
        };

        big_ordered_map::add(&mut registry.games, game_id, game);

        event::emit(GameCreatedEvent {
            game_id,
            white_player,
            black_player,
            time_base_ms: base_time_ms,
            time_increment_ms: increment_ms,
        });

        game_id
    }

    // ============================================
    // MOVE VALIDATION
    // ============================================

    fun is_valid_pawn_move(
        board: &vector<Square>,
        from: u8,
        to: u8,
        is_white: bool,
        en_passant_target: u8,
    ): bool {
        let from_row = index_to_row(from);
        let from_col = index_to_col(from);
        let to_row = index_to_row(to);
        let to_col = index_to_col(to);
        let to_square = get_square(board, to);

        let col_diff = abs_diff(from_col, to_col);

        if (is_white) {
            // White pawns move up (decreasing row)
            if (to_row >= from_row) {
                return false
            };
            let row_diff = from_row - to_row;

            // Forward one square
            if (col_diff == 0 && row_diff == 1 && is_empty(&to_square)) {
                return true
            };

            // Forward two squares from starting position
            if (col_diff == 0 && row_diff == 2 && from_row == 6) {
                let middle = coords_to_index(from_row - 1, from_col);
                if (is_empty(&get_square(board, middle)) && is_empty(&to_square)) {
                    return true
                };
            };

            // Diagonal capture
            if (col_diff == 1 && row_diff == 1) {
                if (!is_empty(&to_square) && to_square.color == COLOR_BLACK) {
                    return true
                };
                if (to == en_passant_target) {
                    return true
                };
            };
        } else {
            // Black pawns move down (increasing row)
            if (to_row <= from_row) {
                return false
            };
            let row_diff = to_row - from_row;

            // Forward one square
            if (col_diff == 0 && row_diff == 1 && is_empty(&to_square)) {
                return true
            };

            // Forward two squares from starting position
            if (col_diff == 0 && row_diff == 2 && from_row == 1) {
                let middle = coords_to_index(from_row + 1, from_col);
                if (is_empty(&get_square(board, middle)) && is_empty(&to_square)) {
                    return true
                };
            };

            // Diagonal capture
            if (col_diff == 1 && row_diff == 1) {
                if (!is_empty(&to_square) && to_square.color == COLOR_WHITE) {
                    return true
                };
                if (to == en_passant_target) {
                    return true
                };
            };
        };

        false
    }

    fun is_valid_knight_move(from: u8, to: u8): bool {
        let from_row = index_to_row(from);
        let from_col = index_to_col(from);
        let to_row = index_to_row(to);
        let to_col = index_to_col(to);

        let row_diff = abs_diff(from_row, to_row);
        let col_diff = abs_diff(from_col, to_col);

        (row_diff == 2 && col_diff == 1) || (row_diff == 1 && col_diff == 2)
    }

    fun is_diagonal_path_clear(board: &vector<Square>, from: u8, to: u8): bool {
        let from_row = index_to_row(from);
        let from_col = index_to_col(from);
        let to_row = index_to_row(to);
        let to_col = index_to_col(to);

        let row_diff = abs_diff(from_row, to_row);
        let col_diff = abs_diff(from_col, to_col);

        // Must be diagonal
        if (row_diff != col_diff || row_diff == 0) {
            return false
        };

        // Check each square along the diagonal (excluding start and end)
        let steps = row_diff - 1;
        let i = 0;
        while (i < steps) {
            let check_row = if (to_row > from_row) { from_row + 1 + i } else { from_row - 1 - i };
            let check_col = if (to_col > from_col) { from_col + 1 + i } else { from_col - 1 - i };
            let idx = coords_to_index(check_row, check_col);
            if (!is_empty(&get_square(board, idx))) {
                return false
            };
            i = i + 1;
        };

        true
    }

    fun is_straight_path_clear(board: &vector<Square>, from: u8, to: u8): bool {
        let from_row = index_to_row(from);
        let from_col = index_to_col(from);
        let to_row = index_to_row(to);
        let to_col = index_to_col(to);

        // Must be same row or same column
        if (from_row != to_row && from_col != to_col) {
            return false
        };
        if (from == to) {
            return false
        };

        if (from_row == to_row) {
            // Horizontal move
            let start_col = if (from_col < to_col) { from_col + 1 } else { to_col + 1 };
            let end_col = if (from_col < to_col) { to_col } else { from_col };
            let col = start_col;
            while (col < end_col) {
                if (!is_empty(&get_square(board, coords_to_index(from_row, col)))) {
                    return false
                };
                col = col + 1;
            };
        } else {
            // Vertical move
            let start_row = if (from_row < to_row) { from_row + 1 } else { to_row + 1 };
            let end_row = if (from_row < to_row) { to_row } else { from_row };
            let row = start_row;
            while (row < end_row) {
                if (!is_empty(&get_square(board, coords_to_index(row, from_col)))) {
                    return false
                };
                row = row + 1;
            };
        };

        true
    }

    fun is_valid_bishop_move(board: &vector<Square>, from: u8, to: u8): bool {
        is_diagonal_path_clear(board, from, to)
    }

    fun is_valid_rook_move(board: &vector<Square>, from: u8, to: u8): bool {
        is_straight_path_clear(board, from, to)
    }

    fun is_valid_queen_move(board: &vector<Square>, from: u8, to: u8): bool {
        is_valid_bishop_move(board, from, to) || is_valid_rook_move(board, from, to)
    }

    fun is_valid_king_move(
        board: &vector<Square>,
        from: u8,
        to: u8,
        castling_rights: &CastlingRights,
        is_white: bool,
    ): bool {
        let from_row = index_to_row(from);
        let from_col = index_to_col(from);
        let to_row = index_to_row(to);
        let to_col = index_to_col(to);

        let row_diff = abs_diff(from_row, to_row);
        let col_diff = abs_diff(from_col, to_col);

        // Normal king move: one square in any direction
        if (row_diff <= 1 && col_diff <= 1 && (row_diff + col_diff) > 0) {
            return true
        };

        // Castling: king moves two squares horizontally
        if (row_diff == 0 && col_diff == 2) {
            return can_castle(board, from, to, castling_rights, is_white)
        };

        false
    }

    fun can_castle(
        board: &vector<Square>,
        from: u8,
        to: u8,
        castling_rights: &CastlingRights,
        is_white: bool,
    ): bool {
        let to_col = index_to_col(to);
        let from_col = index_to_col(from);
        let is_kingside = to_col > from_col;

        // Check castling rights
        let has_rights = if (is_white) {
            if (is_kingside) { castling_rights.white_kingside } else { castling_rights.white_queenside }
        } else {
            if (is_kingside) { castling_rights.black_kingside } else { castling_rights.black_queenside }
        };
        if (!has_rights) {
            return false
        };

        // Check squares between king and destination are empty
        let row = index_to_row(from);
        if (is_kingside) {
            // Kingside: check f and g files
            if (!is_empty(&get_square(board, coords_to_index(row, 5))) ||
                !is_empty(&get_square(board, coords_to_index(row, 6)))) {
                return false
            };
        } else {
            // Queenside: check b, c, d files
            if (!is_empty(&get_square(board, coords_to_index(row, 1))) ||
                !is_empty(&get_square(board, coords_to_index(row, 2))) ||
                !is_empty(&get_square(board, coords_to_index(row, 3)))) {
                return false
            };
        };

        // Check king is not currently in check
        let king_color = if (is_white) { COLOR_WHITE } else { COLOR_BLACK };
        if (is_king_in_check(board, king_color)) {
            return false
        };

        // Check king doesn't pass through or land on attacked square
        let enemy_color = if (is_white) { COLOR_BLACK } else { COLOR_WHITE };
        let check_col = if (is_kingside) { 5u8 } else { 3u8 };
        if (is_square_attacked(board, coords_to_index(row, check_col), enemy_color)) {
            return false
        };
        if (is_square_attacked(board, to, enemy_color)) {
            return false
        };

        true
    }

    // ============================================
    // CHECK DETECTION
    // ============================================

    fun can_pawn_attack(from: u8, to: u8, is_white: bool): bool {
        let from_row = index_to_row(from);
        let from_col = index_to_col(from);
        let to_row = index_to_row(to);
        let to_col = index_to_col(to);

        let col_diff = abs_diff(from_col, to_col);
        if (col_diff != 1) {
            return false
        };

        if (is_white) {
            // White pawn attacks upward (decreasing row)
            from_row > 0 && to_row == from_row - 1
        } else {
            // Black pawn attacks downward (increasing row)
            from_row < 7 && to_row == from_row + 1
        }
    }

    fun is_square_attacked(board: &vector<Square>, square: u8, by_color: u8): bool {
        let i: u8 = 0;
        while (i < 64) {
            let attacker = get_square(board, i);
            if (attacker.color == by_color) {
                let can_attack = if (attacker.piece_type == PIECE_PAWN) {
                    can_pawn_attack(i, square, by_color == COLOR_WHITE)
                } else if (attacker.piece_type == PIECE_KNIGHT) {
                    is_valid_knight_move(i, square)
                } else if (attacker.piece_type == PIECE_BISHOP) {
                    is_valid_bishop_move(board, i, square)
                } else if (attacker.piece_type == PIECE_ROOK) {
                    is_valid_rook_move(board, i, square)
                } else if (attacker.piece_type == PIECE_QUEEN) {
                    is_valid_queen_move(board, i, square)
                } else if (attacker.piece_type == PIECE_KING) {
                    let row_diff = abs_diff(index_to_row(i), index_to_row(square));
                    let col_diff = abs_diff(index_to_col(i), index_to_col(square));
                    row_diff <= 1 && col_diff <= 1 && (row_diff + col_diff) > 0
                } else {
                    false
                };
                if (can_attack) {
                    return true
                };
            };
            i = i + 1;
        };
        false
    }

    fun find_king(board: &vector<Square>, color: u8): u8 {
        let i: u8 = 0;
        while (i < 64) {
            let sq = get_square(board, i);
            if (sq.piece_type == PIECE_KING && sq.color == color) {
                return i
            };
            i = i + 1;
        };
        255 // Should never happen
    }

    fun is_king_in_check(board: &vector<Square>, color: u8): bool {
        let king_square = find_king(board, color);
        let enemy_color = if (color == COLOR_WHITE) { COLOR_BLACK } else { COLOR_WHITE };
        is_square_attacked(board, king_square, enemy_color)
    }

    // ============================================
    // MOVE EXECUTION
    // ============================================

    fun execute_move(
        board: &mut vector<Square>,
        from: u8,
        to: u8,
        promotion_piece: u8,
        en_passant_target: u8,
    ): Square {
        let from_square = get_square(board, from);
        let to_square = get_square(board, to);
        let captured = to_square;

        // Handle en passant capture
        if (from_square.piece_type == PIECE_PAWN && to == en_passant_target && is_empty(&to_square)) {
            let capture_row = if (from_square.color == COLOR_WHITE) {
                index_to_row(to) + 1
            } else {
                index_to_row(to) - 1
            };
            let capture_square = coords_to_index(capture_row, index_to_col(to));
            captured = get_square(board, capture_square);
            set_square(board, capture_square, empty_square());
        };

        // Handle castling
        if (from_square.piece_type == PIECE_KING && abs_diff(index_to_col(from), index_to_col(to)) == 2) {
            let row = index_to_row(from);
            let is_kingside = index_to_col(to) > index_to_col(from);
            if (is_kingside) {
                // Move rook from h-file to f-file
                let rook = get_square(board, coords_to_index(row, 7));
                set_square(board, coords_to_index(row, 7), empty_square());
                set_square(board, coords_to_index(row, 5), rook);
            } else {
                // Move rook from a-file to d-file
                let rook = get_square(board, coords_to_index(row, 0));
                set_square(board, coords_to_index(row, 0), empty_square());
                set_square(board, coords_to_index(row, 3), rook);
            };
        };

        // Move the piece
        let mut_piece = from_square;

        // Handle pawn promotion
        if (from_square.piece_type == PIECE_PAWN) {
            let to_row = index_to_row(to);
            if ((from_square.color == COLOR_WHITE && to_row == 0) ||
                (from_square.color == COLOR_BLACK && to_row == 7)) {
                // Validate promotion piece
                assert!(promotion_piece >= PIECE_KNIGHT && promotion_piece <= PIECE_QUEEN, E_PROMOTION_REQUIRED);
                mut_piece.piece_type = promotion_piece;
            };
        };

        set_square(board, from, empty_square());
        set_square(board, to, mut_piece);

        captured
    }

    fun update_castling_rights(
        rights: &mut CastlingRights,
        from: u8,
        to: u8,
        piece_type: u8,
    ) {
        // King moves - lose all castling rights for that side
        if (piece_type == PIECE_KING) {
            if (index_to_row(from) == 7) {
                // White king
                rights.white_kingside = false;
                rights.white_queenside = false;
            } else if (index_to_row(from) == 0) {
                // Black king
                rights.black_kingside = false;
                rights.black_queenside = false;
            };
        };

        // Rook moves or captures - lose castling rights for that rook
        if (piece_type == PIECE_ROOK || from == 0 || from == 7 || from == 56 || from == 63 ||
            to == 0 || to == 7 || to == 56 || to == 63) {
            // a8 rook (black queenside)
            if (from == 0 || to == 0) {
                rights.black_queenside = false;
            };
            // h8 rook (black kingside)
            if (from == 7 || to == 7) {
                rights.black_kingside = false;
            };
            // a1 rook (white queenside)
            if (from == 56 || to == 56) {
                rights.white_queenside = false;
            };
            // h1 rook (white kingside)
            if (from == 63 || to == 63) {
                rights.white_kingside = false;
            };
        };
    }

    fun calculate_en_passant_target(
        from: u8,
        to: u8,
        piece_type: u8,
        is_white: bool,
    ): u8 {
        if (piece_type != PIECE_PAWN) {
            return 64 // No en passant
        };

        let from_row = index_to_row(from);
        let to_row = index_to_row(to);
        let col = index_to_col(from);

        // Check if pawn moved two squares
        if (is_white && from_row == 6 && to_row == 4) {
            return coords_to_index(5, col) // En passant target is the square the pawn passed through
        };
        if (!is_white && from_row == 1 && to_row == 3) {
            return coords_to_index(2, col)
        };

        64 // No en passant
    }

    // ============================================
    // GAME END DETECTION
    // ============================================

    fun has_legal_moves(
        board: &vector<Square>,
        color: u8,
        castling_rights: &CastlingRights,
        en_passant_target: u8,
    ): bool {
        // Check if the player has any legal moves
        let i: u8 = 0;
        while (i < 64) {
            let piece = get_square(board, i);
            if (piece.color == color) {
                // Try all possible destination squares
                let j: u8 = 0;
                while (j < 64) {
                    if (i != j) {
                        // Skip if destination has friendly piece
                        let dest_square = get_square(board, j);
                        if (!is_empty(&dest_square) && dest_square.color == color) {
                            j = j + 1;
                            continue
                        };
                        let is_valid = validate_piece_move(board, i, j, piece.piece_type, color == COLOR_WHITE, castling_rights, en_passant_target);
                        if (is_valid) {
                            // Check if move leaves king in check
                            let mut_board = *board;
                            let _ = execute_move(&mut mut_board, i, j, PIECE_QUEEN, en_passant_target);
                            if (!is_king_in_check(&mut_board, color)) {
                                return true
                            };
                        };
                    };
                    j = j + 1;
                };
            };
            i = i + 1;
        };
        false
    }

    fun validate_piece_move(
        board: &vector<Square>,
        from: u8,
        to: u8,
        piece_type: u8,
        is_white: bool,
        castling_rights: &CastlingRights,
        en_passant_target: u8,
    ): bool {
        if (piece_type == PIECE_PAWN) {
            is_valid_pawn_move(board, from, to, is_white, en_passant_target)
        } else if (piece_type == PIECE_KNIGHT) {
            is_valid_knight_move(from, to)
        } else if (piece_type == PIECE_BISHOP) {
            is_valid_bishop_move(board, from, to)
        } else if (piece_type == PIECE_ROOK) {
            is_valid_rook_move(board, from, to)
        } else if (piece_type == PIECE_QUEEN) {
            is_valid_queen_move(board, from, to)
        } else if (piece_type == PIECE_KING) {
            is_valid_king_move(board, from, to, castling_rights, is_white)
        } else {
            false
        }
    }

    // ============================================
    // ENTRY FUNCTIONS
    // ============================================

    public entry fun make_move(
        player: &signer,
        game_id: u64,
        from_square: u8,
        to_square: u8,
        promotion_piece: u8,
    ) acquires GameRegistry {
        // Validate square indices
        assert!(from_square < 64, E_INVALID_SQUARE);
        assert!(to_square < 64, E_INVALID_SQUARE);

        let player_addr = signer::address_of(player);
        let registry = borrow_global_mut<GameRegistry>(@chess);

        assert!(big_ordered_map::contains(&registry.games, &game_id), E_GAME_NOT_FOUND);
        // Remove game, modify, then add back (required for variable-sized values in BigOrderedMap)
        let game = big_ordered_map::remove(&mut registry.games, &game_id);

        // Verify game is active
        assert!(game.status == STATUS_ACTIVE, E_GAME_NOT_ACTIVE);

        // Verify it's this player's turn
        let is_white_turn = game.active_color == COLOR_WHITE;
        let is_player_white = player_addr == game.white_player;
        let is_player_black = player_addr == game.black_player;

        assert!(is_player_white || is_player_black, E_NOT_A_PLAYER);
        assert!(
            (is_white_turn && is_player_white) || (!is_white_turn && is_player_black),
            E_NOT_YOUR_TURN
        );

        // Update time control
        let now_ms = timestamp::now_microseconds() / 1000;
        let elapsed = now_ms - game.time_control.last_move_timestamp_ms;

        if (is_white_turn) {
            if (elapsed > game.time_control.white_time_remaining_ms) {
                game.status = STATUS_BLACK_WIN_TIMEOUT;
                event::emit(GameEndedEvent {
                    game_id: game.game_id,
                    status: STATUS_BLACK_WIN_TIMEOUT,
                    winner: game.black_player,
                });
                chess_leaderboard::update_ratings_internal(game.white_player, game.black_player, 2);
                big_ordered_map::add(&mut registry.games, game_id, game);
                return
            };
            game.time_control.white_time_remaining_ms = game.time_control.white_time_remaining_ms - elapsed + game.time_control.increment_ms;
        } else {
            if (elapsed > game.time_control.black_time_remaining_ms) {
                game.status = STATUS_WHITE_WIN_TIMEOUT;
                event::emit(GameEndedEvent {
                    game_id: game.game_id,
                    status: STATUS_WHITE_WIN_TIMEOUT,
                    winner: game.white_player,
                });
                chess_leaderboard::update_ratings_internal(game.white_player, game.black_player, 1);
                big_ordered_map::add(&mut registry.games, game_id, game);
                return
            };
            game.time_control.black_time_remaining_ms = game.time_control.black_time_remaining_ms - elapsed + game.time_control.increment_ms;
        };
        game.time_control.last_move_timestamp_ms = now_ms;

        // Validate move
        let from_sq = get_square(&game.board, from_square);
        assert!(!is_empty(&from_sq), E_NO_PIECE_AT_SQUARE);
        assert!(from_sq.color == game.active_color, E_WRONG_COLOR_PIECE);

        let to_sq = get_square(&game.board, to_square);
        if (!is_empty(&to_sq)) {
            assert!(to_sq.color != game.active_color, E_CANNOT_CAPTURE_OWN);
        };

        // Check if promotion is required
        if (from_sq.piece_type == PIECE_PAWN) {
            let to_row = index_to_row(to_square);
            if ((from_sq.color == COLOR_WHITE && to_row == 0) ||
                (from_sq.color == COLOR_BLACK && to_row == 7)) {
                assert!(promotion_piece >= PIECE_KNIGHT && promotion_piece <= PIECE_QUEEN, E_PROMOTION_REQUIRED);
            };
        };

        // Validate move based on piece type
        let is_valid = validate_piece_move(
            &game.board,
            from_square,
            to_square,
            from_sq.piece_type,
            is_white_turn,
            &game.castling_rights,
            game.en_passant_target
        );
        assert!(is_valid, E_INVALID_MOVE);

        // Execute move on a copy to check for check
        let en_passant = game.en_passant_target;
        let test_board = game.board;
        let _ = execute_move(&mut test_board, from_square, to_square, promotion_piece, en_passant);
        assert!(!is_king_in_check(&test_board, game.active_color), E_KING_IN_CHECK_AFTER_MOVE);

        // Execute the actual move
        let captured = execute_move(&mut game.board, from_square, to_square, promotion_piece, en_passant);
        let is_capture = !is_empty(&captured);

        // Update castling rights
        update_castling_rights(&mut game.castling_rights, from_square, to_square, from_sq.piece_type);

        // Update en passant target
        game.en_passant_target = calculate_en_passant_target(from_square, to_square, from_sq.piece_type, is_white_turn);

        // Update halfmove clock (reset on pawn move or capture)
        if (from_sq.piece_type == PIECE_PAWN || is_capture) {
            game.halfmove_clock = 0;
            // Clear position history on irreversible move
            game.position_history = vector::empty();
        } else {
            game.halfmove_clock = game.halfmove_clock + 1;
        };

        // Record move
        let move_record = MoveRecord {
            from_square,
            to_square,
            piece_type: from_sq.piece_type,
            captured_piece: captured.piece_type,
            promotion_piece,
            is_castling: from_sq.piece_type == PIECE_KING && abs_diff(index_to_col(from_square), index_to_col(to_square)) == 2,
            is_en_passant: from_sq.piece_type == PIECE_PAWN && is_capture && is_empty(&to_sq),
        };
        vector::push_back(&mut game.move_history, move_record);

        // Switch turns
        let opponent_color = if (is_white_turn) { COLOR_BLACK } else { COLOR_WHITE };
        game.active_color = opponent_color;
        if (!is_white_turn) {
            game.fullmove_number = game.fullmove_number + 1;
        };

        // Clear draw offer
        game.draw_offer_by = COLOR_NONE;

        // Add current position to history and check for repetition
        let current_hash = hash_position(&game.board, game.active_color, &game.castling_rights, game.en_passant_target);
        if (is_threefold_repetition(&game.position_history, current_hash)) {
            game.status = STATUS_DRAW_REPETITION;
            event::emit(GameEndedEvent {
                game_id: game.game_id,
                status: STATUS_DRAW_REPETITION,
                winner: @0x0,
            });
            chess_leaderboard::update_ratings_internal(game.white_player, game.black_player, 3);
            big_ordered_map::add(&mut registry.games, game_id, game);
            return
        };
        vector::push_back(&mut game.position_history, current_hash);

        // Check for insufficient material
        if (is_insufficient_material(&game.board)) {
            game.status = STATUS_DRAW_INSUFFICIENT;
            event::emit(GameEndedEvent {
                game_id: game.game_id,
                status: STATUS_DRAW_INSUFFICIENT,
                winner: @0x0,
            });
            chess_leaderboard::update_ratings_internal(game.white_player, game.black_player, 3);
            big_ordered_map::add(&mut registry.games, game_id, game);
            return
        };

        // Check for game end conditions
        let is_check = is_king_in_check(&game.board, opponent_color);
        let has_moves = has_legal_moves(&game.board, opponent_color, &game.castling_rights, game.en_passant_target);

        if (!has_moves) {
            if (is_check) {
                // Checkmate
                if (opponent_color == COLOR_WHITE) {
                    game.status = STATUS_BLACK_WIN_CHECKMATE;
                    event::emit(GameEndedEvent {
                        game_id: game.game_id,
                        status: STATUS_BLACK_WIN_CHECKMATE,
                        winner: game.black_player,
                    });
                    chess_leaderboard::update_ratings_internal(game.white_player, game.black_player, 2);
                } else {
                    game.status = STATUS_WHITE_WIN_CHECKMATE;
                    event::emit(GameEndedEvent {
                        game_id: game.game_id,
                        status: STATUS_WHITE_WIN_CHECKMATE,
                        winner: game.white_player,
                    });
                    chess_leaderboard::update_ratings_internal(game.white_player, game.black_player, 1);
                };
            } else {
                // Stalemate
                game.status = STATUS_DRAW_STALEMATE;
                event::emit(GameEndedEvent {
                    game_id: game.game_id,
                    status: STATUS_DRAW_STALEMATE,
                    winner: @0x0,
                });
                chess_leaderboard::update_ratings_internal(game.white_player, game.black_player, 3);
            };
        } else if (game.halfmove_clock >= 100) {
            // 50-move rule
            game.status = STATUS_DRAW_50_MOVE;
            event::emit(GameEndedEvent {
                game_id: game.game_id,
                status: STATUS_DRAW_50_MOVE,
                winner: @0x0,
            });
            chess_leaderboard::update_ratings_internal(game.white_player, game.black_player, 3);
        };

        // Emit move event
        event::emit(MoveMadeEvent {
            game_id: game.game_id,
            player: player_addr,
            from_square,
            to_square,
            piece_type: from_sq.piece_type,
            is_capture,
            is_check,
            promotion_piece,
        });

        // Add game back to map
        big_ordered_map::add(&mut registry.games, game_id, game);
    }

    public entry fun resign(
        player: &signer,
        game_id: u64,
    ) acquires GameRegistry {
        let player_addr = signer::address_of(player);
        let registry = borrow_global_mut<GameRegistry>(@chess);

        assert!(big_ordered_map::contains(&registry.games, &game_id), E_GAME_NOT_FOUND);
        let game = big_ordered_map::remove(&mut registry.games, &game_id);

        assert!(game.status == STATUS_ACTIVE, E_GAME_NOT_ACTIVE);

        if (player_addr == game.white_player) {
            game.status = STATUS_BLACK_WIN_RESIGNATION;
            event::emit(GameEndedEvent {
                game_id: game.game_id,
                status: STATUS_BLACK_WIN_RESIGNATION,
                winner: game.black_player,
            });
            chess_leaderboard::update_ratings_internal(game.white_player, game.black_player, 2);
        } else if (player_addr == game.black_player) {
            game.status = STATUS_WHITE_WIN_RESIGNATION;
            event::emit(GameEndedEvent {
                game_id: game.game_id,
                status: STATUS_WHITE_WIN_RESIGNATION,
                winner: game.white_player,
            });
            chess_leaderboard::update_ratings_internal(game.white_player, game.black_player, 1);
        } else {
            big_ordered_map::add(&mut registry.games, game_id, game);
            abort E_NOT_A_PLAYER
        };

        big_ordered_map::add(&mut registry.games, game_id, game);
    }

    public entry fun claim_timeout(
        claimer: &signer,
        game_id: u64,
    ) acquires GameRegistry {
        let claimer_addr = signer::address_of(claimer);
        let registry = borrow_global_mut<GameRegistry>(@chess);

        assert!(big_ordered_map::contains(&registry.games, &game_id), E_GAME_NOT_FOUND);
        let game = big_ordered_map::remove(&mut registry.games, &game_id);

        assert!(game.status == STATUS_ACTIVE, E_GAME_NOT_ACTIVE);
        assert!(claimer_addr == game.white_player || claimer_addr == game.black_player, E_NOT_A_PLAYER);

        let now_ms = timestamp::now_microseconds() / 1000;
        let elapsed = now_ms - game.time_control.last_move_timestamp_ms;

        if (game.active_color == COLOR_WHITE) {
            let remaining = if (elapsed > game.time_control.white_time_remaining_ms) {
                0
            } else {
                game.time_control.white_time_remaining_ms - elapsed
            };
            assert!(remaining == 0, E_TIMEOUT_NOT_REACHED);
            game.status = STATUS_BLACK_WIN_TIMEOUT;
            event::emit(GameEndedEvent {
                game_id: game.game_id,
                status: STATUS_BLACK_WIN_TIMEOUT,
                winner: game.black_player,
            });
            chess_leaderboard::update_ratings_internal(game.white_player, game.black_player, 2);
        } else {
            let remaining = if (elapsed > game.time_control.black_time_remaining_ms) {
                0
            } else {
                game.time_control.black_time_remaining_ms - elapsed
            };
            assert!(remaining == 0, E_TIMEOUT_NOT_REACHED);
            game.status = STATUS_WHITE_WIN_TIMEOUT;
            event::emit(GameEndedEvent {
                game_id: game.game_id,
                status: STATUS_WHITE_WIN_TIMEOUT,
                winner: game.white_player,
            });
            chess_leaderboard::update_ratings_internal(game.white_player, game.black_player, 1);
        };

        big_ordered_map::add(&mut registry.games, game_id, game);
    }

    public entry fun offer_draw(
        player: &signer,
        game_id: u64,
    ) acquires GameRegistry {
        let player_addr = signer::address_of(player);
        let registry = borrow_global_mut<GameRegistry>(@chess);

        assert!(big_ordered_map::contains(&registry.games, &game_id), E_GAME_NOT_FOUND);
        let game = big_ordered_map::remove(&mut registry.games, &game_id);

        assert!(game.status == STATUS_ACTIVE, E_GAME_NOT_ACTIVE);

        if (player_addr == game.white_player) {
            game.draw_offer_by = COLOR_WHITE;
            event::emit(DrawOfferedEvent {
                game_id: game.game_id,
                offered_by: player_addr,
                color: COLOR_WHITE,
            });
        } else if (player_addr == game.black_player) {
            game.draw_offer_by = COLOR_BLACK;
            event::emit(DrawOfferedEvent {
                game_id: game.game_id,
                offered_by: player_addr,
                color: COLOR_BLACK,
            });
        } else {
            big_ordered_map::add(&mut registry.games, game_id, game);
            abort E_NOT_A_PLAYER
        };

        big_ordered_map::add(&mut registry.games, game_id, game);
    }

    public entry fun cancel_draw_offer(
        player: &signer,
        game_id: u64,
    ) acquires GameRegistry {
        let player_addr = signer::address_of(player);
        let registry = borrow_global_mut<GameRegistry>(@chess);

        assert!(big_ordered_map::contains(&registry.games, &game_id), E_GAME_NOT_FOUND);
        let game = big_ordered_map::remove(&mut registry.games, &game_id);

        assert!(game.status == STATUS_ACTIVE, E_GAME_NOT_ACTIVE);

        // Can only cancel own draw offer
        if (player_addr == game.white_player) {
            assert!(game.draw_offer_by == COLOR_WHITE, E_NO_DRAW_OFFER_TO_CANCEL);
        } else if (player_addr == game.black_player) {
            assert!(game.draw_offer_by == COLOR_BLACK, E_NO_DRAW_OFFER_TO_CANCEL);
        } else {
            big_ordered_map::add(&mut registry.games, game_id, game);
            abort E_NOT_A_PLAYER
        };

        game.draw_offer_by = COLOR_NONE;
        event::emit(DrawOfferCancelledEvent {
            game_id: game.game_id,
            cancelled_by: player_addr,
        });

        big_ordered_map::add(&mut registry.games, game_id, game);
    }

    public entry fun accept_draw(
        player: &signer,
        game_id: u64,
    ) acquires GameRegistry {
        let player_addr = signer::address_of(player);
        let registry = borrow_global_mut<GameRegistry>(@chess);

        assert!(big_ordered_map::contains(&registry.games, &game_id), E_GAME_NOT_FOUND);
        let game = big_ordered_map::remove(&mut registry.games, &game_id);

        assert!(game.status == STATUS_ACTIVE, E_GAME_NOT_ACTIVE);

        // Can only accept opponent's draw offer
        if (player_addr == game.white_player) {
            assert!(game.draw_offer_by == COLOR_BLACK, E_NO_DRAW_OFFER);
        } else if (player_addr == game.black_player) {
            assert!(game.draw_offer_by == COLOR_WHITE, E_NO_DRAW_OFFER);
        } else {
            big_ordered_map::add(&mut registry.games, game_id, game);
            abort E_NOT_A_PLAYER
        };

        game.status = STATUS_DRAW_AGREEMENT;
        event::emit(GameEndedEvent {
            game_id: game.game_id,
            status: STATUS_DRAW_AGREEMENT,
            winner: @0x0,
        });
        chess_leaderboard::update_ratings_internal(game.white_player, game.black_player, 3);

        big_ordered_map::add(&mut registry.games, game_id, game);
    }

    // ============================================
    // VIEW FUNCTIONS
    // ============================================

    #[view]
    public fun get_game_state(game_id: u64): (
        u64,            // game_id
        address,        // white_player
        address,        // black_player
        u8,             // active_color
        u8,             // status
        u64,            // white_time_remaining_ms
        u64,            // black_time_remaining_ms
        u64,            // last_move_timestamp_ms
        u8,             // en_passant_target
        u64,            // halfmove_clock
        u64,            // fullmove_number
        u8,             // draw_offer_by
    ) acquires GameRegistry {
        let registry = borrow_global<GameRegistry>(@chess);
        assert!(big_ordered_map::contains(&registry.games, &game_id), E_GAME_NOT_FOUND);
        let game = big_ordered_map::borrow(&registry.games, &game_id);
        (
            game.game_id,
            game.white_player,
            game.black_player,
            game.active_color,
            game.status,
            game.time_control.white_time_remaining_ms,
            game.time_control.black_time_remaining_ms,
            game.time_control.last_move_timestamp_ms,
            game.en_passant_target,
            game.halfmove_clock,
            game.fullmove_number,
            game.draw_offer_by,
        )
    }

    #[view]
    /// Get current time remaining (accounting for elapsed time since last move)
    public fun get_current_time_remaining(game_id: u64): (u64, u64) acquires GameRegistry {
        let registry = borrow_global<GameRegistry>(@chess);
        assert!(big_ordered_map::contains(&registry.games, &game_id), E_GAME_NOT_FOUND);
        let game = big_ordered_map::borrow(&registry.games, &game_id);

        if (game.status != STATUS_ACTIVE) {
            return (game.time_control.white_time_remaining_ms, game.time_control.black_time_remaining_ms)
        };

        let now_ms = timestamp::now_microseconds() / 1000;
        let elapsed = now_ms - game.time_control.last_move_timestamp_ms;

        if (game.active_color == COLOR_WHITE) {
            let white_remaining = if (elapsed > game.time_control.white_time_remaining_ms) {
                0
            } else {
                game.time_control.white_time_remaining_ms - elapsed
            };
            (white_remaining, game.time_control.black_time_remaining_ms)
        } else {
            let black_remaining = if (elapsed > game.time_control.black_time_remaining_ms) {
                0
            } else {
                game.time_control.black_time_remaining_ms - elapsed
            };
            (game.time_control.white_time_remaining_ms, black_remaining)
        }
    }

    #[view]
    public fun get_board(game_id: u64): vector<Square> acquires GameRegistry {
        let registry = borrow_global<GameRegistry>(@chess);
        assert!(big_ordered_map::contains(&registry.games, &game_id), E_GAME_NOT_FOUND);
        let game = big_ordered_map::borrow(&registry.games, &game_id);
        game.board
    }

    #[view]
    public fun get_move_history(game_id: u64): vector<MoveRecord> acquires GameRegistry {
        let registry = borrow_global<GameRegistry>(@chess);
        assert!(big_ordered_map::contains(&registry.games, &game_id), E_GAME_NOT_FOUND);
        let game = big_ordered_map::borrow(&registry.games, &game_id);
        game.move_history
    }

    #[view]
    public fun is_check(game_id: u64): bool acquires GameRegistry {
        let registry = borrow_global<GameRegistry>(@chess);
        assert!(big_ordered_map::contains(&registry.games, &game_id), E_GAME_NOT_FOUND);
        let game = big_ordered_map::borrow(&registry.games, &game_id);
        is_king_in_check(&game.board, game.active_color)
    }

    #[view]
    public fun get_legal_moves_for_square(game_id: u64, square: u8): vector<u8> acquires GameRegistry {
        assert!(square < 64, E_INVALID_SQUARE);
        let registry = borrow_global<GameRegistry>(@chess);
        assert!(big_ordered_map::contains(&registry.games, &game_id), E_GAME_NOT_FOUND);
        let game = big_ordered_map::borrow(&registry.games, &game_id);

        let piece = get_square(&game.board, square);
        let legal_moves = vector::empty<u8>();

        if (is_empty(&piece) || piece.color != game.active_color) {
            return legal_moves
        };

        let j: u8 = 0;
        while (j < 64) {
            if (square != j) {
                // Check destination doesn't have friendly piece
                let dest_square = get_square(&game.board, j);
                if (!is_empty(&dest_square) && dest_square.color == piece.color) {
                    j = j + 1;
                    continue
                };

                let is_valid = validate_piece_move(
                    &game.board,
                    square,
                    j,
                    piece.piece_type,
                    game.active_color == COLOR_WHITE,
                    &game.castling_rights,
                    game.en_passant_target
                );
                if (is_valid) {
                    // Check if move leaves king in check
                    let test_board = game.board;
                    let _ = execute_move(&mut test_board, square, j, PIECE_QUEEN, game.en_passant_target);
                    if (!is_king_in_check(&test_board, game.active_color)) {
                        vector::push_back(&mut legal_moves, j);
                    };
                };
            };
            j = j + 1;
        };

        legal_moves
    }

    #[view]
    public fun game_exists(game_id: u64): bool acquires GameRegistry {
        let registry = borrow_global<GameRegistry>(@chess);
        big_ordered_map::contains(&registry.games, &game_id)
    }

    #[view]
    public fun get_next_game_id(): u64 acquires GameRegistry {
        let registry = borrow_global<GameRegistry>(@chess);
        registry.next_game_id
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
    }

    #[test_only]
    /// Test wrapper to check has_legal_moves with game state
    public fun test_has_legal_moves(game_id: u64, color: u8): bool acquires GameRegistry {
        let registry = borrow_global<GameRegistry>(@chess);
        let game = big_ordered_map::borrow(&registry.games, &game_id);
        has_legal_moves(&game.board, color, &game.castling_rights, game.en_passant_target)
    }

    #[test_only]
    /// Debug version - returns (from, to) of first "legal" move found, or (255, 255) if none
    public fun test_find_first_legal_move(game_id: u64, color: u8): (u8, u8) acquires GameRegistry {
        let registry = borrow_global<GameRegistry>(@chess);
        let game = big_ordered_map::borrow(&registry.games, &game_id);

        let i: u8 = 0;
        while (i < 64) {
            let piece = get_square(&game.board, i);
            if (piece.color == color) {
                let j: u8 = 0;
                while (j < 64) {
                    if (i != j) {
                        // Skip if destination has friendly piece
                        let dest_square = get_square(&game.board, j);
                        if (!is_empty(&dest_square) && dest_square.color == color) {
                            j = j + 1;
                            continue
                        };
                        let is_valid = validate_piece_move(&game.board, i, j, piece.piece_type, color == COLOR_WHITE, &game.castling_rights, game.en_passant_target);
                        if (is_valid) {
                            let mut_board = game.board;
                            let _ = execute_move(&mut mut_board, i, j, PIECE_QUEEN, game.en_passant_target);
                            if (!is_king_in_check(&mut_board, color)) {
                                return (i, j)
                            };
                        };
                    };
                    j = j + 1;
                };
            };
            i = i + 1;
        };
        (255, 255)
    }

    #[test(deployer = @chess)]
    fun test_create_game(deployer: &signer) acquires GameRegistry {
        setup_test(deployer);

        let white = @0x123;
        let black = @0x456;

        // Register players first
        let white_signer = &account::create_signer_for_test(white);
        let black_signer = &account::create_signer_for_test(black);
        chess_leaderboard::register_player(white_signer);
        chess_leaderboard::register_player(black_signer);

        let game_id = create_game_internal(white, black, 300, 5);

        assert!(game_exists(game_id), 1);
        assert!(game_id == 1, 2);

        let (id, white_player, black_player, active_color, status, _, _, _, _, _, _, _) = get_game_state(game_id);
        assert!(id == 1, 3);
        assert!(white_player == white, 4);
        assert!(black_player == black, 5);
        assert!(active_color == COLOR_WHITE, 6);
        assert!(status == STATUS_ACTIVE, 7);
    }

    #[test(deployer = @chess)]
    #[expected_failure(abort_code = E_SAME_PLAYER)]
    fun test_create_game_same_player_fails(deployer: &signer) acquires GameRegistry {
        setup_test(deployer);

        let player = @0x123;
        let player_signer = &account::create_signer_for_test(player);
        chess_leaderboard::register_player(player_signer);

        // Should fail - same player for both colors
        let _ = create_game_internal(player, player, 300, 5);
    }

    #[test(deployer = @chess)]
    #[expected_failure(abort_code = E_INVALID_TIME_CONTROL)]
    fun test_create_game_time_too_short_fails(deployer: &signer) acquires GameRegistry {
        setup_test(deployer);

        let white_signer = &account::create_signer_for_test(@0x123);
        let black_signer = &account::create_signer_for_test(@0x456);
        chess_leaderboard::register_player(white_signer);
        chess_leaderboard::register_player(black_signer);

        // Should fail - 10 seconds is below minimum of 30
        let _ = create_game_internal(@0x123, @0x456, 10, 0);
    }

    #[test(deployer = @chess)]
    #[expected_failure(abort_code = E_INVALID_TIME_CONTROL)]
    fun test_create_game_time_too_long_fails(deployer: &signer) acquires GameRegistry {
        setup_test(deployer);

        let white_signer = &account::create_signer_for_test(@0x123);
        let black_signer = &account::create_signer_for_test(@0x456);
        chess_leaderboard::register_player(white_signer);
        chess_leaderboard::register_player(black_signer);

        // Should fail - 4 hours exceeds 3 hour maximum
        let _ = create_game_internal(@0x123, @0x456, 14400, 0);
    }

    #[test(deployer = @chess)]
    fun test_make_move_e2_e4(deployer: &signer) acquires GameRegistry {
        setup_test(deployer);

        let white = @0x123;
        let black = @0x456;
        let white_signer = &account::create_signer_for_test(white);
        let black_signer = &account::create_signer_for_test(black);
        chess_leaderboard::register_player(white_signer);
        chess_leaderboard::register_player(black_signer);

        let game_id = create_game_internal(white, black, 300, 5);

        // e2 = index 52, e4 = index 36
        make_move(white_signer, game_id, 52, 36, 0);

        let (_, _, _, active_color, _, _, _, _, en_passant, _, fullmove, _) = get_game_state(game_id);
        assert!(active_color == COLOR_BLACK, 1);
        assert!(en_passant == 44, 2); // e3 is en passant target
        assert!(fullmove == 1, 3);
    }

    #[test(deployer = @chess)]
    #[expected_failure(abort_code = E_NOT_YOUR_TURN)]
    fun test_make_move_wrong_turn_fails(deployer: &signer) acquires GameRegistry {
        setup_test(deployer);

        let white = @0x123;
        let black = @0x456;
        let white_signer = &account::create_signer_for_test(white);
        let black_signer = &account::create_signer_for_test(black);
        chess_leaderboard::register_player(white_signer);
        chess_leaderboard::register_player(black_signer);

        let game_id = create_game_internal(white, black, 300, 5);

        // Black tries to move first - should fail
        make_move(black_signer, game_id, 12, 28, 0); // e7-e5
    }

    #[test(deployer = @chess)]
    #[expected_failure(abort_code = E_INVALID_MOVE)]
    fun test_invalid_pawn_move_fails(deployer: &signer) acquires GameRegistry {
        setup_test(deployer);

        let white = @0x123;
        let black = @0x456;
        let white_signer = &account::create_signer_for_test(white);
        let black_signer = &account::create_signer_for_test(black);
        chess_leaderboard::register_player(white_signer);
        chess_leaderboard::register_player(black_signer);

        let game_id = create_game_internal(white, black, 300, 5);

        // e2-e5 is not a valid pawn move (3 squares)
        make_move(white_signer, game_id, 52, 28, 0);
    }

    #[test(deployer = @chess)]
    fun test_knight_move(deployer: &signer) acquires GameRegistry {
        setup_test(deployer);

        let white = @0x123;
        let black = @0x456;
        let white_signer = &account::create_signer_for_test(white);
        let black_signer = &account::create_signer_for_test(black);
        chess_leaderboard::register_player(white_signer);
        chess_leaderboard::register_player(black_signer);

        let game_id = create_game_internal(white, black, 300, 5);

        // Nf3 (g1 = 62, f3 = 45)
        make_move(white_signer, game_id, 62, 45, 0);

        let board = get_board(game_id);
        let f3 = vector::borrow(&board, 45);
        assert!(f3.piece_type == PIECE_KNIGHT, 1);
        assert!(f3.color == COLOR_WHITE, 2);
    }

    #[test(deployer = @chess)]
    fun test_resign(deployer: &signer) acquires GameRegistry {
        setup_test(deployer);

        let white = @0x123;
        let black = @0x456;
        let white_signer = &account::create_signer_for_test(white);
        let black_signer = &account::create_signer_for_test(black);
        chess_leaderboard::register_player(white_signer);
        chess_leaderboard::register_player(black_signer);

        let game_id = create_game_internal(white, black, 300, 5);

        resign(white_signer, game_id);

        let (_, _, _, _, status, _, _, _, _, _, _, _) = get_game_state(game_id);
        assert!(status == STATUS_BLACK_WIN_RESIGNATION, 1);
    }

    #[test(deployer = @chess)]
    fun test_draw_offer_and_accept(deployer: &signer) acquires GameRegistry {
        setup_test(deployer);

        let white = @0x123;
        let black = @0x456;
        let white_signer = &account::create_signer_for_test(white);
        let black_signer = &account::create_signer_for_test(black);
        chess_leaderboard::register_player(white_signer);
        chess_leaderboard::register_player(black_signer);

        let game_id = create_game_internal(white, black, 300, 5);

        // White offers draw
        offer_draw(white_signer, game_id);

        let (_, _, _, _, _, _, _, _, _, _, _, draw_offer_by) = get_game_state(game_id);
        assert!(draw_offer_by == COLOR_WHITE, 1);

        // Black accepts
        accept_draw(black_signer, game_id);

        let (_, _, _, _, status, _, _, _, _, _, _, _) = get_game_state(game_id);
        assert!(status == STATUS_DRAW_AGREEMENT, 2);
    }

    #[test(deployer = @chess)]
    #[expected_failure(abort_code = E_NO_DRAW_OFFER)]
    fun test_accept_draw_without_offer_fails(deployer: &signer) acquires GameRegistry {
        setup_test(deployer);

        let white = @0x123;
        let black = @0x456;
        let white_signer = &account::create_signer_for_test(white);
        let black_signer = &account::create_signer_for_test(black);
        chess_leaderboard::register_player(white_signer);
        chess_leaderboard::register_player(black_signer);

        let game_id = create_game_internal(white, black, 300, 5);

        // Try to accept draw without offer - should fail
        accept_draw(black_signer, game_id);
    }

    #[test(deployer = @chess)]
    fun test_cancel_draw_offer(deployer: &signer) acquires GameRegistry {
        setup_test(deployer);

        let white = @0x123;
        let black = @0x456;
        let white_signer = &account::create_signer_for_test(white);
        let black_signer = &account::create_signer_for_test(black);
        chess_leaderboard::register_player(white_signer);
        chess_leaderboard::register_player(black_signer);

        let game_id = create_game_internal(white, black, 300, 5);

        // White offers draw
        offer_draw(white_signer, game_id);

        let (_, _, _, _, _, _, _, _, _, _, _, draw_offer_by) = get_game_state(game_id);
        assert!(draw_offer_by == COLOR_WHITE, 1);

        // White cancels offer
        cancel_draw_offer(white_signer, game_id);

        let (_, _, _, _, _, _, _, _, _, _, _, draw_offer_by) = get_game_state(game_id);
        assert!(draw_offer_by == COLOR_NONE, 2);
    }

    #[test(deployer = @chess)]
    fun test_legal_moves_initial_position(deployer: &signer) acquires GameRegistry {
        setup_test(deployer);

        let white = @0x123;
        let black = @0x456;
        let white_signer = &account::create_signer_for_test(white);
        let black_signer = &account::create_signer_for_test(black);
        chess_leaderboard::register_player(white_signer);
        chess_leaderboard::register_player(black_signer);

        let game_id = create_game_internal(white, black, 300, 5);

        // e2 pawn should have 2 legal moves (e3, e4)
        let moves = get_legal_moves_for_square(game_id, 52);
        assert!(vector::length(&moves) == 2, 1);

        // b1 knight should have exactly 2 legal moves (a3, c3)
        let knight_moves = get_legal_moves_for_square(game_id, 57);
        assert!(vector::length(&knight_moves) == 2, 2);
    }

    #[test(deployer = @chess)]
    fun test_debug_knight_legal_moves(deployer: &signer) acquires GameRegistry {
        setup_test(deployer);

        let white = @0x123;
        let black = @0x456;
        let white_signer = &account::create_signer_for_test(white);
        let black_signer = &account::create_signer_for_test(black);
        chess_leaderboard::register_player(white_signer);
        chess_leaderboard::register_player(black_signer);

        let game_id = create_game_internal(white, black, 300, 5);

        // Verify board setup - check knight at b1 (index 57)
        let board = get_board(game_id);
        let b1_piece = vector::borrow(&board, 57);
        assert!(b1_piece.piece_type == PIECE_KNIGHT, 100);
        assert!(b1_piece.color == COLOR_WHITE, 101);

        // Check knight at g1 (index 62)
        let g1_piece = vector::borrow(&board, 62);
        assert!(g1_piece.piece_type == PIECE_KNIGHT, 102);
        assert!(g1_piece.color == COLOR_WHITE, 103);

        // b1 knight (57) should move to a3 (40) and c3 (42)
        // From (7,1) -> (5,0)=40 and (5,2)=42
        let b1_moves = get_legal_moves_for_square(game_id, 57);
        let b1_count = vector::length(&b1_moves);

        // g1 knight (62) should move to f3 (45) and h3 (47)
        // From (7,6) -> (5,5)=45 and (5,7)=47
        let g1_moves = get_legal_moves_for_square(game_id, 62);
        let g1_count = vector::length(&g1_moves);

        // Debug: Check what we got
        // Expected: b1_count = 2, g1_count = 2
        // If this fails, we know which knight has the issue
        assert!(b1_count == 2, 200 + b1_count);
        assert!(g1_count == 2, 300 + g1_count);
    }

    #[test(deployer = @chess)]
    fun test_is_check(deployer: &signer) acquires GameRegistry {
        setup_test(deployer);

        let white = @0x123;
        let black = @0x456;
        let white_signer = &account::create_signer_for_test(white);
        let black_signer = &account::create_signer_for_test(black);
        chess_leaderboard::register_player(white_signer);
        chess_leaderboard::register_player(black_signer);

        let game_id = create_game_internal(white, black, 300, 5);

        // Initial position - no check
        assert!(!is_check(game_id), 1);
    }

    #[test(deployer = @chess)]
    #[expected_failure(abort_code = E_NOT_A_PLAYER)]
    fun test_move_by_non_player_fails(deployer: &signer) acquires GameRegistry {
        setup_test(deployer);

        let white = @0x123;
        let black = @0x456;
        let other = @0x789;
        let white_signer = &account::create_signer_for_test(white);
        let black_signer = &account::create_signer_for_test(black);
        let other_signer = &account::create_signer_for_test(other);
        chess_leaderboard::register_player(white_signer);
        chess_leaderboard::register_player(black_signer);
        chess_leaderboard::register_player(other_signer);

        let game_id = create_game_internal(white, black, 300, 5);

        // Non-player tries to move - should fail
        make_move(other_signer, game_id, 52, 36, 0);
    }

    #[test(deployer = @chess)]
    #[expected_failure(abort_code = E_INVALID_SQUARE)]
    fun test_invalid_square_fails(deployer: &signer) acquires GameRegistry {
        setup_test(deployer);

        let white = @0x123;
        let black = @0x456;
        let white_signer = &account::create_signer_for_test(white);
        let black_signer = &account::create_signer_for_test(black);
        chess_leaderboard::register_player(white_signer);
        chess_leaderboard::register_player(black_signer);

        let game_id = create_game_internal(white, black, 300, 5);

        // Square 64 doesn't exist
        make_move(white_signer, game_id, 52, 64, 0);
    }

    #[test(deployer = @chess)]
    fun test_move_history(deployer: &signer) acquires GameRegistry {
        setup_test(deployer);

        let white = @0x123;
        let black = @0x456;
        let white_signer = &account::create_signer_for_test(white);
        let black_signer = &account::create_signer_for_test(black);
        chess_leaderboard::register_player(white_signer);
        chess_leaderboard::register_player(black_signer);

        let game_id = create_game_internal(white, black, 300, 5);

        // Make some moves
        make_move(white_signer, game_id, 52, 36, 0); // e4
        make_move(black_signer, game_id, 12, 28, 0); // e5

        let history = get_move_history(game_id);
        assert!(vector::length(&history) == 2, 1);

        let first_move = vector::borrow(&history, 0);
        assert!(first_move.from_square == 52, 2);
        assert!(first_move.to_square == 36, 3);
        assert!(first_move.piece_type == PIECE_PAWN, 4);
    }

    #[test(deployer = @chess)]
    #[expected_failure(abort_code = E_GAME_NOT_FOUND)]
    fun test_get_nonexistent_game_fails(deployer: &signer) acquires GameRegistry {
        setup_test(deployer);

        // Game 999 doesn't exist
        let (_, _, _, _, _, _, _, _, _, _, _, _) = get_game_state(999);
    }

    #[test(deployer = @chess)]
    fun test_multiple_games(deployer: &signer) acquires GameRegistry {
        setup_test(deployer);

        let p1 = @0x123;
        let p2 = @0x456;
        let p3 = @0x789;
        let p1_signer = &account::create_signer_for_test(p1);
        let p2_signer = &account::create_signer_for_test(p2);
        let p3_signer = &account::create_signer_for_test(p3);
        chess_leaderboard::register_player(p1_signer);
        chess_leaderboard::register_player(p2_signer);
        chess_leaderboard::register_player(p3_signer);

        let game1_id = create_game_internal(p1, p2, 300, 5);
        let game2_id = create_game_internal(p1, p3, 600, 10);

        assert!(game1_id == 1, 1);
        assert!(game2_id == 2, 2);
        assert!(game_exists(game1_id), 3);
        assert!(game_exists(game2_id), 4);
        assert!(get_next_game_id() == 3, 5);
    }

    #[test(deployer = @chess)]
    /// Test checkmate detection using fool's mate (fastest possible checkmate)
    /// 1. f3 e5  2. g4 Qh4#
    fun test_checkmate_fools_mate(deployer: &signer) acquires GameRegistry {
        setup_test(deployer);

        let white = @0x123;
        let black = @0x456;
        let white_signer = &account::create_signer_for_test(white);
        let black_signer = &account::create_signer_for_test(black);
        chess_leaderboard::register_player(white_signer);
        chess_leaderboard::register_player(black_signer);

        let game_id = create_game_internal(white, black, 300, 5);

        // 1. f3 (f2=53 -> f3=45)
        make_move(white_signer, game_id, 53, 45, 0);

        // 1... e5 (e7=12 -> e5=28)
        make_move(black_signer, game_id, 12, 28, 0);

        // 2. g4 (g2=54 -> g4=38)
        make_move(white_signer, game_id, 54, 38, 0);

        // 2... Qh4# (Qd8=3 -> h4=39) - CHECKMATE!
        make_move(black_signer, game_id, 3, 39, 0);

        // Verify checkmate
        let (_, _, _, _, status, _, _, _, _, _, _, _) = get_game_state(game_id);
        assert!(status == STATUS_BLACK_WIN_CHECKMATE, 100 + (status as u64));
    }
}
