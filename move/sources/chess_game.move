module chess::chess_game {
    use std::signer;
    use std::vector;
    use aptos_framework::timestamp;
    use aptos_framework::event;
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
    struct Game has key, store {
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
    }

    /// Global game registry
    struct GameRegistry has key {
        next_game_id: u64,
        active_game_ids: vector<u64>,
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

    // ============================================
    // INITIALIZATION
    // ============================================

    public entry fun initialize(admin: &signer) {
        let admin_addr = signer::address_of(admin);
        assert!(!exists<GameRegistry>(admin_addr), E_ALREADY_INITIALIZED);

        move_to(admin, GameRegistry {
            next_game_id: 1,
            active_game_ids: vector::empty(),
        });
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
        *vector::borrow(board, (index as u64))
    }

    fun set_square(board: &mut vector<Square>, index: u8, square: Square) {
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
    // GAME CREATION
    // ============================================

    public entry fun create_game(
        creator: &signer,
        white_player: address,
        black_player: address,
        time_base_seconds: u64,
        time_increment_seconds: u64,
    ) acquires GameRegistry {
        let _creator_addr = signer::address_of(creator);
        let registry = borrow_global_mut<GameRegistry>(@chess);

        let game_id = registry.next_game_id;
        registry.next_game_id = game_id + 1;

        let base_time_ms = time_base_seconds * 1000;
        let increment_ms = time_increment_seconds * 1000;
        let now_ms = timestamp::now_microseconds() / 1000;

        let game = Game {
            game_id,
            white_player,
            black_player,
            board: initial_board(),
            active_color: COLOR_WHITE,
            status: STATUS_ACTIVE,
            castling_rights: initial_castling_rights(),
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
        };

        vector::push_back(&mut registry.active_game_ids, game_id);

        // Store game - using a resource account pattern
        // For simplicity, we store under @chess
        // In production, use Object or Table for multiple games
        move_to(creator, game);

        event::emit(GameCreatedEvent {
            game_id,
            white_player,
            black_player,
            time_base_ms: base_time_ms,
            time_increment_ms: increment_ms,
        });
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
                // Promote pawn
                if (promotion_piece >= PIECE_KNIGHT && promotion_piece <= PIECE_QUEEN) {
                    mut_piece.piece_type = promotion_piece;
                } else {
                    // Default to queen if invalid promotion piece
                    mut_piece.piece_type = PIECE_QUEEN;
                };
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
        game_addr: address,
        from_square: u8,
        to_square: u8,
        promotion_piece: u8,
    ) acquires Game {
        let player_addr = signer::address_of(player);
        let game = borrow_global_mut<Game>(game_addr);

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
        let test_board = game.board;
        let _ = execute_move(&mut test_board, from_square, to_square, promotion_piece, game.en_passant_target);
        assert!(!is_king_in_check(&test_board, game.active_color), E_KING_IN_CHECK_AFTER_MOVE);

        // Execute the actual move
        let captured = execute_move(&mut game.board, from_square, to_square, promotion_piece, game.en_passant_target);
        let is_capture = !is_empty(&captured);

        // Update castling rights
        update_castling_rights(&mut game.castling_rights, from_square, to_square, from_sq.piece_type);

        // Update en passant target
        game.en_passant_target = calculate_en_passant_target(from_square, to_square, from_sq.piece_type, is_white_turn);

        // Update halfmove clock (reset on pawn move or capture)
        if (from_sq.piece_type == PIECE_PAWN || is_capture) {
            game.halfmove_clock = 0;
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
    }

    public entry fun resign(
        player: &signer,
        game_addr: address,
    ) acquires Game {
        let player_addr = signer::address_of(player);
        let game = borrow_global_mut<Game>(game_addr);

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
            abort E_NOT_A_PLAYER
        };
    }

    public entry fun claim_timeout(
        claimer: &signer,
        game_addr: address,
    ) acquires Game {
        let claimer_addr = signer::address_of(claimer);
        let game = borrow_global_mut<Game>(game_addr);

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
    }

    public entry fun offer_draw(
        player: &signer,
        game_addr: address,
    ) acquires Game {
        let player_addr = signer::address_of(player);
        let game = borrow_global_mut<Game>(game_addr);

        assert!(game.status == STATUS_ACTIVE, E_GAME_NOT_ACTIVE);

        if (player_addr == game.white_player) {
            game.draw_offer_by = COLOR_WHITE;
        } else if (player_addr == game.black_player) {
            game.draw_offer_by = COLOR_BLACK;
        } else {
            abort E_NOT_A_PLAYER
        };
    }

    public entry fun accept_draw(
        player: &signer,
        game_addr: address,
    ) acquires Game {
        let player_addr = signer::address_of(player);
        let game = borrow_global_mut<Game>(game_addr);

        assert!(game.status == STATUS_ACTIVE, E_GAME_NOT_ACTIVE);

        // Can only accept opponent's draw offer
        if (player_addr == game.white_player) {
            assert!(game.draw_offer_by == COLOR_BLACK, E_NO_DRAW_OFFER);
        } else if (player_addr == game.black_player) {
            assert!(game.draw_offer_by == COLOR_WHITE, E_NO_DRAW_OFFER);
        } else {
            abort E_NOT_A_PLAYER
        };

        game.status = STATUS_DRAW_AGREEMENT;
        event::emit(GameEndedEvent {
            game_id: game.game_id,
            status: STATUS_DRAW_AGREEMENT,
            winner: @0x0,
        });
        chess_leaderboard::update_ratings_internal(game.white_player, game.black_player, 3);
    }

    // ============================================
    // VIEW FUNCTIONS
    // ============================================

    #[view]
    public fun get_game_state(game_addr: address): (
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
    ) acquires Game {
        let game = borrow_global<Game>(game_addr);
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
    public fun get_board(game_addr: address): vector<Square> acquires Game {
        let game = borrow_global<Game>(game_addr);
        game.board
    }

    #[view]
    public fun get_move_history(game_addr: address): vector<MoveRecord> acquires Game {
        let game = borrow_global<Game>(game_addr);
        game.move_history
    }

    #[view]
    public fun is_check(game_addr: address): bool acquires Game {
        let game = borrow_global<Game>(game_addr);
        is_king_in_check(&game.board, game.active_color)
    }

    #[view]
    public fun get_legal_moves_for_square(game_addr: address, square: u8): vector<u8> acquires Game {
        let game = borrow_global<Game>(game_addr);
        let piece = get_square(&game.board, square);
        let legal_moves = vector::empty<u8>();

        if (is_empty(&piece) || piece.color != game.active_color) {
            return legal_moves
        };

        let j: u8 = 0;
        while (j < 64) {
            if (square != j) {
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
}
