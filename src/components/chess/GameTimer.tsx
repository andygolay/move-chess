"use client";

import { useState, useEffect } from "react";
import { formatTime } from "../../../constants";

interface GameTimerProps {
  timeMs: number;
  isActive: boolean;
  lastMoveTimestamp: number;
}

export default function GameTimer({
  timeMs,
  isActive,
  lastMoveTimestamp,
}: GameTimerProps) {
  const [displayTime, setDisplayTime] = useState(timeMs);

  useEffect(() => {
    if (!isActive) {
      setDisplayTime(timeMs);
      return;
    }

    // Calculate remaining time based on elapsed time since last move
    // Note: Device clock drift may cause slight differences between players
    const updateTime = () => {
      const now = Date.now();
      const elapsed = now - lastMoveTimestamp;
      const remaining = Math.max(0, timeMs - elapsed);
      setDisplayTime(remaining);
    };

    updateTime();
    const interval = setInterval(updateTime, 100);

    return () => clearInterval(interval);
  }, [timeMs, isActive, lastMoveTimestamp]);

  const isLowTime = displayTime < 30000; // Less than 30 seconds
  const isCriticalTime = displayTime < 10000; // Less than 10 seconds

  return (
    <div
      className={`
        px-3 py-1.5 rounded font-mono text-lg font-bold
        ${
          isActive
            ? isCriticalTime
              ? "bg-red-600 text-white animate-pulse"
              : isLowTime
                ? "bg-orange-500 text-white"
                : "bg-green-600 text-white"
            : "bg-gray-200 dark:bg-gray-700 text-gray-700 dark:text-gray-300"
        }
      `}
    >
      {formatTime(displayTime)}
    </div>
  );
}
