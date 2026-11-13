# Shadow Hunter — Friends integration (first working stage)

## Included
- Existing Shadow Hunter app, preserving habits, XP, goals and Pomodoro.
- Supabase-backed Hunter invite code.
- Send friend requests by invite code.
- View incoming requests and accept/decline.
- Display accepted friends.
- Realtime refresh for incoming requests and friendship changes.

## Before testing
1. Keep `index.html`, `config.js` and `accountability_setup.sql` together.
2. The Accountability SQL setup must already have been run in the same Supabase project.
3. Serve the folder with VS Code Live Server (do not open index.html with `file://`).
4. Log in with an existing account.

## Not integrated in this stage
Direct/room chat, reminders, room-code joining, live presence and WebRTC screen sharing are not yet connected. They will be added and tested in later stages.
