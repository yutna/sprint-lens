# Fonts

Two families, both under the SIL Open Font License 1.1, both carrying Thai
and Latin so a heading and a paragraph beside each other are the same design
rather than two faces that happen to be nearby.

| Family | Role | Weights | Designer |
| --- | --- | --- | --- |
| IBM Plex Sans Thai | text | 400, 600 | Mike Abbink, Bold Monday |
| Mitr | display | 500, 600 | Cadson Demak |

Mitr is why the interface has a display voice in Thai at all. Thai faces that
are warm in form and still carry a weight range are scarce; without one, the
personality would have had to come from the Latin face alone while the Thai
stayed neutral — a worse outcome for an interface that is Thai first.

The licences are `OFL-IBMPlexSansThai.txt` and `OFL-Mitr.txt`, beside the
files, which is what the licence asks for. They are not incidental: shipping
the fonts without them would be a breach.

## Regenerating

The files are the Google Fonts builds, split by `unicode-range` so a Thai page
fetches the Thai subsets and nothing else. Nothing fetches them at runtime —
`AGENTS.md` forbids the layouts referencing anything external, and a
retrospective tool should not tell a third party who is reading it.

To change the weights, edit the family list below, run it, and regenerate
`assets/css/fonts.css` the same way:

```bash
curl -A "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 \
  (KHTML, like Gecko) Chrome/120.0 Safari/537.36" \
  "https://fonts.googleapis.com/css2?family=IBM+Plex+Sans+Thai:wght@400;600&family=Mitr:wght@500;600&display=swap"
```

The user agent matters: without a modern one Google serves TrueType instead of
woff2, which is roughly three times the size.

Keep only the `thai`, `latin` and `latin-ext` subsets. The others — Cyrillic,
Vietnamese — are weight this interface never spends.
