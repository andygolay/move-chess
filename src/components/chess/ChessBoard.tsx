"use client";

import ChessPiece from "./ChessPieces";
import { COLOR_WHITE, COLOR_BLACK } from "../../../constants";

interface Square {
  piece_type: number;
  color: number;
}

interface ChessBoardProps {
  board: Square[];
  selectedSquare: number | null;
  legalMoves: number[];
  playerColor: number;
  onSquareClick: (square: number) => void;
  disabled?: boolean;
}

export default function ChessBoard({
  board,
  selectedSquare,
  legalMoves,
  playerColor,
  onSquareClick,
  disabled = false,
}: ChessBoardProps) {
  // Flip board if player is black
  const shouldFlip = playerColor === COLOR_BLACK;

  const getSquareColor = (row: number, col: number) => {
    return (row + col) % 2 === 0 ? "bg-amber-100" : "bg-amber-700";
  };

  const renderSquare = (visualRow: number, visualCol: number) => {
    // Convert visual position to actual board index
    const actualRow = shouldFlip ? 7 - visualRow : visualRow;
    const actualCol = shouldFlip ? 7 - visualCol : visualCol;
    const squareIndex = actualRow * 8 + actualCol;

    const piece = board[squareIndex];
    const isSelected = selectedSquare === squareIndex;
    const isLegalMove = legalMoves.includes(squareIndex);
    const hasPiece = piece && piece.piece_type !== 0;
    const isCapture = isLegalMove && hasPiece;

    return (
      <button
        key={squareIndex}
        onClick={() => !disabled && onSquareClick(squareIndex)}
        disabled={disabled}
        className={`
          relative aspect-square flex items-center justify-center
          ${getSquareColor(actualRow, actualCol)}
          ${isSelected ? "ring-4 ring-yellow-400 ring-inset" : ""}
          ${disabled ? "cursor-default" : "cursor-pointer"}
          transition-all duration-100
        `}
      >
        {/* Piece */}
        {hasPiece && (
          <ChessPiece
            pieceType={piece.piece_type}
            color={piece.color}
            className="w-[85%] h-[85%]"
          />
        )}

        {/* Legal move indicator */}
        {isLegalMove && !isCapture && (
          <div className="absolute inset-0 flex items-center justify-center pointer-events-none">
            <div className="w-3 h-3 rounded-full bg-black/20" />
          </div>
        )}

        {/* Capture indicator */}
        {isCapture && (
          <div className="absolute inset-0 rounded-full border-4 border-black/30 pointer-events-none" />
        )}

        {/* File labels (bottom row) */}
        {visualRow === 7 && (
          <span
            className={`absolute bottom-0.5 right-1 text-[10px] font-medium ${
              (actualRow + actualCol) % 2 === 0
                ? "text-amber-700"
                : "text-amber-100"
            }`}
          >
            {String.fromCharCode(97 + actualCol)}
          </span>
        )}

        {/* Rank labels (left column) */}
        {visualCol === 0 && (
          <span
            className={`absolute top-0.5 left-1 text-[10px] font-medium ${
              (actualRow + actualCol) % 2 === 0
                ? "text-amber-700"
                : "text-amber-100"
            }`}
          >
            {8 - actualRow}
          </span>
        )}
      </button>
    );
  };

  return (
    <div className="w-full max-w-[400px] aspect-square">
      <div className="grid grid-cols-8 w-full h-full border-2 border-amber-900 rounded overflow-hidden shadow-lg">
        {Array.from({ length: 8 }, (_, row) =>
          Array.from({ length: 8 }, (_, col) => renderSquare(row, col))
        )}
      </div>
    </div>
  );
}
