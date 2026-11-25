# South Sudan Economic Inclusion Platform

A responsive web app starter with Supabase authentication, role-based profiles, jobs, applications, training, business directory, funding opportunities, resources and enquiries.

## 1. Open in VS Code
Open this folder in VS Code. The project files are `index.html`, `style.css`, `app.js` and `supabase.sql`.

## 2. Create and configure Supabase
1. Create a project at https://supabase.com/.
2. Open **SQL Editor** in your Supabase dashboard.
3. Paste and run all of `supabase.sql`.
4. Open **Project Settings → API** (or API Keys) and copy the Project URL and public anon/publishable key.
5. In `app.js`, replace `YOUR_SUPABASE_PROJECT_URL` and `YOUR_SUPABASE_ANON_OR_PUBLISHABLE_KEY` with those two values.
6. In Supabase Authentication settings, configure the Site URL and allowed redirect URLs for your local development URL and eventual deployed domain. For local testing with VS Code Live Server, add the local origin shown by Live Server.
7. Start the site using VS Code Live Server.

Never put the `service_role` or secret key in `app.js`, HTML, GitHub, or any browser code. The public anon/publishable key is intended for browser use when Row Level Security is enabled.

## 3. Roles
Users can register as job seeker, employer, entrepreneur or training provider. New accounts cannot select administrator. To make your own account an administrator, find its UUID under Authentication → Users and run this in SQL Editor:

```sql
update public.profiles set role = 'admin' where id = 'YOUR_AUTH_USER_UUID';
```

The platform has approval status columns. For this initial version, posts created by authorised roles are inserted as `published` for immediate testing. Before a public launch, change the insert defaults in `app.js` to `pending`, then build admin review/approval screens and corresponding policies.

## 4. Current working features
- Sign up, log in and log out through Supabase Auth.
- Separate account roles and profile editing.
- Employers can create job listings; job seekers can apply and see their applications.
- Training providers can publish courses; users can enrol and track enrolments.
- Entrepreneurs can publish business profiles.
- Admins can publish funding and resource listings.
- Visitors can submit contact enquiries.
- Row Level Security policies restrict database access by user and role.

## 5. Important limitations before launch
This is a functional starter, not a fully audited production service. It does not yet include email notifications, password reset UI, employer candidate-review UI, document upload UI, full admin moderation UI, rate limiting/anti-spam, analytics, or legal verification of South Sudan-specific content. Do not collect sensitive identity documents until you have a documented privacy policy, consent process, retention rules and secure review procedures. Verify employers and opportunities before promoting them. Have the database policies and application reviewed before handling real users' data.
