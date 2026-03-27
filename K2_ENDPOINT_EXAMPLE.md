# Joomla 3.5 + K2 endpoint example

If your site uses K2, expose a simple JSON endpoint with K2 item fields.

## Example output (`GET /api/news`)

```json
{
  "data": [
    {
      "id": 101,
      "title": "K2 news title",
      "introtext": "Short text from K2 introtext",
      "fulltext": "<p>Full K2 article HTML</p>",
      "created": "2026-03-27 10:30:00",
      "image": "https://your-site.kz/media/k2/items/cache/your-image_L.jpg"
    }
  ]
}
```

## Minimal SQL source for K2 items

Use table `#__k2_items` with filters:

- `published = 1`
- `trash = 0`
- `access = 1` (or your access logic)

Basic fields:

- `id`
- `title`
- `introtext`
- `fulltext`
- `created`
- `catid`
- `alias`

## Typical PHP flow (high level)

1. Bootstrap Joomla framework.
2. Query `#__k2_items` with ordering `created DESC`.
3. Build full image URL for each item.
4. Return JSON with `Content-Type: application/json`.

Current Flutter app already supports these K2 names:

- `title`
- `introtext`
- `fulltext`
- `created`
- `data` wrapper or direct array root
