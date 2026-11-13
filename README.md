# Shadow Hunter — Guild Chat stage

## Added
- Private one-to-one chat with accepted friends.
- Friend selector populated from accepted friendships.
- Message history (latest 200 messages).
- Send messages up to 2,000 characters.
- Realtime incoming/outgoing message refresh through Supabase Realtime.
- Chat access is governed by the existing `accountability_messages` RLS policies.

## Deploy
1. Replace the files in your project/repository with these files.
2. Keep `index.html`, `config.js` and `accountability_setup.sql` in the same root folder.
3. The Accountability SQL must already have been run.
4. Commit and push to GitHub; Vercel will deploy the update automatically.

## Notes
This stage implements direct messages only. Study-room chat, reminders, presence and screen sharing are not included yet.
