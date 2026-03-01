"use client";

import { COLOR_WHITE, PIECE_QUEEN, PIECE_ROOK, PIECE_BISHOP, PIECE_KNIGHT } from "../../../constants";
import ChessPiece from "./ChessPieces";

interface PromotionModalProps {
  playerColor: number;
  onSelect: (pieceType: number) => void;
  onCancel: () => void;
}

const promotionPieces = [
  { type: PIECE_QUEEN, label: "Queen" },
  { type: PIECE_ROOK, label: "Rook" },
  { type: PIECE_BISHOP, label: "Bishop" },
  { type: PIECE_KNIGHT, label: "Knight" },
];

export default function PromotionModal({
  playerColor,
  onSelect,
  onCancel,
}: PromotionModalProps) {
  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50">
      <div className="bg-white dark:bg-gray-800 rounded-xl p-4 shadow-xl mx-4 w-full max-w-xs">
        <h3 className="text-lg font-semibold text-gray-900 dark:text-white text-center mb-4">
          Promote Pawn
        </h3>

        <div className="grid grid-cols-4 gap-2 mb-4">
          {promotionPieces.map((piece) => (
            <button
              key={piece.type}
              onClick={() => onSelect(piece.type)}
              className="aspect-square bg-amber-100 dark:bg-amber-900 rounded-lg p-2 hover:ring-2 ring-green-500 transition-all"
            >
              <ChessPiece
                pieceType={piece.type}
                color={playerColor}
                className="w-full h-full"
              />
            </button>
          ))}
        </div>

        <button
          onClick={onCancel}
          className="w-full py-2 text-sm text-gray-500 dark:text-gray-400 hover:text-gray-700 dark:hover:text-gray-200"
        >
          Cancel
        </button>
      </div>
    </div>
  );
}
