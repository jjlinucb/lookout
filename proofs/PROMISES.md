# Lookout's proved promises

Each promise is proved by the Lean kernel in [Lookout.lean](Lookout.lean).
Lean proves a model of the Swift code, so `./check.sh` also feeds the
model's answers to the real code (`LeanTieTests.swift`, 13,000+ cases) and
turns red if they ever differ.

1. **Curfew hours.** The curfew covers exactly the minutes you pass going
   forward around the clock from its start until you reach its end, across
   midnight included. The start minute is in and the end minute is out. A
   start equal to the end means no curfew.
2. **The curfew holds.** During curfew hours the screen is up, unless a
   working-late pass was taken at or before now and less than its length
   (30 minutes by default) ago. A pass never counts outside curfew hours, and
   a pass dated in the future never counts.
3. **The warning.** The "curfew soon" notice shows only before the curfew,
   never during it, and only when the curfew starts within the warning time.
4. **Page redirects.** A redirect for a site fires only on that site or a
   subdomain of it (www.linkedin.com), never on another name ending in the
   same letters (evillinkedin.com). A redirect for a page fires on that page
   and the pages under it (/feed, /feed/today), never on a longer name that
   starts the same way (/feedback).

5. **A pause always ends by itself.** Whatever buttons were pressed (the
   cover's Wrong flag, the menu's Pause 30 Minutes, in any order), once every
   pause pressed so far has run out, Lookout is checking again unless Turn
   Off was used. Pressing Pause 30 More Minutes starts a fresh 30 from then;
   it never adds on. A pause never turns Lookout off; only Turn Off does.

## Not proved

- The detector, the cover, the tab closing and website blocking.
- Reading "HH:mm" (a bad time reads as midnight) and time zones: the model
  counts minutes, and the tie-in test runs in UTC.
- Whether the redirect target opens; only which pages are matched.
