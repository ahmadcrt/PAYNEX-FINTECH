# PAYNEX FINTECH

Digital banking and payments **demo** platform. Designed & Developed by Ahmad.

> **Portfolio project only.** No real banking, deposits, withdrawals, transfers, or card issuance. All balances and transactions are fictional and labelled DEMO. PAYNEX is not a bank or licensed payment provider. Never enter real banking credentials.

## Features

Home (hero, services, security, how it works, FAQ) · Register / login / forgot password with validation · Dashboard (balance, income, expenses, spending overview, recent activity) · Transfers (form → confirmation → status → printable receipt) · Payments (airtime and bills, history, receipts) · Virtual card with freeze/unfreeze (a frozen card declines payments) · Savings goals with progress and history · Transaction history with search and date/type/status filters · Profile, password, notification and security settings · Admin dashboard (stats, suspend users, flag transactions, activity log, reset).

## Run it

`index.html` is a single self-contained file that talks to Supabase through `supabase-js` (loaded from a CDN). Serve it over http, e.g. `npx serve .`, or deploy with GitHub Pages. Opening it from `file://` may block auth.

Configuration lives at the top of the script (`sb=supabase.createClient(URL, ANON_KEY)`). Use your project's URL and **publishable/anon key only**.

## Supabase setup (production-style backend)

1. Create a project at supabase.com.
2. SQL Editor → paste and run `schema.sql`. It creates tables, a signup trigger (profile, demo card, $5,000 demo credit), **Row Level Security**, and server-side functions `demo_transfer`, `demo_pay`, `demo_save`.
3. Authentication → Providers → enable Email.
4. After registering, promote yourself to admin in the SQL Editor:
   `update public.profiles set role = 'admin' where email = 'you@example.com';`
5. Copy **Project URL** and **anon public key** (Settings → API) into your frontend config:

```
SUPABASE_URL=https://YOUR-PROJECT.supabase.co
SUPABASE_ANON_KEY=your-anon-key
```

**Never put the `service_role` key in frontend code or commit it.** The anon key is safe in the browser only because RLS is enabled on every table.

4b. Run `schema_v2.sql` after `schema.sql` (column-level permissions, logged admin actions), then deploy the matching `index.html`.

### Security model

- Users can read only their own profiles, transactions, and goals; admins can read all.
- Clients cannot insert transactions directly. Money moves only through `security definer` functions that validate amounts, balance, ownership, and frozen-card state.
- A trigger blocks non-admins from changing their `role`, `status`, email, or account number.

## Testing checklist

Register → login → transfer to `amina@paynex.demo` (confirm, receipt prints) → pay airtime → freeze card and confirm payment is declined → create and fund a goal → filter history → edit profile and password → admin suspend/flag → mobile width (360px) → no console errors.

## Status

Frontend is wired to Supabase: Auth, RLS-protected tables, and RPC functions for transfers, payments and savings. In Supabase, set **Authentication → URL Configuration → Site URL** to your deployed URL so password-reset emails work, and turn off "Confirm email" if you want instant sign-up while testing.

© 2026 PAYNEX FINTECH · Designed & Developed by Ahmad
