/-
Lookout's safety promises, proved by the Lean kernel.

Each promise below is a model of a Swift function in mac/Sources/LookoutCore,
written to read line for line like it. Lean proves things about the model, not
the Swift, so `lean --run Lookout.lean` does two jobs:

  1. checks every proof (a broken promise is a compile error), then
  2. prints test vectors from the model, which `check.sh` writes to
     mac/Tests/LookoutCoreTests/lean-vectors.txt. LeanTieTests.swift feeds the
     same inputs to the Swift code and fails if any answer differs.

The plain English promises live in PROMISES.md.
-/

/-! ## Curfew hours (`Curfew.isNight`) -/

/-- Minutes in a day. Curfew times are minutes after midnight, 0 to 1439. -/
def day : Nat := 1440

/-- Swift: `s < e ? (s <= t && t < e) : s > e ? (t >= s || t < e) : false` -/
def isNight (s e t : Nat) : Bool :=
  if s < e then decide (s ≤ t) && decide (t < e)
  else if e < s then decide (s ≤ t) || decide (t < e)
  else false

/-- Promise 1: the curfew covers exactly the minutes you pass going forward
around the clock from `start` until you reach `end`, midnight included. -/
theorem isNight_iff_clockwise (s e t : Nat) (hs : s < day) (he : e < day) (ht : t < day) :
    isNight s e t = true ↔ (t + day - s) % day < (e + day - s) % day := by
  unfold isNight day at *
  by_cases h1 : s < e <;> by_cases h2 : e < s <;> simp [h1, h2] <;> omega

/-- The start minute is in, the end minute is out. -/
theorem start_in_end_out (s e : Nat) (hne : s ≠ e) :
    isNight s e s = true ∧ isNight s e e = false := by
  unfold isNight
  by_cases h1 : s < e <;> by_cases h2 : e < s <;> simp [h1, h2] <;> omega

/-- 22:00 to 07:00 covers both sides of midnight. -/
example : isNight (22*60) (7*60) (23*60+59) = true ∧ isNight (22*60) (7*60) 0 = true ∧
    isNight (22*60) (7*60) (7*60) = false ∧ isNight (22*60) (7*60) (21*60+59) = false := by decide

/-! ## Curfew state and the working-late pass (`Curfew.state`) -/

inductive St | off | warn | night | pass
  deriving DecidableEq, Repr

structure Cfg where
  start : Nat
  stop : Nat
  warnMin : Nat
  passMin : Nat

/-- The minute of the day for a time in seconds (UTC, as the tie-in test uses). -/
def minuteOf (now : Int) : Nat := ((now / 60) % 1440).toNat

/-- Swift: `if let lastPass, date >= lastPass, date.timeIntervalSince(lastPass) < passMinutes * 60` -/
def passCounts (c : Cfg) (now : Int) : Option Int → Bool
  | some p => decide (p ≤ now) && decide (now - p < c.passMin * 60)
  | none => false

def state (c : Cfg) (now : Int) (lastPass : Option Int) : St :=
  if isNight c.start c.stop (minuteOf now) then
    if passCounts c now lastPass then .pass else .night
  else if isNight c.start c.stop (minuteOf (now + c.warnMin * 60)) then .warn
  else .off

/-- Promise 2: during curfew hours the screen is up, unless a pass was taken
at or before now and less than `passMinutes` ago. -/
theorem curfew_holds (c : Cfg) (now : Int) (lp : Option Int)
    (h : isNight c.start c.stop (minuteOf now) = true) :
    state c now lp = .night ∨
    (state c now lp = .pass ∧ ∃ p, lp = some p ∧ p ≤ now ∧ now < p + c.passMin * 60) := by
  unfold state; simp only [h]
  cases lp with
  | none => simp [passCounts]
  | some p =>
    by_cases hp : passCounts c now (some p) = true
    · simp only [hp]; right
      simp [passCounts] at hp
      exact ⟨by simp, p, rfl, hp.1, by omega⟩
    · simp [hp]

/-- A pass never lets anything through outside curfew hours, and outside
curfew hours the state is only `off` or `warn`. -/
theorem pass_only_at_night (c : Cfg) (now : Int) (lp : Option Int)
    (h : state c now lp = .pass) : isNight c.start c.stop (minuteOf now) = true := by
  unfold state at h
  by_cases hn : isNight c.start c.stop (minuteOf now) = true
  · exact hn
  · by_cases hw : isNight c.start c.stop (minuteOf (now + c.warnMin * 60)) = true <;> simp [hn, hw] at h

