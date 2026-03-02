"use client";

import { useState, useEffect, useCallback, use, useRef } from "react";
import { useRouter } from "next/navigation";
import { Button } from "@moveindustries/movement-design-system";
import { useMovementSDK } from "@movement-labs/miniapp-sdk";
import ChessBoard from "@/components/chess/ChessBoard";
import GameTimer from "@/components/chess/GameTimer";
import PromotionModal from "@/components/chess/PromotionModal";
import GameOverModal from "@/components/chess/GameOverModal";
import {
  getChessModuleAddress,
  COLOR_WHITE,
  COLOR_BLACK,
  GAME_STATUS_ACTIVE,
  isGameOver,
  getGameStatusText,
} from "../../../../constants";

interface Square {
  piece_type: number;
  color: number;
}

interface GameState {
  game_id: number;
  white_player: string;
  black_player: string;
  board: Square[];
  active_color: number;
  status: number;
  white_time_remaining_ms: number;
  black_time_remaining_ms: number;
  last_move_timestamp_ms: number;
}

interface PageParams {
  params: Promise<{ gameId: string }>;
}

export default function GamePage({ params }: PageParams) {
  const resolvedParams = use(params);
  const gameId = resolvedParams.gameId;
  const router = useRouter();
  const { sdk, address } = useMovementSDK();

  const [gameState, setGameState] = useState<GameState | null>(null);
  const [selectedSquare, setSelectedSquare] = useState<number | null>(null);
  const [legalMoves, setLegalMoves] = useState<number[]>([]);
  const [promotionMove, setPromotionMove] = useState<{
    from: number;
    to: number;
  } | null>(null);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState("");
  const timeoutClaimedRef = useRef(false);

  const playerColor =
    address?.toLowerCase() === gameState?.white_player?.toLowerCase()
      ? COLOR_WHITE
      : address?.toLowerCase() === gameState?.black_player?.toLowerCase()
        ? COLOR_BLACK
        : null;

  const isMyTurn = gameState?.active_color === playerColor;
  const isGameActive = gameState?.status === GAME_STATUS_ACTIVE;

  const fetchGameState = useCallback(async () => {
    if (!sdk || !gameId) return;

    try {
      // Fetch game state (returns tuple) and board in parallel
      const [stateResult, boardResult] = await Promise.all([
        sdk.view({
          function: `${getChessModuleAddress(sdk.network)}::chess_game::get_game_state`,
          type_arguments: [],
          function_arguments: [gameId],
        }),
        sdk.view({
          function: `${getChessModuleAddress(sdk.network)}::chess_game::get_board`,
          type_arguments: [],
          function_arguments: [gameId],
        }),
      ]);

      // get_game_state returns tuple: (game_id, white_player, black_player, active_color, status,
      //   white_time_remaining_ms, black_time_remaining_ms, last_move_timestamp_ms,
      //   en_passant_target, halfmove_clock, fullmove_number, draw_offer_by)
      const stateData = Array.isArray(stateResult) ? stateResult : [stateResult];

      // get_board returns vector<Square>
      const boardData = Array.isArray(boardResult) ? boardResult[0] : boardResult;
      const board = Array.isArray(boardData)
        ? boardData.map((sq: Record<string, unknown>) => ({
            piece_type: Number(sq.piece_type || 0),
            color: Number(sq.color || 0),
          }))
        : [];

      setGameState({
        game_id: Number(stateData[0] || 0),
        white_player: String(stateData[1] || ""),
        black_player: String(stateData[2] || ""),
        board,
        active_color: Number(stateData[3] || 1),
        status: Number(stateData[4] || 0),
        white_time_remaining_ms: Number(stateData[5] || 0),
        black_time_remaining_ms: Number(stateData[6] || 0),
        last_move_timestamp_ms: Number(stateData[7] || 0),
      });
    } catch (err) {
      console.error("[Game] Failed to fetch state:", err);
      setError("Failed to load game");
    }
  }, [sdk, gameId]);

  useEffect(() => {
    fetchGameState();
    const interval = setInterval(fetchGameState, 5000); // Poll every 5s instead of 2s
    return () => clearInterval(interval);
  }, [fetchGameState]);

  // Auto-claim timeout when opponent's time runs out
  useEffect(() => {
    if (!sdk || !gameState || !isGameActive || !playerColor || timeoutClaimedRef.current) {
      return;
    }

    const checkTimeout = async () => {
      const now = Date.now();
      const elapsed = now - gameState.last_move_timestamp_ms;

      // Calculate opponent's remaining time
      const opponentTimeMs =
        playerColor === COLOR_WHITE
          ? gameState.black_time_remaining_ms
          : gameState.white_time_remaining_ms;

      // Only check opponent's time when it's their turn
      const isOpponentsTurn = gameState.active_color !== playerColor;
      if (!isOpponentsTurn) return;

      const opponentRemainingTime = opponentTimeMs - elapsed;

      if (opponentRemainingTime <= 0) {
        timeoutClaimedRef.current = true;
        try {
          await sdk.sendTransaction({
            function: `${getChessModuleAddress(sdk.network)}::chess_game::claim_timeout`,
            type_arguments: [],
            arguments: [gameId],
            title: "Claim Timeout",
            description: "Opponent ran out of time",
          });
          await fetchGameState();
        } catch (e) {
          console.error("[Game] Failed to auto-claim timeout:", e);
          timeoutClaimedRef.current = false; // Allow retry
        }
      }
    };

    const interval = setInterval(checkTimeout, 3000); // Check every 3s
    checkTimeout(); // Check immediately

    return () => clearInterval(interval);
  }, [sdk, gameState, isGameActive, playerColor, gameId, fetchGameState]);

  const fetchLegalMoves = useCallback(
    async (square: number) => {
      if (!sdk || !gameId) return [];

      try {
        const result = await sdk.view({
          function: `${getChessModuleAddress(sdk.network)}::chess_game::get_legal_moves_for_square`,
          type_arguments: [],
          function_arguments: [gameId, square],
        });

        // Result is ["0x..."] where the hex string contains the u8 bytes
        const data = Array.isArray(result) ? result[0] : result;

        // Parse hex string to byte array (each 2 hex chars = 1 u8 square index)
        if (typeof data === "string" && data.startsWith("0x")) {
          const hex = data.slice(2); // Remove "0x" prefix
          const moves: number[] = [];
          for (let i = 0; i < hex.length; i += 2) {
            moves.push(parseInt(hex.substring(i, i + 2), 16));
          }
          return moves;
        }

        // Fallback for array format
        const moves = Array.isArray(data) ? data : [];
        return moves.map((m: unknown) => Number(m));
      } catch (err) {
        console.error("[Game] Failed to fetch legal moves:", err);
        return [];
      }
    },
    [sdk, gameId]
  );

  const handleSquareClick = async (square: number) => {
    if (!isGameActive || !isMyTurn || !gameState) return;

    const piece = gameState.board[square];

    // If clicking on own piece, select it
    if (piece.color === playerColor) {
      setSelectedSquare(square);
      const moves = await fetchLegalMoves(square);
      setLegalMoves(moves);
      return;
    }

    // If a piece is selected and clicking on a legal move target
    if (selectedSquare !== null && legalMoves.includes(square)) {
      const fromPiece = gameState.board[selectedSquare];

      // Check for pawn promotion
      const isPawn = fromPiece.piece_type === 1;
      const toRank = Math.floor(square / 8);
      const isPromotionRank =
        (playerColor === COLOR_WHITE && toRank === 0) ||
        (playerColor === COLOR_BLACK && toRank === 7);

      if (isPawn && isPromotionRank) {
        setPromotionMove({ from: selectedSquare, to: square });
        return;
      }

      await makeMove(selectedSquare, square, 0);
    } else {
      // Deselect
      setSelectedSquare(null);
      setLegalMoves([]);
    }
  };

  const makeMove = async (from: number, to: number, promotion: number) => {
    if (!sdk || !gameId) return;

    setIsLoading(true);
    setError("");

    try {
      await sdk.haptic?.({ type: "impact", style: "light" });
      await sdk.sendTransaction({
        function: `${getChessModuleAddress(sdk.network)}::chess_game::make_move`,
        type_arguments: [],
        arguments: [gameId, from, to, promotion],
        title: "Make Move",
        description: "Execute chess move",
      });

      setSelectedSquare(null);
      setLegalMoves([]);
      setPromotionMove(null);
      await fetchGameState();
      await sdk.haptic?.({ type: "notification", style: "success" });
    } catch (e) {
      const errorMessage = e instanceof Error ? e.message : "Failed to make move";
      setError(errorMessage);
      await sdk.haptic?.({ type: "notification", style: "error" });
    } finally {
      setIsLoading(false);
    }
  };

  const handlePromotion = (pieceType: number) => {
    if (promotionMove) {
      makeMove(promotionMove.from, promotionMove.to, pieceType);
    }
  };

  const handleResign = async () => {
    if (!sdk || !gameId) return;

    try {
      await sdk.haptic?.({ type: "impact", style: "medium" });
      await sdk.sendTransaction({
        function: `${getChessModuleAddress(sdk.network)}::chess_game::resign`,
        type_arguments: [],
        arguments: [gameId],
        title: "Resign Game",
        description: "Resign from this game",
      });

      await fetchGameState();
    } catch (e) {
      const errorMessage = e instanceof Error ? e.message : "Failed to resign";
      setError(errorMessage);
    }
  };

  const handleClaimTimeout = async () => {
    if (!sdk || !gameId) return;

    try {
      await sdk.sendTransaction({
        function: `${getChessModuleAddress(sdk.network)}::chess_game::claim_timeout`,
        type_arguments: [],
        arguments: [gameId],
        title: "Claim Timeout",
        description: "Claim win by timeout",
      });

      await fetchGameState();
    } catch (e) {
      const errorMessage = e instanceof Error ? e.message : "Failed to claim timeout";
      setError(errorMessage);
    }
  };

  if (!gameState) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-gray-50 dark:bg-gray-900">
        <div className="text-gray-500 dark:text-gray-400">Loading game...</div>
      </div>
    );
  }

  const gameIsOver = isGameOver(gameState.status);

  return (
    <div className="min-h-screen bg-gray-50 dark:bg-gray-900 flex flex-col">
      {/* Opponent Timer & Info */}
      <div className="bg-white dark:bg-gray-800 shadow-sm p-3">
        <div className="max-w-lg mx-auto flex items-center justify-between">
          <div className="text-sm text-gray-600 dark:text-gray-300 font-mono">
            {playerColor === COLOR_WHITE
              ? `${gameState.black_player.slice(0, 6)}...${gameState.black_player.slice(-4)}`
              : `${gameState.white_player.slice(0, 6)}...${gameState.white_player.slice(-4)}`}
          </div>
          <GameTimer
            timeMs={
              playerColor === COLOR_WHITE
                ? gameState.black_time_remaining_ms
                : gameState.white_time_remaining_ms
            }
            isActive={
              isGameActive &&
              gameState.active_color !==
                (playerColor === COLOR_WHITE ? COLOR_WHITE : COLOR_BLACK)
            }
            lastMoveTimestamp={gameState.last_move_timestamp_ms}
          />
        </div>
      </div>

      {/* Error Message */}
      {error && (
        <div className="max-w-lg mx-auto px-4 py-2">
          <div className="p-2 bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 rounded text-xs text-red-600 dark:text-red-400">
            {error}
          </div>
        </div>
      )}

      {/* Chess Board */}
      <div className="flex-1 flex items-center justify-center px-2">
        <ChessBoard
          board={gameState.board}
          selectedSquare={selectedSquare}
          legalMoves={legalMoves}
          playerColor={playerColor || COLOR_WHITE}
          onSquareClick={handleSquareClick}
          disabled={!isGameActive || !isMyTurn || isLoading}
        />
      </div>

      {/* Player Timer & Controls */}
      <div className="bg-white dark:bg-gray-800 shadow-sm p-3">
        <div className="max-w-lg mx-auto">
          <div className="flex items-center justify-between mb-3">
            <div className="text-sm text-gray-600 dark:text-gray-300 font-mono">
              You ({playerColor === COLOR_WHITE ? "White" : "Black"})
            </div>
            <GameTimer
              timeMs={
                playerColor === COLOR_WHITE
                  ? gameState.white_time_remaining_ms
                  : gameState.black_time_remaining_ms
              }
              isActive={isGameActive && isMyTurn}
              lastMoveTimestamp={gameState.last_move_timestamp_ms}
            />
          </div>

          {/* Turn Indicator */}
          {isGameActive && (
            <div
              className={`text-center text-sm py-2 rounded mb-3 ${
                isMyTurn
                  ? "bg-green-100 dark:bg-green-900/30 text-green-700 dark:text-green-300"
                  : "bg-gray-100 dark:bg-gray-700 text-gray-600 dark:text-gray-400"
              }`}
            >
              {isMyTurn ? "Your turn" : "Opponent's turn"}
            </div>
          )}

          {/* Game Controls */}
          {isGameActive && playerColor && (
            <div className="flex gap-2">
              <Button
                onClick={handleResign}
                variant="outline"
                size="sm"
                className="flex-1"
              >
                Resign
              </Button>
              <Button
                onClick={handleClaimTimeout}
                variant="outline"
                size="sm"
                className="flex-1"
              >
                Claim Timeout
              </Button>
            </div>
          )}

          {/* Back to Lobby (when game is over) */}
          {gameIsOver && (
            <Button
              onClick={() => router.push("/lobby")}
              variant="default"
              color="green"
              size="lg"
              className="w-full"
            >
              Back to Lobby
            </Button>
          )}
        </div>
      </div>

      {/* Promotion Modal */}
      {promotionMove && (
        <PromotionModal
          playerColor={playerColor || COLOR_WHITE}
          onSelect={handlePromotion}
          onCancel={() => setPromotionMove(null)}
        />
      )}

      {/* Game Over Modal */}
      {gameIsOver && (
        <GameOverModal
          status={gameState.status}
          playerColor={playerColor}
          onClose={() => router.push("/lobby")}
        />
      )}
    </div>
  );
}
