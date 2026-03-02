"use client";

import { useState, useEffect, useCallback, useRef } from "react";
import { useRouter } from "next/navigation";
import { Button } from "@moveindustries/movement-design-system";
import { useMovementSDK } from "@movement-labs/miniapp-sdk";
import { getChessModuleAddress, CHALLENGE_STATUS_OPEN, CHALLENGE_STATUS_ACCEPTED } from "../../../constants";

interface Challenge {
  challenge_id: number;
  challenger: string;
  opponent: string;
  time_control_base_seconds: number;
  time_control_increment_seconds: number;
  challenger_color_pref: number;
  status: number;
  expires_at_ms: number;
  min_rating: number;
  max_rating: number;
}

interface ChallengeListProps {
  currentAddress: string | undefined;
}

export default function ChallengeList({ currentAddress }: ChallengeListProps) {
  const router = useRouter();
  const { sdk } = useMovementSDK();
  const [challenges, setChallenges] = useState<Challenge[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [acceptingId, setAcceptingId] = useState<number | null>(null);
  const myChallengeIdsRef = useRef<Set<number>>(new Set());

  // Check if any of user's challenges were accepted and redirect to game
  const checkMyChallengesAccepted = useCallback(async (currentOpenChallenges: Challenge[]) => {
    if (!sdk || !currentAddress) return;

    const currentOpenIds = new Set(
      currentOpenChallenges
        .filter(c => c.challenger.toLowerCase() === currentAddress.toLowerCase())
        .map(c => c.challenge_id)
    );

    // Find challenges that were in our list but are no longer open
    for (const challengeId of myChallengeIdsRef.current) {
      if (!currentOpenIds.has(challengeId)) {
        // Challenge is no longer open - check if it was accepted
        try {
          const result = await sdk.view({
            function: `${getChessModuleAddress(sdk.network)}::chess_lobby::get_challenge`,
            type_arguments: [],
            function_arguments: [challengeId.toString()],
          });

          const challengeData = Array.isArray(result) ? result[0] : result;
          const status = Number(challengeData?.status ?? -1);

          if (status === CHALLENGE_STATUS_ACCEPTED) {
            // Get the game ID and redirect
            const gameResult = await sdk.view({
              function: `${getChessModuleAddress(sdk.network)}::chess_lobby::get_game_id_for_challenge`,
              type_arguments: [],
              function_arguments: [challengeId.toString()],
            });

            const gameId = Array.isArray(gameResult) ? Number(gameResult[0]) : Number(gameResult);
            if (gameId > 0) {
              await sdk.haptic?.({ type: "notification", style: "success" });
              router.push(`/game/${gameId}`);
              return;
            }
          }
        } catch (err) {
          console.error("[ChallengeList] Failed to check challenge status:", err);
        }
      }
    }

    // Update our tracked challenge IDs
    myChallengeIdsRef.current = currentOpenIds;
  }, [sdk, currentAddress, router]);

  const fetchChallenges = useCallback(async () => {
    if (!sdk) return;

    try {
      const result = await sdk.view({
        function: `${getChessModuleAddress(sdk.network)}::chess_lobby::get_open_challenges`,
        type_arguments: [],
        function_arguments: [],
      });

      const data = Array.isArray(result) ? result[0] : result;
      if (Array.isArray(data)) {
        const parsed = data.map((c: Record<string, unknown>) => ({
          challenge_id: Number(c.challenge_id || 0),
          challenger: String(c.challenger || ""),
          opponent: String(c.opponent || ""),
          time_control_base_seconds: Number(c.time_control_base_seconds || 0),
          time_control_increment_seconds: Number(c.time_control_increment_seconds || 0),
          challenger_color_pref: Number(c.challenger_color_pref || 0),
          status: Number(c.status || 0),
          expires_at_ms: Number(c.expires_at_ms || 0),
          min_rating: Number(c.min_rating || 0),
          max_rating: Number(c.max_rating || 0),
        }));
        const openChallenges = parsed.filter((c) => c.status === CHALLENGE_STATUS_OPEN);

        // Check if any of our challenges were accepted
        await checkMyChallengesAccepted(openChallenges);

        setChallenges(openChallenges);
      }
    } catch (err) {
      console.error("[ChallengeList] Failed to fetch:", err);
    } finally {
      setIsLoading(false);
    }
  }, [sdk, checkMyChallengesAccepted]);

  useEffect(() => {
    fetchChallenges();
    const interval = setInterval(fetchChallenges, 5000);
    return () => clearInterval(interval);
  }, [fetchChallenges]);

  const handleAccept = async (challengeId: number) => {
    if (!sdk) return;

    setAcceptingId(challengeId);

    try {
      await sdk.haptic?.({ type: "impact", style: "light" });
      await sdk.sendTransaction({
        function: `${getChessModuleAddress(sdk.network)}::chess_lobby::accept_challenge`,
        type_arguments: [],
        arguments: [challengeId.toString()],
        title: "Accept Challenge",
        description: "Accept this chess challenge",
        useFeePayer: true,
        gasLimit: "Sponsored",
      });

      // Query the actual game_id from the accepted challenge
      const result = await sdk.view({
        function: `${getChessModuleAddress(sdk.network)}::chess_lobby::get_game_id_for_challenge`,
        type_arguments: [],
        function_arguments: [challengeId.toString()],
      });

      const gameId = Array.isArray(result) ? Number(result[0]) : Number(result);

      // Navigate to game page using the actual game_id
      router.push(`/game/${gameId}`);
    } catch (err) {
      console.error("[ChallengeList] Failed to accept:", err);
    } finally {
      setAcceptingId(null);
    }
  };

  const handleCancel = async (challengeId: number) => {
    if (!sdk) return;

    try {
      await sdk.haptic?.({ type: "impact", style: "light" });
      await sdk.sendTransaction({
        function: `${getChessModuleAddress(sdk.network)}::chess_lobby::cancel_challenge`,
        type_arguments: [],
        arguments: [challengeId.toString()],
        title: "Cancel Challenge",
        description: "Cancel your chess challenge",
        useFeePayer: true,
        gasLimit: "Sponsored",
      });

      await fetchChallenges();
    } catch (err) {
      console.error("[ChallengeList] Failed to cancel:", err);
    }
  };

  const formatTimeControl = (baseSeconds: number) => {
    if (baseSeconds >= 3600) {
      const hours = Math.floor(baseSeconds / 3600);
      return `${hours}h`;
    }
    const mins = Math.floor(baseSeconds / 60);
    return `${mins}m`;
  };

  const formatAddress = (addr: string) => {
    if (!addr || addr.length < 10) return addr;
    return `${addr.slice(0, 6)}...${addr.slice(-4)}`;
  };


  if (isLoading) {
    return (
      <div className="text-center py-8 text-gray-500 dark:text-gray-400 text-sm">
        Loading challenges...
      </div>
    );
  }

  if (challenges.length === 0) {
    return (
      <div className="text-center py-8">
        <div className="text-2xl mb-2">🎯</div>
        <p className="text-gray-500 dark:text-gray-400 text-sm">
          No open challenges yet.
          <br />
          Create one to get started!
        </p>
      </div>
    );
  }

  return (
    <div className="space-y-2">
      {challenges.map((challenge) => {
        const isOwn =
          currentAddress?.toLowerCase() === challenge.challenger.toLowerCase();
        const isAccepting = acceptingId === challenge.challenge_id;

        return (
          <div
            key={challenge.challenge_id}
            className={`flex items-center gap-3 p-3 rounded-lg border ${
              isOwn
                ? "bg-green-50 dark:bg-green-900/20 border-green-200 dark:border-green-800"
                : "bg-gray-50 dark:bg-gray-700/50 border-gray-200 dark:border-gray-600"
            }`}
          >
            {/* Time Control */}
            <div className="text-center min-w-[60px]">
              <div className="text-lg font-bold text-gray-900 dark:text-white">
                {formatTimeControl(challenge.time_control_base_seconds)}
              </div>
            </div>

            {/* Challenger Info */}
            <div className="flex-1 min-w-0">
              <div className="text-sm font-mono text-gray-700 dark:text-gray-300 truncate">
                {isOwn ? "Your challenge" : formatAddress(challenge.challenger)}
              </div>
            </div>

            {/* Action Button */}
            {isOwn ? (
              <Button
                onClick={() => handleCancel(challenge.challenge_id)}
                variant="outline"
                size="sm"
              >
                Cancel
              </Button>
            ) : (
              <Button
                onClick={() => handleAccept(challenge.challenge_id)}
                disabled={isAccepting}
                variant="default"
                color="green"
                size="sm"
              >
                {isAccepting ? "..." : "Play"}
              </Button>
            )}
          </div>
        );
      })}
    </div>
  );
}
