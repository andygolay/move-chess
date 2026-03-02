# MOVE Chess

A peer-to-peer chess mini app for the Movement Apps mobile app. Play chess against other players with on-chain game state, time controls, and ELO ratings.

## Features

- Full chess rules implementation on-chain (castling, en passant, promotion, check/checkmate detection)
- Multiple time controls (1min, 3min+2s, 5min, 10min, 15min+10s, 30min)
- ELO rating system with leaderboard
- Challenge system for matchmaking
- Real-time game timer with blockchain-synced time

## Smart Contracts

Three Move modules handle all game logic:

### chess_game.move
Core chess engine with complete rules:
- Board representation and piece movement
- Legal move generation and validation
- Check, checkmate, and stalemate detection
- Draw conditions (50-move rule, threefold repetition, insufficient material)
- Time control and timeout handling

### chess_lobby.move
Matchmaking system:
- Create open challenges with time control preferences
- Accept challenges to start games
- Challenge expiration and cancellation

### chess_leaderboard.move
Player statistics and rankings:
- Player registration with initial rating
- ELO rating updates after games
- Top players leaderboard

## Project Structure

Frontend built with Next.js and the Movement MiniApp SDK:

```
├── constants.ts                  # Contract addresses and game constants
├── move/
│   └── sources/
│       ├── chess_game.move
│       ├── chess_lobby.move
│       └── chess_leaderboard.move
└── src/
    ├── app/
    │   ├── page.tsx              # Home/splash screen
    │   ├── lobby/page.tsx        # Challenge creation and listing
    │   ├── game/[gameId]/page.tsx # Active game board
    │   └── leaderboard/page.tsx  # Player rankings
    └── components/
        ├── chess/
        │   ├── ChessBoard.tsx    # Interactive board
        │   ├── ChessPieces.tsx   # SVG piece rendering
        │   ├── GameTimer.tsx     # Time control display
        │   ├── PromotionModal.tsx
        │   └── GameOverModal.tsx
        ├── lobby/
        │   ├── ChallengeList.tsx
        │   └── CreateChallengeModal.tsx
        └── navigation/
            └── BottomNav.tsx
```

## Getting Started

1. Install dependencies:
```bash
pnpm install
```

2. Deploy the Move contracts:
```bash
cd move
movement move compile
movement move publish
```

3. Set the contract address in `.env.local`:
```bash
NEXT_PUBLIC_CHESS_MODULE_ADDRESS_TESTNET=0x<your-address>
```

4. Run the development server:
```bash
pnpm dev
```

## Usage

This is a mini app designed to run inside the Movement Apps mobile app. To test:

1. Deploy to a public URL (e.g., Vercel)
2. Open the Movement Apps mobile app
3. Navigate to the mini app using your deployed URL

## Contract Deployment

The contracts are deployed to a single address. All modules use `init_module` for automatic initialization on publish:
```bash
movement move publish --named-addresses chess=<your-address>
```
