---
description: How to drive the Wallabag preview environment for verification.
---

# Wallabag verify skill

Wallabag is a self-hosted "read it later" / bookmarking app. The preview serves
the full web UI at the preview URL. Everything past the login screen requires
authentication.

## Logging in

The app gates all content behind a login form at `/login` — you'll be
redirected there on first navigation. Before anything else:

1. Navigate to the preview URL.
2. Fill the username field with `{{ secrets.wallabag_admin_email }}`.
3. Fill the password field with `{{ secrets.wallabag_admin_password }}`.
4. Click the "Log in" button.

After login you land on the article list (the unread "entries" view).

## Getting around

- The main view is a list of saved articles ("entries"), rendered as cards.
- The top toolbar has the page title, a search control, and view-mode toggles
  (list vs. grid).
- Each card links to a reader view and carries per-entry actions (archive,
  star, delete) plus any tags.
- Useful routes: `/` or `/unread/list` (unread), `/starred/list`,
  `/archive/list`, `/config` (settings).

## What's observable here

This is a real running app driven through the browser, so UI state, computed
styles, DOM structure, and console output are all fair game for evidence.
Background jobs and outbound email/integrations are not exercised in the
preview, so don't try to verify anything that depends on them.
