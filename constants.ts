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
export const GAME_STATUS_PENDING = 0;
export const GAME_STATUS_ACTIVE = 1;
export const GAME_STATUS_WHITE_WIN = 2;
export const GAME_STATUS_BLACK_WIN = 3;
export const GAME_STATUS_DRAW = 4;
export const GAME_STATUS_WHITE_TIMEOUT = 5;
export const GAME_STATUS_BLACK_TIMEOUT = 6;
export const GAME_STATUS_WHITE_RESIGNED = 7;
export const GAME_STATUS_BLACK_RESIGNED = 8;

// Challenge status (matching Move contract)
export const CHALLENGE_STATUS_OPEN = 0;
export const CHALLENGE_STATUS_ACCEPTED = 1;
export const CHALLENGE_STATUS_CANCELLED = 2;
export const CHALLENGE_STATUS_EXPIRED = 3;

// Color preferences for challenges
export const COLOR_RANDOM = 0;
// COLOR_WHITE and COLOR_BLACK already defined above

// Time control presets (in seconds)
export const TIME_CONTROLS: readonly { label: string; base: number; increment: number }[] = [
  { label: "5 min", base: 300, increment: 0 },
  { label: "10 min", base: 600, increment: 0 },
  { label: "20 min", base: 1200, increment: 0 },
  { label: "30 min", base: 1800, increment: 0 },
  { label: "24 hours", base: 86400, increment: 0 },
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
    case GAME_STATUS_PENDING:
      return "Waiting to start";
    case GAME_STATUS_ACTIVE:
      return "In progress";
    case GAME_STATUS_WHITE_WIN:
      return "White wins";
    case GAME_STATUS_BLACK_WIN:
      return "Black wins";
    case GAME_STATUS_DRAW:
      return "Draw";
    case GAME_STATUS_WHITE_TIMEOUT:
      return "White timeout - Black wins";
    case GAME_STATUS_BLACK_TIMEOUT:
      return "Black timeout - White wins";
    case GAME_STATUS_WHITE_RESIGNED:
      return "White resigned - Black wins";
    case GAME_STATUS_BLACK_RESIGNED:
      return "Black resigned - White wins";
    default:
      return "Unknown";
  }
}

// Check if game is over
export function isGameOver(status: number): boolean {
  return status >= GAME_STATUS_WHITE_WIN;
}
