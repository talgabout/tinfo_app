# Joomla 3.5 API contract for Flutter

Use these endpoints on your Joomla site:

- `GET /api/news` - news list
- `GET /api/news/{id}` - one article (optional for next step)

## Preferred response for `GET /api/news`

```json
{
  "data": [
    {
      "id": 1254,
      "title": "Article title",
      "summary": "Short summary",
      "content": "Full article text or HTML",
      "image": "https://site.kz/images/news/1254.jpg",
      "published_at": "2026-03-27T09:00:00+06:00"
    }
  ]
}
```

## Also supported by current Flutter parser

The app can already parse these Joomla-style field names:

- `introtext` as summary
- `fulltext` as content
- `publish_up` or `created` as publication date
- root arrays and object wrappers: `data`, `items`, `news`

## Minimal Joomla custom endpoint output example

```json
[
  {
    "id": "1254",
    "title": "Article title",
    "introtext": "Short summary",
    "fulltext": "<p>Full HTML article</p>",
    "publish_up": "2026-03-27 09:00:00"
  }
]
```
