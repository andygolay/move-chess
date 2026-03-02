// Contract addresses per network (from .env)
const CHESS_ADDRESSES: Record<string, string | undefined> = {
  testnet: process.env.NEXT_PUBLIC_CHESS_MODULE_ADDRESS_TESTNET,
  mainnet: process.env.NEXT_PUBLIC_CHESS_MODULE_ADDRESS_MAINNET,
};

// Get the contract address for the current network
// Usage: const address = getChessModuleAddress(sdk.network)
export function getChessModuleAddress(network?: string): string {
  const addr = CHESS_ADDRESSES[network || "testnet"];
  if (!addr) {
    throw new Error(`Chess module address not configured for network: ${network || "testnet"}`);
  }
  return addr;
}

// Piece types (matching Move contract)
export const PIECE_NONE = 0;
export const PIECE_PAWN = 1;
export const PIECE_KNIGHT = 2;
export const PIECE_BISHOP = 3;
export const PIECE_ROOK = 4;
export const PIECE_QUEEN = 5;
export const PIECE_KING = 6;

// Colors (matching Move contract)
export const COLOR_NONE = 0;
export const COLOR_WHITE = 1;
export const COLOR_BLACK = 2;

// Game status (matching Move contract)
export const GAME_STATUS_ACTIVE = 1;
export const GAME_STATUS_WHITE_WIN_CHECKMATE = 2;
export const GAME_STATUS_BLACK_WIN_CHECKMATE = 3;
export const GAME_STATUS_DRAW_STALEMATE = 4;
export const GAME_STATUS_DRAW_AGREEMENT = 5;
export const GAME_STATUS_DRAW_50_MOVE = 6;
export const GAME_STATUS_DRAW_INSUFFICIENT = 7;
export const GAME_STATUS_WHITE_WIN_TIMEOUT = 8;
export const GAME_STATUS_BLACK_WIN_TIMEOUT = 9;
export const GAME_STATUS_WHITE_WIN_RESIGNATION = 10;
export const GAME_STATUS_BLACK_WIN_RESIGNATION = 11;
export const GAME_STATUS_DRAW_REPETITION = 12;

// Helper groupings
export const WHITE_WIN_STATUSES = [
  GAME_STATUS_WHITE_WIN_CHECKMATE,
  GAME_STATUS_WHITE_WIN_TIMEOUT,
  GAME_STATUS_WHITE_WIN_RESIGNATION,
];
export const BLACK_WIN_STATUSES = [
  GAME_STATUS_BLACK_WIN_CHECKMATE,
  GAME_STATUS_BLACK_WIN_TIMEOUT,
  GAME_STATUS_BLACK_WIN_RESIGNATION,
];
export const DRAW_STATUSES = [
  GAME_STATUS_DRAW_STALEMATE,
  GAME_STATUS_DRAW_AGREEMENT,
  GAME_STATUS_DRAW_50_MOVE,
  GAME_STATUS_DRAW_INSUFFICIENT,
  GAME_STATUS_DRAW_REPETITION,
];

// Challenge status (matching Move contract)
export const CHALLENGE_STATUS_OPEN = 0;
export const CHALLENGE_STATUS_ACCEPTED = 1;
export const CHALLENGE_STATUS_CANCELLED = 2;
export const CHALLENGE_STATUS_EXPIRED = 3;

// Color preferences for challenges
export const COLOR_RANDOM = 0;
// COLOR_WHITE and COLOR_BLACK already defined above

// Time control presets (in seconds)
// Contract limits: min 30s, max 10800s (3 hours), increment max 60s
export const TIME_CONTROLS: readonly { label: string; base: number; increment: number }[] = [
  { label: "1 min", base: 60, increment: 0 },
  { label: "3 min", base: 180, increment: 2 },
  { label: "5 min", base: 300, increment: 0 },
  { label: "10 min", base: 600, increment: 0 },
  { label: "15+10", base: 900, increment: 10 },
  { label: "30 min", base: 1800, increment: 0 },
];

// Initial ELO rating
export const INITIAL_RATING = 1200;

// Piece characters for notation
export const PIECE_SYMBOLS: Record<number, string> = {
  [PIECE_PAWN]: "",
  [PIECE_KNIGHT]: "N",
  [PIECE_BISHOP]: "B",
  [PIECE_ROOK]: "R",
  [PIECE_QUEEN]: "Q",
  [PIECE_KING]: "K",
};

