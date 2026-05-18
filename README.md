# Glance — Landing Page

Landing page for [Glance](https://seven74ai.github.io/glance): share any screen with AI in real-time.

## Deploy

The landing page is a static site in `/docs`. GitHub Pages serves it from the `main` branch `/docs` folder.

### 1. Configure GitHub Pages

Go to https://github.com/Seven74AI/glance/settings/pages and set:
- **Source:** Deploy from a branch
- **Branch:** `main`
- **Folder:** `/docs`

### 2. Push

```bash
git add docs/ README.md
git commit -m "Landing page + waitlist for Glance"
git push origin main
```

### 3. Waitlist

The waitlist form uses [Formspree](https://formspree.io). Emails are collected at formspree.io/f/xldjdqlo. To change the endpoint:

1. Create a free Formspree account
2. Create a new form
3. Update the `action` attribute in `docs/index.html` (`<form action="https://formspree.io/f/YOUR_FORM_ID" ...>`)

### 4. Verify

After pushing, the site is live at:

- **https://seven74ai.github.io/glance**

GitHub Pages takes ~1 minute to deploy after the first push.

## Files

```
docs/
  index.html    — Landing page
  styles.css    — Styling (dark theme)
README.md       — This file
```

## Messaging

Three headline variants are displayed on the page for A/B testing:
1. "Share your screen with AI" (Primary)
2. "AI that sees what you see" (Alt A)
3. "Your AI pair programmer with full context" (Alt B)
