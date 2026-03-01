"use client";

import { useState, useEffect, useCallback } from "react";
import { useMovementSDK } from "@movement-labs/miniapp-sdk";
import BottomNav from "@/components/navigation/BottomNav";
import { getChessModuleAddress } from "../../../constants";

interface PlayerStats {
  player: string;
  rating: number;
  games_played: number;
  wins: number;
  losses: number;
  draws: number;
  highest_rating: number;
}

export default function LeaderboardPage() {
  const { sdk, address } = useMovementSDK();
  const [players, setPlayers] = useState<PlayerStats[]>([]);
  const [isLoading, setIsLoading] = useState(true);

  const fetchLeaderboard = useCallback(async () => {
    if (!sdk) return;

    setIsLoading(true);
    try {
      const result = await sdk.view({
        function: `${getChessModuleAddress(sdk.network)}::chess_leaderboard::get_top_players`,
        type_arguments: [],
        function_arguments: ["50"],
      });

      const data = Array.isArray(result) ? result[0] : result;
      if (Array.isArray(data)) {
        const parsed = data.map((p: Record<string, unknown>) => ({
          player: String(p.player || ""),
          rating: Number(p.rating || 0),
          games_played: Number(p.games_played || 0),
          wins: Number(p.wins || 0),
          losses: Number(p.losses || 0),
          draws: Number(p.draws || 0),
          highest_rating: Number(p.highest_rating || 0),
        }));
        setPlayers(parsed);
      }
    } catch (err) {
      console.error("[Leaderboard] Failed to fetch:", err);
    } finally {
      setIsLoading(false);
    }
  }, [sdk]);

  useEffect(() => {
    fetchLeaderboard();
  }, [fetchLeaderboard]);

  const formatAddress = (addr: string) => {
    if (!addr || addr.length < 10) return addr;
    return `${addr.slice(0, 6)}...${addr.slice(-4)}`;
  };

  const getWinRate = (wins: number, games: number) => {
    if (games === 0) return "0%";
    return `${Math.round((wins / games) * 100)}%`;
  };

  return (
    <div className="min-h-screen bg-gray-50 dark:bg-gray-900">
      {/* Header */}
      <div className="bg-white dark:bg-gray-800 shadow-sm">
        <div className="max-w-lg mx-auto px-4 py-4">
          <h1 className="text-xl font-bold text-gray-900 dark:text-white">
            Leaderboard
          </h1>
        </div>
      </div>

      {/* Main Content */}
      <div className="max-w-lg mx-auto px-4 py-4">
        {isLoading ? (
          <div className="text-center py-12 text-gray-500 dark:text-gray-400">
            Loading rankings...
          </div>
        ) : players.length === 0 ? (
          <div className="text-center py-12">
            <div className="text-4xl mb-4">🏆</div>
            <p className="text-gray-500 dark:text-gray-400">
              No players yet. Be the first to register!
            </p>
          </div>
        ) : (
          <div className="space-y-2">
            {players.map((player, index) => {
              const isCurrentUser =
                address?.toLowerCase() === player.player.toLowerCase();
              const rank = index + 1;

              return (
                <div
                  key={player.player}
                  className={`bg-white dark:bg-gray-800 rounded-lg p-3 shadow-sm flex items-center gap-3 ${
                    isCurrentUser ? "ring-2 ring-green-500" : ""
                  }`}
                >
                  {/* Rank */}
                  <div
                    className={`w-8 h-8 rounded-full flex items-center justify-center text-sm font-bold ${
                      rank === 1
                        ? "bg-yellow-100 text-yellow-700 dark:bg-yellow-900 dark:text-yellow-300"
                        : rank === 2
                          ? "bg-gray-200 text-gray-700 dark:bg-gray-600 dark:text-gray-200"
                          : rank === 3
                            ? "bg-orange-100 text-orange-700 dark:bg-orange-900 dark:text-orange-300"
                            : "bg-gray-100 text-gray-600 dark:bg-gray-700 dark:text-gray-300"
                    }`}
                  >
                    {rank}
                  </div>

                  {/* Player Info */}
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-2">
                      <span
                        className={`font-mono text-sm ${
                          isCurrentUser
                            ? "text-green-600 dark:text-green-400 font-semibold"
                            : "text-gray-900 dark:text-white"
                        }`}
                      >
                        {formatAddress(player.player)}
                      </span>
                      {isCurrentUser && (
                        <span className="text-xs bg-green-100 dark:bg-green-900 text-green-700 dark:text-green-300 px-1.5 py-0.5 rounded">
                          You
                        </span>
                      )}
                    </div>
                    <div className="text-xs text-gray-500 dark:text-gray-400 mt-0.5">
                      {player.games_played} games •{" "}
                      {getWinRate(player.wins, player.games_played)} win rate
                    </div>
                  </div>

                  {/* Rating */}
                  <div className="text-right">
                    <div className="text-lg font-bold text-gray-900 dark:text-white">
                      {player.rating}
                    </div>
                    <div className="text-xs text-gray-400">
                      {player.wins}W/{player.losses}L/{player.draws}D
                    </div>
                  </div>
                </div>
              );
            })}
          </div>
        )}
      </div>

      <BottomNav />
    </div>
  );
}
