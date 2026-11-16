USMANIA STATIONERS & OPTICALS WEBSITE

Files:
- index.html: redesigned website + WhatsApp/call links + Supabase-backed admin login/editor
- supabase-setup.sql: database table and owner-only update policy

Contact links already configured:
- WhatsApp and call: +92 334 9898919 (WhatsApp URL uses 923349898919)
- Call only: +92 332 6965497
- No email contact option is included.

IMPORTANT ADMIN SETUP:
1. Create a Supabase project.
2. In Supabase Authentication > Users, create the one owner/admin user.
3. Copy that user's UUID.
4. Open supabase-setup.sql, replace YOUR_ADMIN_USER_UUID with the UUID, and run it in Supabase SQL Editor.
5. In index.html, replace YOUR_SUPABASE_PROJECT_URL and YOUR_SUPABASE_ANON_KEY with the Project URL and anon/public key from Supabase Project Settings > API.
6. Upload index.html to your hosting.

Security:
- The public website can read the published website content.
- Only the exact Supabase Auth user UUID entered in the SQL policy can update the content.
- Do not share the admin password.
- Never add the Supabase service_role key to frontend HTML.
- This first admin editor edits categories and products as JSON. A later version can add friendly individual Add/Edit/Delete forms and image upload storage.

The site can run without Supabase as a public demo, but admin saving will not work until setup is complete.