/-- Promise 3: the warning comes only before curfew, never during it, and
only when curfew starts within `warnMinutes`. -/
theorem warn_only_before (c : Cfg) (now : Int) (lp : Option Int)
    (h : state c now lp = .warn) :
    isNight c.start c.stop (minuteOf now) = false ∧
    isNight c.start c.stop (minuteOf (now + c.warnMin * 60)) = true := by
  unfold state at h
  by_cases hn : isNight c.start c.stop (minuteOf now) = true
  · by_cases hp : passCounts c now lp = true <;> simp [hn, hp] at h
  · simp only [hn] at h
    refine ⟨by simpa using hn, ?_⟩
    by_cases hw : isNight c.start c.stop (minuteOf (now + c.warnMin * 60)) = true
    · exact hw
    · simp [hw] at h

/-! ## Page redirects (`redirect(for:settings:)`) -/

/-- Swift: `host == site || host.hasSuffix("." + site)` -/
def hostMatches (site host : List Char) : Bool :=
  host == site || ('.' :: site).isSuffixOf host

/-- Swift: `u.path == path || u.path.hasPrefix(path + "/")` -/
def pathMatches (rule path : List Char) : Bool :=
  path == rule || (rule ++ ['/']).isPrefixOf path

/-- Promise 4: a redirect rule for a site fires only on that site or a
subdomain of it, never on a different name that ends in the same letters. -/
theorem host_is_site_or_subdomain (site host : List Char) (h : hostMatches site host = true) :
    host = site ∨ ∃ sub, host = sub ++ '.' :: site := by
  unfold hostMatches at h
  simp only [Bool.or_eq_true, beq_iff_eq] at h
  rcases h with h | h
  · exact .inl h
  · right
    obtain ⟨sub, hs⟩ := List.isSuffixOf_iff_suffix.mp h
    exact ⟨sub, hs.symm⟩

/-- ...and a rule for a page fires on that page and the pages under it, never
on a longer name that starts the same way (/feed is not /feedback). -/
theorem path_is_page_or_below (rule path : List Char) (h : pathMatches rule path = true) :
    path = rule ∨ ∃ rest, path = rule ++ '/' :: rest := by
  unfold pathMatches at h
  simp only [Bool.or_eq_true, beq_iff_eq] at h
  rcases h with h | h
  · exact .inl h
  · right
    obtain ⟨rest, hr⟩ := List.isPrefixOf_iff_prefix.mp h
    exact ⟨rest, by simpa using hr.symm⟩

example : hostMatches "linkedin.com".toList "evillinkedin.com".toList = false := by decide
example : pathMatches "/feed".toList "/feedback".toList = false := by decide

/-! ## Pauses (`GuardState`) -/

/-- What a button press does. `wrongFlag` is the cover's Wrong flag button
(`pause(at:)`, `pauseMinutes` long); `menu` is the menu bar's Pause 30 Minutes
(`pauseFromMenu(minutes:at:)`); `toggle` is Turn Off / Turn On. Times are seconds. -/
inductive Act | toggle | wrongFlag (t : Int) | menu (t m : Int)

structure GS where
  on : Bool
  pausedUntil : Int

/-- Swift: `on.toggle()`, `pausedUntil = now + pauseMinutes * 60`, `pausedUntil = now + minutes * 60` -/
def step (pauseMin : Int) (g : GS) : Act → GS
  | .toggle => { g with on := !g.on }
  | .wrongFlag t => { g with pausedUntil := t + pauseMin * 60 }
  | .menu t m => { g with pausedUntil := t + m * 60 }

/-- Swift: `on && now >= pausedUntil` -/
def shouldCheck (g : GS) (now : Int) : Bool := g.on && decide (g.pausedUntil ≤ now)

def run (pauseMin : Int) (g : GS) (acts : List Act) : GS := acts.foldl (step pauseMin) g

/-- When the pause a press starts runs out (a toggle starts none). -/
def pauseEnd (pauseMin : Int) : Act → Option Int
  | .toggle => none
  | .wrongFlag t => some (t + pauseMin * 60)
  | .menu t m => some (t + m * 60)

