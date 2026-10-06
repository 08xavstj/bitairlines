# Review, October 2026 (second pass): whole game and code

Four reviews: game core, app screens, balance, saves and project. What was fixed in rules version 6, and what is left.

## Fixed

Saves and iCloud
- Each game has its own id; iCloud files are named by game, not slot, so a new game on a second device or after a reinstall can
  no longer overwrite the main game. Copies are compared by game progress (the game clock), not by the time of day.
- An iCloud copy is read in full (and must be from this version or older) before it replaces anything; the old file is kept as
  `save-N.bak.json`. An upload never replaces a copy that is further along.
- Deleted games leave a marker in iCloud so other devices do not send them back. Delete asks first.
- A new airline never overwrites a save: with all slots full the game says so. A save that cannot be read is listed as such
  instead of disappearing, and failing to open one shows a message.
- The clock stops when the app goes to the background (and restarts on return); a paused game does not move on while away.
- iCloud sign-in later in the session is picked up; the background save asks iOS for time to finish the upload.
- Sandbox games stay off the leaderboards. Saves cope with a stray NaN number instead of failing every autosave.

Game core
- An old save could lose its crews for good if the player changed anything before pressing play: fixed.
- A weekly goal met on the last day now pays.
- Removing a longer runway or paving takes aircraft off routes they no longer fit (they used to wait forever).
- Reassigning an aircraft held at the gate re-times it at once.
- A shared aircraft's daily cost is split between its routes.
- A finished job hands the aircraft back cleanly; a grounded aircraft cannot be sold (its breakdown would linger).
- Purchases, permits and certificates go through one investment booking.

Screens
- Suggested routes are worked out once a game week, not every game day; the Hangar works out each type's fit once per update.
- Menu to Settings, Airline and Leave now open reliably. The loan slider stops at what can still be borrowed.
- Smaller fixes: "1 day left", "Cash change", route names on two lines, airline names limited to 22 plain characters,
  a refused special livery keeps the sheet open, logo drags just outside the canvas no longer paint the edge.

Balance
- No more buy-and-resell profits: a dealer never pays more than the airline paid. Rare low-hours finds at 80% of value,
  barn finds at 60%.
- Remote-town fare premium 1.1 to 0.9: the suggested long fly-in routes paid back in about a year, against a target of 2 to 4.
- Marketing costs a share of the last 30 days' revenue (1.5%, 5%, 15%) with small floors, so it is a choice at every size.
- Staff salaries halved; the revenue manager raises fares above 87% full instead of 85%.
- Weekly goals: 1.1 times last week instead of 1.2; bonus 8% of last week's revenue instead of 15%.
- Level 2 needs reputation 11 instead of 12 (flying alone adds about half a point a year per Caravan).
- New aircraft are crewed by spare pilots already on the payroll before anyone new is hired.

## Left to do (recommendations)
1. Rivals that respond: add flights on your best routes, fare wars, leave routes they lose. Levels 4 to 7 need an opponent.
2. Reputation that moves both ways (delays, breakdowns, slow decay), so it stays a live number late in the game.
3. The fare curve makes about 0.76 the best fare on any route that is not full; soften the gain from cutting fares.
4. Rare barn finds as restoration projects (time and cost before they fly) rather than cheap aircraft.
5. Heavy checks every few years with a real cost, so keeping an old aircraft is a decision.
6. Place-based weekly goals ("2 t to Kugluktuk") with a fixed bonus by level.
7. Hubs count connecting passengers more than once when routes overlap; count each pair once.
8. Job flights skip some departure checks (crew hours, frozen lakes in season).
9. Slots are cheap late in the game (60k base); consider 150k.
10. Save the world off the main thread, and keep a small summary file per slot for the title screen.
11. CI: pin the macOS image and simulator, skip the Core run for docs-only changes, and add a pre-push check.
