# Take A Tar Heel

A student ride-share site for UNC: older students with cars drive younger students without them, for a few dollars a seat. Built for a BUSI 200 recitation project at Kenan-Flagler.

Students sign in with their UNC email (an emailed link, no password), then:

- **Join a ride** or **Create a ride**, including an optional ride back
- save their class schedule and see rides that fit it
- build a profile with a photo and bio
- rate each other after a confirmed ride
- answer the survey, whose totals everyone can see

Organizers get a tab with everyone's schedules, suggested matches, survey comments and CSV exports.

The site is plain HTML and JavaScript (`index.html`). Data, sign-in and photos live in [Supabase](https://supabase.com). It is hosted on [Netlify](https://netlify.com). Both are free at this size.

## Files

| File | What it is |
|---|---|
| `index.html` | The whole site |
| `config.js` | Your Supabase project address and public key (fill these in) |
| `supabase/schema.sql` | Database tables, privacy rules, UNC-only sign-up and photo storage |
| `vendor/supabase.min.js` | Supabase's browser library, version 2.117.3 |
| `netlify.toml` | Netlify settings (no build step) |
| `archive/` | Earlier prototypes, kept for reference |

## Setup

### 1. Create the Supabase project (about 10 minutes)

1. Sign up at [supabase.com](https://supabase.com) and click **New project**. Name it `take-a-tarheel`, pick a database password (save it somewhere) and the **East US** region.
2. When the project is ready, open **SQL Editor → New query**. Paste in all of `supabase/schema.sql` and click **Run**. You should see "Success. No rows returned."
3. Make yourself an organizer. In a new query, run the following with your own UNC email, adding a line for each teammate who should see the Organizer tab:
   ```sql
   insert into public.organizers (email) values ('your-onyen@unc.edu') on conflict do nothing;
   ```
4. Open **Project Settings → API Keys** and copy:
   - the **Project URL** (looks like `https://abcdefgh.supabase.co`, also shown under Project Settings → Data API)
   - the **anon public** key (under *Legacy API keys*) or the **publishable** key (starts with `sb_publishable_`)

   Paste both into `config.js`. **Never** use the `service_role` or `secret` key; it bypasses every privacy rule.

### 2. Put the site online with Netlify (about 5 minutes)

1. Sign up at [netlify.com](https://netlify.com) with your GitHub account.
2. Click **Add new project → Import an existing project → GitHub**, then pick this repository.
3. Leave the build settings empty (Netlify reads `netlify.toml`) and click **Deploy**.
4. Your site is live at an address like `https://take-a-tarheel.netlify.app`. To change the name, go to **Project configuration → Change project name**.

Every time a change is pushed to GitHub, Netlify publishes it again automatically.

### 3. Tell Supabase where the site lives

In Supabase, open **Authentication → URL Configuration**:

- **Site URL**: your Netlify address, for example `https://take-a-tarheel.netlify.app`
- **Redirect URLs**: add the same address followed by `/**`

Without this step, the sign-in emails link back to the wrong place.

### 4. Sign-in emails

Supabase's built-in email service only sends a few sign-in emails per hour for the whole site. Past that, people see "Too many sign-in emails were sent just now." To lift the limit, send the emails through a Gmail account (up to about 500 a day, and no domain needed):

1. Turn on 2-step verification for the Google account, then create an app password at [myaccount.google.com/apppasswords](https://myaccount.google.com/apppasswords). Name it "Take A Tar Heel" and copy the 16-character password.
2. In Supabase, open **Authentication → Emails → SMTP Settings** and turn on **Enable custom SMTP**:
   - Sender email: the Gmail address
   - Sender name: `Take A Tar Heel`
   - Host: `smtp.gmail.com`
   - Port: `465`
   - Username: the Gmail address
   - Password: the app password
3. Click **Save**, then open **Authentication → Rate Limits** and raise **Rate limit for sending emails** (for example, to 100 per hour).
4. **Put the sign-in code in the emails** (required). UNC's Microsoft email scans links before students click them, which uses up one-time sign-in links. The site therefore asks for the code from the email instead. In **Authentication → Emails → Templates**, edit both **Confirm signup** and **Magic link** so the body includes `{{ .Token }}`, for example:
   ```html
   <h2>Your Take A Tar Heel sign-in code</h2>
   <p style="font-size:28px;letter-spacing:4px"><strong>{{ .Token }}</strong></p>
   <p>Type this code on the site to sign in. It expires in one hour.</p>
   <p>If you didn't ask for this, you can ignore this email.</p>
   ```

People only sign in once per device; the site keeps them signed in afterward. UNC mail sometimes files new senders under Junk, so tell testers to check there.

If you later buy a domain (for example takeatarheel.com), a service like Resend or Brevo can send from that domain instead.

## Who can see what

| Data | Who can read it | Who can change it |
|---|---|---|
| Rides, seat requests, waitlist, ratings, profiles | Any signed-in UNC student | The person it belongs to (drivers accept or decline requests on their own rides) |
| Schedules (including email) | The student and organizers | The student |
| Survey answers | The student and organizers; everyone sees the anonymous totals | The student |
| Survey comments | The student and organizers | The student |
| Profile photos | Anyone with the photo's link | The student |

- Only UNC addresses (ending in `unc.edu`) can create an account. To let someone else in for testing, run `insert into public.allowed_emails (email) values ('name@gmail.com');`.
- Ratings can only be left by someone who shared a confirmed ride with the person they're rating.

## Changing the site

Edit `index.html`, commit and push to GitHub. Netlify updates the live site within a minute. To try it on your own computer, run `python3 -m http.server` in this folder and open `http://localhost:8000`.

Not affiliated with UNC, UNC Transportation and Parking or Chapel Hill Transit.
