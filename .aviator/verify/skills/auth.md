# Signing in

The app gates all content behind a login form at `/login` — you're redirected
there on first navigation. To sign in:

1. Navigate to the preview URL.
2. Fill the username field with `{{ secrets.wallabag_admin_email }}`.
3. Fill the password field with `{{ secrets.wallabag_admin_password }}`.
4. Click the "Log in" button.

After login you land on the article list (the unread "entries" view). Carry the
`{{ secrets.* }}` placeholders into the sign-in step verbatim — the collector
substitutes the real values at run time. Never put a literal secret in a scenario.
