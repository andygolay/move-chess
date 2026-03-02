"use client";

import { useState } from "react";
import { Button } from "@moveindustries/movement-design-system";
import { useMovementSDK } from "@movement-labs/miniapp-sdk";
import {
  getChessModuleAddress,
  TIME_CONTROLS,
  COLOR_RANDOM,
} from "../../../constants";

interface CreateChallengeModalProps {
  onClose: () => void;
}

export default function CreateChallengeModal({
  onClose,
}: CreateChallengeModalProps) {
  const { sdk } = useMovementSDK();
  const [selectedTimeControl, setSelectedTimeControl] = useState<{ label: string; base: number; increment: number }>(TIME_CONTROLS[1]); // 10 min default
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState("");

  const handleCreate = async () => {
    if (!sdk) return;

    setIsLoading(true);
    setError("");

    try {
      await sdk.haptic?.({ type: "impact", style: "light" });
      await sdk.sendTransaction({
        function: `${getChessModuleAddress(sdk.network)}::chess_lobby::create_open_challenge`,
        type_arguments: [],
        arguments: [
          selectedTimeControl.base.toString(),
          selectedTimeControl.increment.toString(),
          COLOR_RANDOM.toString(),
          "0", // No min rating
          "0", // No max rating
          "3600", // 1 hour expiry
        ],
        title: "Create Challenge",
        description: `Create ${selectedTimeControl.label} challenge`,
      });

      await sdk.notify?.({
        title: "Challenge Created",
        body: `${selectedTimeControl.label} challenge is now open`,
      });

      onClose();
    } catch (e) {
      const errorMessage =
        e instanceof Error ? e.message : "Failed to create challenge";
      setError(errorMessage);
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50">
      <div className="bg-white dark:bg-gray-800 rounded-xl p-5 shadow-xl mx-4 w-full max-w-sm">
        <h3 className="text-lg font-semibold text-gray-900 dark:text-white mb-4">
          Create Challenge
        </h3>

        {/* Error */}
        {error && (
          <div className="mb-4 p-2 bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 rounded text-xs text-red-600 dark:text-red-400">
            {error}
          </div>
        )}

        {/* Time Control */}
        <div className="mb-6">
          <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
            Game Length
          </label>
          <div className="grid grid-cols-2 gap-2">
            {TIME_CONTROLS.map((tc) => (
              <button
                key={tc.label}
                onClick={() => setSelectedTimeControl(tc)}
                className={`py-3 px-3 rounded-lg text-sm font-medium transition-colors ${
                  selectedTimeControl.label === tc.label
                    ? "bg-green-600 text-white"
                    : "bg-gray-100 dark:bg-gray-700 text-gray-700 dark:text-gray-300 hover:bg-gray-200 dark:hover:bg-gray-600"
                }`}
              >
                {tc.label}
              </button>
            ))}
          </div>
        </div>

        {/* Actions */}
        <div className="flex gap-2">
          <Button
            onClick={onClose}
            variant="outline"
            size="lg"
            className="flex-1"
          >
            Cancel
          </Button>
          <Button
            onClick={handleCreate}
            disabled={isLoading}
            variant="default"
            color="green"
            size="lg"
            className="flex-1"
          >
            {isLoading ? "Creating..." : "Create"}
          </Button>
        </div>
      </div>
    </div>
  );
}
