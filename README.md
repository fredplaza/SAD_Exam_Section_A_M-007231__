# Scholarship Monitoring & Academic Compliance System

Stack: HTML/CSS/vanilla JS, Supabase (Postgres + Auth + RLS), `@supabase/supabase-js@2.45.4` via CDN. Synthetic data only.

## Setup
1. Create a Supabase project. Authentication → disable "Confirm email" (for the exam).
2. SQL Editor → paste and run `schema.sql` (tables, RLS, RPC functions, 2 policies, seeds A01–A06).
3. Open `index.html`, set `SUPABASE_URL` and `SUPABASE_ANON_KEY` (anon key only; never the service-role key). No env file needed; for a build setup use `SUPABASE_URL`, `SUPABASE_ANON_KEY`.
4. Create accounts through the app's Sign up form. New signups are scholars by default:
   - First admin: sign up with Student ID `ADMIN1`, then in SQL Editor run `update profiles set role='admin' where student_id='ADMIN1';` Sign out and back in. Admins can change other account roles in the dashboard.
   - Staff: sign up with Student ID `STAFF1`, then promote in SQL with `update profiles set role='staff' where student_id='STAFF1';` (or let an admin change the role).
   - Scholar 1: Student ID `A01`; Scholar 2: Student ID `A02` (links to seeded records).
   - Supply passwords privately to the instructor.
5. Run: `python -m http.server 8000` in this folder → http://localhost:8000.

## Design notes
- Clients have **read-only** table access (RLS). All writes go through `security definer` functions that check role and rules: `submit_grades`, `verify_submission`, `evaluate_submission`, `decide_renewal`, `register_scholar`.
- Thresholds/deadline are read from the `programs` table, not code.
- Submission status, compliance result and renewal decision are separate columns.
- Deadlines compare `timestamptz` (seed uses +08:00); display in Asia/Manila.

## Expected results for seeds (derived from policy)
| ID | Expected compliance | Reasons |
|---|---|---|
| A01 | Compliant | — (exact GWA and deadline) |
| A02 | With Deficiency | GWA 1.76 exceeds 1.75 |
| A03 | Compliant | 1 drop allowed for Community |
| A04 | With Deficiency | Units 14 < 15; INC 1 > 0 |
| A05 | With Deficiency | Failed 1 > 0; late submission |
| A06 | Blocked | Pending verification |

## Test results (fill in after running; I have not executed these against a live Supabase project)
| Test | Input/action | Expected | Actual | Pass/Fail | Evidence |
|---|---|---|---|---|---|
| TC01 | Evaluate A01 | Compliant | | | |
| TC02 | Evaluate A02 | With Deficiency, GWA reason | | | |
| TC03 | Evaluate A03 | Compliant | | | |
| TC04 | Evaluate A04 | Units + incomplete reasons | | | |
| TC05 | Evaluate A05 | Failed + late reasons | | | |
| TC06 | Evaluate / approve A06 | Both blocked ("must be Verified…") | | | |
| TC07 | Duplicate semester; GWA 0.50; units/failed −1 | Rejected with clear message | | | |
| TC08 | As scholar A01 query A02 row; call `verify_submission` | 0 rows; "Staff only" | | | |
| TC09 | Return A06 (reason), sign in as A06's account, resubmit, refresh | Pending, history shows Returned→Resubmitted | | | |
| TC10 | Staff approve A01, try approve A02, hold A02; scholar RPC `decide_renewal` | Approve OK; A02 approve refused; hold OK; scholar denied | | | |

Quick TC08 check in browser console while signed in as a scholar:
`await sb.from('submissions').select('*')` (only own row) and `await sb.rpc('verify_submission',{p_id:'<uuid>',p_status:'Verified',p_reason:null})` (error: Staff only).

## Known limitations
- Policy thresholds are edited via the `programs` table, not the UI. Only AY 2026-2027 is offered in the form. The staff dashboard counts all assigned scholars (not only those with a submission in the chosen semester). Untested against a live project until you run the checks above.
- For an existing database created with the former two-role schema, run `migration_admin_role.sql` in Supabase SQL Editor before using admin accounts.
