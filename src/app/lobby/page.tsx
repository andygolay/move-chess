"use client";

import { useState, useEffect, useCallback } from "react";
import { Button } from "@moveindustries/movement-design-system";
import { useMovementSDK } from "@movement-labs/miniapp-sdk";
import BottomNav from "@/components/navigation/BottomNav";
import ChallengeList from "@/components/lobby/ChallengeList";
import {
  getChessModuleAddress,
  INITIAL_RATING,
  TIME_CONTROLS,
} from "../../../constants";

interface PlayerStats {
  rating: number;
  games_played: number;
  wins: number;
  losses: number;
  draws: number;
}

export default function LobbyPage() {
  const { sdk, isConnected, address } = useMovementSDK();
  const [isRegistered, setIsRegistered] = useState(false);
  const [playerStats, setPlayerStats] = useState<PlayerStats | null>(null);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState("");

  const checkRegistration = useCallback(async () => {
    if (!sdk || !address) return;

    try {
      const result = await sdk.view({
        function: `${getChessModuleAddress(sdk.network)}::chess_leaderboard::is_registered`,
        type_arguments: [],
        function_arguments: [address],
      });
      const registered = Array.isArray(result) ? result[0] : result;
      setIsRegistered(Boolean(registered));

      if (registered) {
        const stats = await sdk.view({
          function: `${getChessModuleAddress(sdk.network)}::chess_leaderboard::get_player_stats`,
          type_arguments: [],
          function_arguments: [address],
        });
        const statsData = Array.isArray(stats) ? stats[0] : stats;
        if (statsData) {
          setPlayerStats({
            rating: Number(statsData.rating || INITIAL_RATING),
            games_played: Number(statsData.games_played || 0),
            wins: Number(statsData.wins || 0),
            losses: Number(statsData.losses || 0),
            draws: Number(statsData.draws || 0),
          });
        }
      }
    } catch (err) {
      console.error("[Lobby] Failed to check registration:", err);
    }
  }, [sdk, address]);

  useEffect(() => {
    if (isConnected && address) {
      checkRegistration();
    }
  }, [isConnected, address, checkRegistration]);

  const handleRegister = async () => {
    if (!sdk || !isConnected) {
      setError("Please connect your wallet first");
      return;
    }

    setIsLoading(true);
    setError("");

    try {
      await sdk.haptic?.({ type: "impact", style: "light" });
      await sdk.sendTransaction({
        function: `${getChessModuleAddress(sdk.network)}::chess_leaderboard::register_player`,
        type_arguments: [],
        arguments: [],
        title: "Register for Chess",
        description: "Create your player profile with initial rating",
        useFeePayer: true,
        gasLimit: "Sponsored",
      });

      await checkRegistration();
      await sdk.notify?.({
        title: "Welcome!",
        body: `You're registered with ${INITIAL_RATING} rating`,
      });
    } catch (e) {
      const errorMessage =
        e instanceof Error ? e.message : "Failed to register";
      setError(errorMessage);
    } finally {
      setIsLoading(false);
    }
  };

  const handleQuickPlay = async (timeControl: (typeof TIME_CONTROLS)[number]) => {
    if (!sdk || !isConnected || !isRegistered) return;

    setIsLoading(true);
    setError("");

    try {
      await sdk.haptic?.({ type: "impact", style: "light" });
      await sdk.sendTransaction({
        function: `${getChessModuleAddress(sdk.network)}::chess_lobby::create_open_challenge`,
        type_arguments: [],
        arguments: [
          timeControl.base.toString(),
          timeControl.increment.toString(),
          "0", // Random color
          "0", // No min rating
          "0", // No max rating
          "3600", // 1 hour expiry
        ],
        title: "Create Challenge",
        description: `Create ${timeControl.label} challenge`,
        useFeePayer: true,
        gasLimit: "Sponsored",
      });

      await sdk.notify?.({
        title: "Challenge Created",
        body: `${timeControl.label} challenge is now open`,
      });
    } catch (e) {
      const errorMessage =
        e instanceof Error ? e.message : "Failed to create challenge";
      setError(errorMessage);
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <div className="min-h-screen bg-gray-50 dark:bg-gray-900">
      {/* Header */}
      <div className="bg-white dark:bg-gray-800 shadow-sm">
        <div className="max-w-lg mx-auto px-4 py-4">
          <div className="flex items-center justify-between">
            <h1 className="text-xl font-bold text-gray-900 dark:text-white">
              Chess Lobby
            </h1>
            {isRegistered && playerStats && (
              <div className="text-right">
                <div className="text-lg font-bold text-green-600 dark:text-green-400">
                  {playerStats.rating}
                </div>
                <div className="text-xs text-gray-500 dark:text-gray-400">
                  {playerStats.wins}W / {playerStats.losses}L / {playerStats.draws}D
                </div>
              </div>
            )}
          </div>
        </div>
      </div>

      {/* Main Content */}
      <div className="max-w-lg mx-auto px-4 py-6 space-y-6">
        {/* Error Message */}
        {error && (
          <div className="p-3 bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 rounded-lg text-sm text-red-600 dark:text-red-400">
            {error}
          </div>
        )}

        {!isConnected ? (
          /* Not Connected State */
          <div className="bg-white dark:bg-gray-800 rounded-xl p-8 text-center shadow-sm">
            <h2 className="text-lg font-semibold text-gray-900 dark:text-white mb-2">
              Connect to Play
            </h2>
            <p className="text-gray-500 dark:text-gray-400 text-sm">
              Connect your wallet to join the chess lobby
            </p>
          </div>
        ) : !isRegistered ? (
          /* Not Registered State */
          <div className="bg-white dark:bg-gray-800 rounded-xl p-8 text-center shadow-sm">
            <h2 className="text-lg font-semibold text-gray-900 dark:text-white mb-2">
              Join the Game
            </h2>
            <p className="text-gray-500 dark:text-gray-400 text-sm mb-6">
              Register to start playing with an initial rating of {INITIAL_RATING}
            </p>
            <Button
              onClick={handleRegister}
              disabled={isLoading}
              variant="default"
              color="green"
              size="lg"
              className="w-full"
            >
              {isLoading ? "Registering..." : "Register"}
            </Button>
          </div>
        ) : (
          /* Registered - Show Lobby */
          <>
            {/* Create Game */}
            <div className="bg-white dark:bg-gray-800 rounded-xl p-4 shadow-sm">
              <h2 className="text-sm font-semibold text-gray-900 dark:text-white mb-3">
                Create Game
              </h2>
              <div className="grid grid-cols-2 gap-2">
                {TIME_CONTROLS.map((tc) => (
                  <Button
                    key={tc.label}
                    onClick={() => handleQuickPlay(tc)}
                    disabled={isLoading}
                    variant="outline"
                    size="sm"
                    className="w-full"
                  >
                    {tc.label}
                  </Button>
                ))}
              </div>
            </div>

            {/* Open Challenges */}
            <div className="bg-white dark:bg-gray-800 rounded-xl p-4 shadow-sm">
              <h2 className="text-sm font-semibold text-gray-900 dark:text-white mb-3">
                Open Challenges
              </h2>
              <ChallengeList currentAddress={address ?? undefined} />
            </div>
          </>
        )}
      </div>

      <BottomNav />
    </div>
  );
}
