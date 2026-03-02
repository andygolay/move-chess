"use client";

import { Button } from "@moveindustries/movement-design-system";
import {
  COLOR_WHITE,
  COLOR_BLACK,
  isWhiteWin,
  isBlackWin,
  isDraw,
  getResultReason,
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
  const whiteWon = isWhiteWin(status);
  const blackWon = isBlackWin(status);
  const gameIsDraw = isDraw(status);

  const playerWon =
    (playerColor === COLOR_WHITE && whiteWon) ||
    (playerColor === COLOR_BLACK && blackWon);

  const playerLost =
    (playerColor === COLOR_WHITE && blackWon) ||
    (playerColor === COLOR_BLACK && whiteWon);

  const getResultText = () => {
    if (gameIsDraw) return "Draw";
    if (playerWon) return "You Win!";
    if (playerLost) return "You Lose";
    return whiteWon ? "White Wins" : "Black Wins";
  };

  const getEmoji = () => {
    if (gameIsDraw) return "\u{1F91D}";
    if (playerWon) return "\u{1F3C6}";
    if (playerLost) return "\u{1F614}";
    return "\u265F";
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
          {getResultReason(status)}
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
