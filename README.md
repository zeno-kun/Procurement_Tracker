# BrightBots Procurement — frontend preview

Portable source for the Procurement interface, ready to open locally or push to your own GitHub repository.

## Open locally

Extract the ZIP and double-click **index.html** in Chrome or Edge. No Procurement account, npm installation, or database connection is needed.

For a local web server instead, install Node.js 18 or newer, open a terminal in this folder, and run:

```bash
npm start
```

Then open http://localhost:3000. The server binds to your own computer only. Stop it with Ctrl+C.

## Included screens

- Overview and ten stage inboxes.
- Multi-item requests and local draft saving.
- Request tracking, newest first, with item history.
- Request Approval, Quotation, Vendor Approval, PO, Fund Approval, Payment, Dispatch, QC, Invoice, and Accounting forms.
- Select All for Vendor and Fund Approval, plus item selection in other queues.
- Three-vendor quotation comparison.
- PO/GST calculations, payment balances and QC quantity validation.
- Catalog, document-filename preview and CSV export.
- Procurement-only review indicators.

“Source & readiness” is removed from the menu. No new Admin role or common employee dashboard is included.

## What is operational?

This is a **frontend preview**, not a live purchasing system. All DEMO records are illustrative. Preview actions update only browser-local storage. No live request, approval, payment, upload, email, Sheet update or Supabase write is performed.

File inputs retain filenames only; they do not upload file contents. Use **Reset sample** to reset illustrative requests. Browser-local changes do not synchronize between users or devices.

The existing Supabase database and original Google Sheet remain separate and unchanged by this package. This download contains no production records, passwords, API tokens or Supabase keys. Backend integration and live cutover are a later phase.

## Push to GitHub

Create an empty private repository on GitHub. From this extracted folder:

```bash
git init
git add .
git commit -m "Add Procurement frontend preview"
git branch -M main
git remote add origin https://github.com/YOUR-ACCOUNT/YOUR-REPOSITORY.git
git push -u origin main
```

Replace `YOUR-ACCOUNT/YOUR-REPOSITORY` with your actual repository path. If you already have a repository, copy these files into its checkout and commit normally instead of running `git init` again.

For GitHub Pages, set **Settings → Pages → Deploy from a branch → main → /(root)**, if your GitHub plan supports Pages for that repository. Pages has its own visibility rules: a private repository alone does not guarantee a private website. The frontend uses relative asset paths and works under a repository subpath. It can also be deployed as static files to Cloudflare Pages, with no build command and the project root as the output directory.

## Files

```text
index.html              Main entry point
assets/app.js           Preview workflow and UI
assets/workspace.css    Shared visual styles
assets/frontend.css     Procurement screen and form styles
assets/favicon.svg      App icon
server.mjs              Optional dependency-free localhost server
package.json            npm start / npm run check
INTEGRATION.md          Future operational integration checklist
```

Fonts load from Google Fonts when available; system fonts are used offline.