theorem pausedUntil_le (pm : Int) (acts : List Act) (g : GS) (T : Int) (hg : g.pausedUntil ≤ T)
    (ha : ∀ a ∈ acts, ∀ e, pauseEnd pm a = some e → e ≤ T) : (run pm g acts).pausedUntil ≤ T := by
  induction acts generalizing g with
  | nil => simpa [run] using hg
  | cons a as ih =>
    simp only [run, List.foldl_cons]
    apply ih
    · cases a with
      | toggle => simpa [step] using hg
      | wrongFlag t => exact ha _ (List.mem_cons_self ..) _ rfl
      | menu t m => exact ha _ (List.mem_cons_self ..) _ rfl
    · exact fun b hb => ha b (List.mem_cons_of_mem _ hb)

/-- Promise 5: a pause always ends by itself. Whatever buttons were pressed,
once every pause pressed so far has run out, Lookout is checking again,
unless Turn Off was used. -/
theorem pause_comes_back (pm : Int) (acts : List Act) (g : GS) (T now : Int)
    (hg : g.pausedUntil ≤ T) (ha : ∀ a ∈ acts, ∀ e, pauseEnd pm a = some e → e ≤ T) (hn : T ≤ now) :
    shouldCheck (run pm g acts) now = (run pm g acts).on := by
  have := pausedUntil_le pm acts g T hg ha
  simp [shouldCheck]; omega

/-- Pressing Pause 30 More Minutes starts a fresh 30 from now; it never adds
on to the pause already running. -/
theorem pause_restarts (pm : Int) (g : GS) (t m : Int) :
    (step pm g (.menu t m)).pausedUntil = t + m * 60 := rfl

/-- A pause never turns Lookout off: only Turn Off / Turn On changes that. -/
theorem pause_keeps_on (pm : Int) (acts : List Act) (g : GS)
    (h : ∀ a ∈ acts, a ≠ .toggle) : (run pm g acts).on = g.on := by
  induction acts generalizing g with
  | nil => rfl
  | cons a as ih =>
    have ha := h a (List.mem_cons_self ..)
    have := ih (step pm g a) (fun b hb => h b (List.mem_cons_of_mem _ hb))
    simp only [run, List.foldl_cons] at this ⊢
    rw [this]
    cases a <;> simp_all [step]

/-! ## Closing the tab (`shouldClose`) -/

inductive V | exposed | revealing
  deriving DecidableEq

/-- Scores are thousandths (0.65 is 650), as the tie-in test sends them.
Swift: `hits.map(\.score).max() ?? 0` -/
def maxScore (scores : List Nat) : Nat := scores.foldl max 0

/-- Swift: `guard closeTab else { return false }; if verdict == .exposed { return true };
return maxScore >= closeRevealingAt` -/
def shouldClose (closeTab : Bool) (closeAt : Nat) (v : V) (scores : List Nat) : Bool :=
  if !closeTab then false
  else if v = .exposed then true
  else decide (closeAt ≤ maxScore scores)

theorem le_foldl_max (a acc : Nat) (l : List Nat) :
    a ≤ l.foldl max acc ↔ a ≤ acc ∨ ∃ s ∈ l, a ≤ s := by
  induction l generalizing acc with
  | nil => simp
  | cons x xs ih =>
    rw [List.foldl_cons, ih]
    have hm : a ≤ max acc x ↔ a ≤ acc ∨ a ≤ x := by rw [Nat.max_def]; split <;> omega
    simp only [List.mem_cons, exists_eq_or_imp, hm, or_assoc]

/-- Promise 6: with closing turned off, a tab is never closed. -/
theorem close_off_never (closeAt : Nat) (v : V) (scores : List Nat) :
    shouldClose false closeAt v scores = false := rfl

/-- ...with it on, explicit nudity always closes the tab... -/
theorem exposed_closes (closeAt : Nat) (scores : List Nat) :
    shouldClose true closeAt .exposed scores = true := rfl

/-- ...and a revealing image closes it only when some part of it scored at
or above `closeRevealingAt`; below that it is only covered. -/
theorem revealing_closes_iff (closeAt : Nat) (scores : List Nat) (h : 0 < closeAt) :
    shouldClose true closeAt .revealing scores = true ↔ ∃ s ∈ scores, closeAt ≤ s := by
  simp only [shouldClose, maxScore]
  simp [le_foldl_max]; omega

