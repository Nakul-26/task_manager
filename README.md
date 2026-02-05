# task_manager
An Android applications to help manage daily tasks

## Project: Habit Tracker MVP

Build a **very simple, offline-first habit and task tracking app** using Flutter.  
The goal is to create a minimal, distraction-free tool for daily personal habit tracking.

---

## Target Platforms
- Android (primary)
- Windows Desktop (optional, same Flutter codebase)

---

## Core Goal (MVP)
Create an app where the user can:
- Add habits/tasks
- Mark them as done each day
- Automatically reset daily while keeping history

No advanced features in MVP.

---

## Features (MVP Only)

### 1. Today’s Habits Screen
- Display a list of all habits.
- Each habit has a checkbox to mark as completed or not.
- Show today’s date.
- Changes are saved automatically.

---

### 2. Add / Manage Habits
- Add a new habit with:
  - Name (string)
  - Importance flag (boolean)
- Delete habits.

(No descriptions, frequencies, or categories in MVP.)

---

### 3. Daily Reset Logic
- Each new day starts with all habits unchecked.
- Previous day completion data is stored and not modified.
- Reset happens automatically when the app is opened on a new date.

---

## Data Model

### Habit
- id (string)
- name (string)
- isImportant (bool)
- createdAt (DateTime)

### DailyLog
- date (YYYY-MM-DD)
- habitId (string)
- completed (bool)

---

## Storage
- Local-only storage (offline-first).
- Use Hive or simple key-value storage.
- No internet, no accounts, no cloud.

---

## Non-Goals (Explicitly Excluded)
- User authentication
- Cloud sync
- Reminders or notifications
- Timers
- Analytics dashboards
- Streaks or gamification
- Social features
- Complex UI animations

---

## UI Philosophy
- Extremely simple and minimal.
- One-tap interactions.
- Focus on speed: open → check → close.
- No clutter or unnecessary screens.

---

## Implementation Order
1. Flutter project setup
2. Home screen with static habit list
3. Add habit functionality
4. Local storage integration
5. Daily reset & history logic

---

## Long-Term Vision (Post-MVP)
- Streak tracking
- Habit statistics
- Reminders and timers
- Habit frequency settings
- Cloud backup (optional)



### To create apk:
- flutter clean
- flutter config --no-enable-windows-desktop
- flutter pub get
- flutter build apk