// File letters
export const FILES = ["a", "b", "c", "d", "e", "f", "g", "h"] as const;

// Rank numbers
export const RANKS = ["8", "7", "6", "5", "4", "3", "2", "1"] as const;

// Convert square index to algebraic notation
export function squareToAlgebraic(square: number): string {
  const file = square % 8;
  const rank = Math.floor(square / 8);
  return `${FILES[file]}${RANKS[rank]}`;
}

// Convert algebraic notation to square index
export function algebraicToSquare(algebraic: string): number {
  const file = algebraic.charCodeAt(0) - 97; // 'a' = 97
  const rank = 8 - parseInt(algebraic[1]);
  return rank * 8 + file;
}

// Format time remaining in mm:ss or ss.t format
export function formatTime(ms: number): string {
  if (ms <= 0) return "0:00";

  const totalSeconds = Math.floor(ms / 1000);
  const minutes = Math.floor(totalSeconds / 60);
  const seconds = totalSeconds % 60;

  if (totalSeconds < 10) {
    // Show tenths of seconds when under 10 seconds
    const tenths = Math.floor((ms % 1000) / 100);
    return `${seconds}.${tenths}`;
  }

  return `${minutes}:${seconds.toString().padStart(2, "0")}`;
}

// Get game status text
export function getGameStatusText(status: number): string {
  switch (status) {
    case GAME_STATUS_ACTIVE:
      return "In progress";
    case GAME_STATUS_WHITE_WIN_CHECKMATE:
      return "White wins by checkmate";
    case GAME_STATUS_BLACK_WIN_CHECKMATE:
      return "Black wins by checkmate";
    case GAME_STATUS_DRAW_STALEMATE:
      return "Draw by stalemate";
    case GAME_STATUS_DRAW_AGREEMENT:
      return "Draw by agreement";
    case GAME_STATUS_DRAW_50_MOVE:
      return "Draw by 50-move rule";
    case GAME_STATUS_DRAW_INSUFFICIENT:
      return "Draw by insufficient material";
    case GAME_STATUS_WHITE_WIN_TIMEOUT:
      return "White wins on time";
    case GAME_STATUS_BLACK_WIN_TIMEOUT:
      return "Black wins on time";
    case GAME_STATUS_WHITE_WIN_RESIGNATION:
      return "White wins by resignation";
    case GAME_STATUS_BLACK_WIN_RESIGNATION:
      return "Black wins by resignation";
    case GAME_STATUS_DRAW_REPETITION:
      return "Draw by repetition";
    default:
      return "Unknown";
  }
}

// Get short result reason for modals
export function getResultReason(status: number): string {
  switch (status) {
    case GAME_STATUS_WHITE_WIN_CHECKMATE:
    case GAME_STATUS_BLACK_WIN_CHECKMATE:
      return "Checkmate";
    case GAME_STATUS_WHITE_WIN_TIMEOUT:
      return "White ran out of time";
    case GAME_STATUS_BLACK_WIN_TIMEOUT:
      return "Black ran out of time";
    case GAME_STATUS_WHITE_WIN_RESIGNATION:
      return "Black resigned";
    case GAME_STATUS_BLACK_WIN_RESIGNATION:
      return "White resigned";
    case GAME_STATUS_DRAW_STALEMATE:
      return "Stalemate";
    case GAME_STATUS_DRAW_AGREEMENT:
      return "Draw agreed";
    case GAME_STATUS_DRAW_50_MOVE:
      return "50-move rule";
    case GAME_STATUS_DRAW_INSUFFICIENT:
      return "Insufficient material";
    case GAME_STATUS_DRAW_REPETITION:
      return "Threefold repetition";
    default:
      return "";
  }
}

// Check if game is over
export function isGameOver(status: number): boolean {
  return status >= GAME_STATUS_WHITE_WIN_CHECKMATE;
}

// Check if white won
export function isWhiteWin(status: number): boolean {
  return WHITE_WIN_STATUSES.includes(status);
}

// Check if black won
export function isBlackWin(status: number): boolean {
  return BLACK_WIN_STATUSES.includes(status);
}

// Check if draw
export function isDraw(status: number): boolean {
  return DRAW_STATUSES.includes(status);
}
