# Mobile UI kit — Daily Cadence

The core product. Timeline-first, journal-like day logger for iOS/Android.

## Screens
1. **Timeline** — Daily view, stacked notes by time. Default landing.
2. **Note editor** — Create/edit note with type selector.
3. **Progress chart** — Line chart for a tracked metric (weight, sleep, etc).
4. **Calendar** — Month grid with colored dots for note types.
5. **Dashboard** — Customizable widget grid.

Switch screens using the tab bar + the in-screen navigation.
All screens are wrapped in a 390×844 iPhone-like frame.

## Files
- `index.html` — click-through prototype loading all the components
- `components.jsx` — shared primitives (Badge, Icon, NoteCard, etc)
- `Timeline.jsx`, `NoteEditor.jsx`, `ProgressChart.jsx`, `CalendarView.jsx`, `Dashboard.jsx`
