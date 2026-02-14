# Habit Tracker

Offline-first Flutter app for tracking habits with reminders, progress, and history.

## Platforms
- Android (primary)
- iOS
- Web
- Windows
- macOS
- Linux

## Current Features

### Today Screen
- Shows active habits for the current date (filters by start date and frequency).
- Supports two habit types:
  - `binary`: complete/incomplete checkbox
  - `counted`: increment/decrement progress toward `timesPerDay`
- Displays per-habit:
  - name and description
  - color indicator
  - importance marker/score ordering
  - current streak
  - success rate
- Optional per-habit timer with start/pause/reset dialog.

### Habit Details
- Tap a habit on Today screen to open details.
- Shows:
  - success rate
  - start date
  - completed/missed days
  - current streak and longest streak
  - calendar view with completed days highlighted

### Add / Edit Habit
- Create and update habits with:
  - name
  - description
  - importance score (0-5)
  - type (`binary` or `counted`)
  - `timesPerDay` for counted habits
  - frequency (`daily`, `weekly`, `oddDays`, `evenDays`)
  - weekly day selection when frequency is weekly
  - start date
  - reminder on/off + time
  - optional timer minutes
  - color

### Manage Habits
- Reorder active habits (drag-and-drop).
- Edit, archive, and delete habits.
- Archived habits are hidden from Today screen.

### Archived Habits Screen
- View archived habits.
- Unarchive, edit, or delete archived habits.

### Reminders (Local Notifications)
- Timezone-aware local notifications via `flutter_local_notifications` + `timezone`.
- Supports scheduling for:
  - daily habits
  - weekly habits on selected weekdays
  - odd-day / even-day habits
- Reminders are synced on app startup and whenever a habit is changed.

### Data & Persistence
- Local-only storage using Hive boxes:
  - `habits`
  - `dailyLogs`
- No account/auth required.
- No cloud sync.

## Data Model

### Habit
- `id` (String)
- `name` (String)
- `description` (String)
- `isImportant` (bool)
- `importanceScore` (int)
- `type` (`binary` or `counted`)
- `frequency` (`daily`, `weekly`, `oddDays`, `evenDays`)
- `daysOfWeek` (List<int>?)
- `timesPerDay` (int?)
- `reminderEnabled` (bool)
- `reminderHour` / `reminderMinute` (int?)
- `timerMinutes` (int?)
- `color` (Color)
- `startDate` (DateTime)
- `createdAt` (DateTime)
- `isArchived` (bool)
- `archivedAt` (DateTime?)
- `sortOrder` (int)

### DailyLog
- `date` (`YYYY-MM-DD`)
- `habitId` (String)
- `completed` (bool)
- `count` (int?) for counted habits

## Notes
- History is available from the Today screen app bar (history icon) and groups logs by date.

## Run
```bash
flutter pub get
flutter run
```

## Build APK
```bash
flutter clean
flutter pub get
flutter build apk
```