/-! ## Test vectors for the Swift tie-in -/

def minutes : List Nat := [0, 1, 59, 60, 419, 420, 421, 719, 720, 1259, 1260, 1319, 1320, 1321, 1380, 1438, 1439]

def nightLines : List String := Id.run do
  let mut out := []
  for s in minutes do
    for e in minutes do
      for t in minutes ++ [30, 300, 600, 1000, 1350] do
        out := s!"night {s} {e} {t} {isNight s e t}" :: out
  return out.reverse

def stName : St → String
  | .off => "off" | .warn => "warn" | .night => "night" | .pass => "pass"

def stateLines : List String := Id.run do
  let cfgs : List Cfg := [⟨1320, 420, 15, 30⟩, ⟨540, 1020, 10, 5⟩, ⟨0, 1439, 0, 60⟩, ⟨600, 600, 15, 30⟩]
  let nows : List Int := [0, 59, 60, 25140, 25199, 25200, 78300, 78359, 78360, 79199, 79200, 79260, 81000, 82800, 84540, 86399, 86400, 172799]
  let gaps : List (Option Int) := [none, some 0, some 1, some 1799, some 1800, some 1801, some 299, some 300, some (-1), some (-600), some 3600]
  let mut out := []
  for c in cfgs do
    for n in nows do
      for g in gaps do
        let lp := g.map (n - ·)
        let lpS := match lp with | some p => toString p | none => "-"
        out := s!"state {c.start} {c.stop} {c.warnMin} {c.passMin} {n} {lpS} {stName (state c n lp)}" :: out
  return out.reverse

def sites : List String := ["linkedin.com", "linkedin.com/feed", "x.com/home"]
def hosts : List String := ["linkedin.com", "www.linkedin.com", "evillinkedin.com", "linkedin.com.evil.net", "x.com", "box.com", "a.b.x.com"]
def paths : List String := ["", "/", "/feed", "/feed/", "/feed/today", "/feedback", "/home", "/homes", "/home/x", "/messaging/"]

def redirectLines : List String := Id.run do
  let mut out := []
  for r in sites do
    let parts := r.splitOn "/"
    let site := parts.headD ""
    let rest := "/".intercalate parts.tail
    for h in hosts do
      for p in paths do
        let hit := hostMatches site.toList h.toList &&
          (parts.length == 1 || pathMatches ("/" ++ rest).toList p.toList)
        out := s!"redirect {r} {h} {if p.isEmpty then "-" else p} {hit}" :: out
  return out.reverse

def actName : Act → String
  | .toggle => "T" | .wrongFlag t => s!"W{t}" | .menu t m => s!"M{t}x{m}"

def guardLines : List String := Id.run do
  let acts : List Act := [.toggle, .wrongFlag 0, .wrongFlag 600, .menu 300 30, .menu 1500 30, .menu 100 10]
  let seqs := [[]] ++ acts.map ([·]) ++ (acts.flatMap fun a => acts.map ([a, ·])) ++
    (acts.flatMap fun a => acts.flatMap fun b => acts.map ([a, b, ·]))
  let nows : List Int := [0, 299, 300, 1799, 1800, 2099, 2100, 3299, 3300, 3301, 3600]
  let mut out := []
  for pm in [5, 30] do
    for sq in seqs do
      let g := run pm ⟨true, 0⟩ sq
      let sqS := if sq.isEmpty then "-" else ",".intercalate (sq.map actName)
      for n in nows do
        out := s!"guard {pm} {sqS} {n} {shouldCheck g n}" :: out
  return out.reverse

def closeLines : List String := Id.run do
  let ats : List Nat := [0, 1, 500, 649, 650, 651, 1000]
  let lists : List (List Nat) := [[], [0], [649], [650], [651], [1000], [100, 649], [649, 650], [700, 10], [300, 400, 500]]
  let mut out := []
  for ct in [true, false] do
    for a in ats do
      for v in [V.exposed, V.revealing] do
        for l in lists do
          let lS := if l.isEmpty then "-" else ",".intercalate (l.map toString)
          let vS := if v = .exposed then "exposed" else "revealing"
          out := s!"close {ct} {a} {vS} {lS} {shouldClose ct a v l}" :: out
  return out.reverse

def main : IO Unit := do
  for l in nightLines ++ stateLines ++ redirectLines ++ guardLines ++ closeLines do IO.println l
