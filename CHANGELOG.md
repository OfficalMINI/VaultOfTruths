# Changelog

## 1.1.4
- Fix withdrawal trail tracking to split across multiple depositors (FIFO)
- Stacked guild bank items now properly attribute to each depositor

## 1.1.3
- Fix Distribute button not responding to clicks
- Fix guild chat incorrectly showing "craft" for raw PVP item sales
- Distribute button now force-marks as distributed if no deposits match
- Add crafter recipe export script (snapshots on commit)

## 1.1.2
- Include guild bank tab 5 (Finished Goods) in ledger tracking

## 1.1.1
- Fix withdrawals not tracked in ledger or notified
- Scanner now fires events and chat notifications for withdrawals

## 1.1.0
- Restyle all UI panels to custom theme — no default WoW chrome remaining
- Fix T:Button not responding to clicks (missing RegisterForClicks)
- Fix crafting item search causing massive lag (was scanning 67k item IDs)
- Fix "I Supply Mats" mode not showing fee confirmation
- Auto-size confirm dialog based on content
- Add CurseForge automatic packaging via BigWigs packager
- Add GitHub Actions release workflow (tag to release)

## 1.0.13
- Add CurseForge project ID for automatic upload
- Remove invalid dependency slug

## 1.0.12
- Add X-Curse-Project-ID to TOC

## 1.0.11
- Fix GitHub release permissions (contents: write)
- Exclude dev files from release package

## 1.0.10
- Add .pkgmeta, GitHub Actions workflow, CHANGELOG.md
- Use @project-version@ tokens for packager

## 1.0.9
- Add per-sale Distribute button on AH panel
- Fix Distribute button click handling

## 1.0.8
- Restyle Crafting tab with custom theme (no default WoW borders)
- Add T:Button and T:EditBox theme components
- Fix Officer Panel mat debts label overlapping column headers

## 1.0.7
- Fix misleading 'Pending' label on sold AH items (now 'Undistributed'/'Paid')

## 1.0.6
- Add mat debt management UI to Officer Panel

## 1.0.5
- Fix trail misattribution (raw deposits showing as 'Crafted by X')
- Fix operator precedence bug in wasCrafted check
- Remove PVPER role gate from contributor earnings
- All depositors now get proportional contributor share

## 1.0.4
- Fix deposits not recording in ledger
- Scanner now fires events for bag-diff detected deposits

## 1.0.0
- Initial release
- PVP guild economy management
- Contribution tracking, crafting orders, AH profit sharing
