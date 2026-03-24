# Vault of Truths

A WoW addon for PVP-focused guilds that turns PVP rewards into a shared economy. Members deposit loot, crafters transform it, auctioneers sell it, and profits are split proportionally.

Built for **World of Warcraft: Midnight** (Interface 120001).

## How It Works

1. **PVPers** loot items from battlegrounds, arenas, and PVP boxes
2. **Deposit** loot into the guild bank (Tab 1)
3. **Crafters** withdraw materials, craft higher-value items, and deposit them back
4. **Auctioneers** list crafted and raw items on the AH from a dedicated account
5. **Profits are split** proportionally based on each member's contributions

Every step is tracked with an **item trail** — from deposit to craft to sale — so everyone gets their fair share.

## Features

### Guild Economy
- **Contribution tracking** — deposits valued via TSM pricing, proportional profit sharing
- **Two-layer profit split** — Layer 1: contribution share by deposit value, Layer 2: configurable % split (contributors/crafters/auctioneers/guild tax)
- **One-click mail payouts** — officers open mailbox, click through each payout
- **Mat debt tracking** — crafters' withdrawals are price-locked as debt, cleared when they deposit crafted items

### Crafting Orders
- **Guild crafting board** — browse crafters, search recipes, queue orders
- **Recipe scanning** — crafters' recipes are automatically detected and shared
- **NPC order detection** — auto-matches WoW crafting order completions to VoT orders
- **Commission system** — guild mats or requester mats, with configurable fees

### Auction House
- **Dedicated AH account flow** — sales detected from mail, profit calculated automatically
- **Per-sale distribution** — distribute individual sale profits or all at once
- **Profit return tracking** — tracks how much the AH account owes the guild bank

### Tracking & Trails
- **Item trails** — full lifecycle tracking: deposit → craft → list → sell
- **FIFO attribution** — stacked items correctly attribute to multiple depositors
- **Inactivity tracking** — configurable auto-demote thresholds
- **Progression system** — track-based ranks (PVPer/Crafter paths)

### UI
- **Custom themed UI** — clean, modern panels with no default WoW chrome
- **Dashboard** — personal stats, guild overview, recent activity
- **Ledger browser** — sortable, filterable contribution history
- **Officer panel** — role management, mat debts, sync status, payouts
- **What's New tab** — in-game changelog

### Sync & Community
- **Guild addon sync** — data shared between online members via addon channel
- **Community bridge** — non-guildies can browse crafters and request crafts
- **Crafter directory** — visible to all members and community connections

## Slash Commands

| Command | Description |
|---------|-------------|
| `/vot` | Open the main window |
| `/vot help` | List all commands |
| `/vot balance` | Show your balance |
| `/vot ledger` | Print recent ledger entries |
| `/vot status` | Show addon status |
| `/vot debug on/off` | Toggle debug mode |
| `/vot redist` | Officer: re-distribute all sale profits |
| `/vot repair` | Officer: rebuild trail links |
| `/vot scan` | Force guild bank scan |

## Installation

### CurseForge
Install from [CurseForge](https://www.curseforge.com/wow/addons/vault-of-truths) or via the CurseForge app.

### Manual
1. Download the latest release from [GitHub Releases](https://github.com/OfficalMINI/VaultOfTruths/releases)
2. Extract `VaultOfTruths` folder into `World of Warcraft/_retail_/Interface/AddOns/`
3. Restart WoW or `/reload`

## Dependencies

- **Required:** None
- **Optional:** [TradeSkillMaster](https://www.curseforge.com/wow/addons/tradeskill-master) — used for item pricing (highly recommended)

## Libraries

Bundled automatically:
- LibStub
- LibSerialize
- LibDeflate
- LibDataBroker-1.1
