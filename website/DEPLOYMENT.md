# Saytile official site — GitHub Pages deployment

- Canonical product site: `https://saytile.com/` (root domain, not `www`).
- Source of truth: `main/website/`, previously approved as R3. Do not replace the page with a simplified reconstruction.
- Publish via `.github/workflows/pages.yml` using GitHub Actions, upload the **contents** of `website/` as the Pages root. No Vercel, Node build, CDN, or external fonts are required.
- Verify the six original runtime files before every deploy using `website/SHA256SUMS.txt`. Preserved screenshots and design approvals are in `website/reference/` and `website/APPROVAL.md`.
- GitHub Pages repository site configured through the Pages REST API with `build_type=workflow` and `cname=saytile.com` on 2026-11-13.

## DNS (DNSPod is currently authoritative)

At DNSPod for `saytile.com`, add **four separate A records** on host `@`:

```text
@  A  185.199.108.153
@  A  185.199.109.153
@  A  185.199.110.153
@  A  185.199.111.153
www  CNAME  haohongfei2001-png.github.io
```

Use the default DNS line, TTL 600 or provider default. Remove conflicting default parking or old web-only A/AAAA/CNAME records, **not** MX, TXT, SPF, DKIM or other mail verification records. Do not create wildcard DNS records.

Optional IPv6 records at `@` are `2606:50c0:8000::153`, `2606:50c0:8001::153`, `2606:50c0:8002::153`, `2606:50c0:8003::153`.

After public DNS matches the above and GitHub finishes issuing the certificate, enable `Enforce HTTPS` under [Settings → Pages](https://github.com/haohongfei2001-png/saytile/settings/pages) (or via the Pages API).

GitHub Pages custom domains set with the GitHub Actions publishing source are configured in repository Pages settings / API; a `CNAME` file in `website/` is not the authoritative setting and is not needed.

## Verification

Check all of `https://saytile.com/`, `https://www.saytile.com/` (redirect to apex), and the actual CSS, JS and WebP assets. Confirm that responsive layout, hero demo, revisions, journal interactions, and reduced-motion behavior match the approved design. GitHub Actions checks content hashes, not browser visual equivalence.

Reference: https://docs.github.com/en/pages/configuring-a-custom-domain-for-your-github-pages-site/managing-a-custom-domain-for-your-github-pages-site
