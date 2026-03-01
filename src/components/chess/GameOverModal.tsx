"use client";

import { Button } from "@moveindustries/movement-design-system";
import {
  COLOR_WHITE,
  COLOR_BLACK,
  GAME_STATUS_WHITE_WIN,
  GAME_STATUS_BLACK_WIN,
  GAME_STATUS_DRAW,
  GAME_STATUS_WHITE_TIMEOUT,
  GAME_STATUS_BLACK_TIMEOUT,
  GAME_STATUS_WHITE_RESIGNED,
  GAME_STATUS_BLACK_RESIGNED,
} from "../../../constants";

interface GameOverModalProps {
  status: number;
  playerColor: number | null;
  onClose: () => void;
}

export default function GameOverModal({
  status,
  playerColor,
  onClose,
}: GameOverModalProps) {
  const whiteWon =
    status === GAME_STATUS_WHITE_WIN ||
    status === GAME_STATUS_BLACK_TIMEOUT ||
    status === GAME_STATUS_BLACK_RESIGNED;

  const blackWon =
    status === GAME_STATUS_BLACK_WIN ||
    status === GAME_STATUS_WHITE_TIMEOUT ||
    status === GAME_STATUS_WHITE_RESIGNED;

  const isDraw = status === GAME_STATUS_DRAW;

  const playerWon =
    (playerColor === COLOR_WHITE && whiteWon) ||
    (playerColor === COLOR_BLACK && blackWon);

  const playerLost =
    (playerColor === COLOR_WHITE && blackWon) ||
    (playerColor === COLOR_BLACK && whiteWon);

  const getResultText = () => {
    if (isDraw) return "Draw";
    if (playerWon) return "You Win!";
    if (playerLost) return "You Lose";
    return whiteWon ? "White Wins" : "Black Wins";
  };

  const getResultReason = () => {
    switch (status) {
      case GAME_STATUS_WHITE_WIN:
      case GAME_STATUS_BLACK_WIN:
        return "Checkmate";
      case GAME_STATUS_WHITE_TIMEOUT:
        return "White ran out of time";
      case GAME_STATUS_BLACK_TIMEOUT:
        return "Black ran out of time";
      case GAME_STATUS_WHITE_RESIGNED:
        return "White resigned";
      case GAME_STATUS_BLACK_RESIGNED:
        return "Black resigned";
      case GAME_STATUS_DRAW:
        return "Game ended in draw";
      default:
        return "";
    }
  };

  const getEmoji = () => {
    if (isDraw) return "🤝";
    if (playerWon) return "🏆";
    if (playerLost) return "😔";
    return "♟";
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50">
      <div className="bg-white dark:bg-gray-800 rounded-xl p-6 shadow-xl mx-4 w-full max-w-xs text-center">
        <div className="text-5xl mb-4">{getEmoji()}</div>

        <h2
          className={`text-2xl font-bold mb-2 ${
            playerWon
              ? "text-green-600 dark:text-green-400"
              : playerLost
                ? "text-red-600 dark:text-red-400"
                : "text-gray-900 dark:text-white"
          }`}
        >
          {getResultText()}
        </h2>

        <p className="text-gray-500 dark:text-gray-400 mb-6">
          {getResultReason()}
        </p>

        <Button
          onClick={onClose}
          variant="default"
          color="green"
          size="lg"
          className="w-full"
        >
          Back to Lobby
        </Button>
      </div>
    </div>
  );
}
