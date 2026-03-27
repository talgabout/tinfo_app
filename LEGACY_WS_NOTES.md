# Legacy ws integration notes

This Flutter app is now wired for old Joomla/K2 ws endpoints.

## Configure base URL

Open `lib/main.dart` and set:

- `NewsApiService._wsBaseUrl` to your real domain, for example:
  - `https://tinfo.kz/ws`
- `NewsApiService._defaultCatId` to the category id you want as feed root.

## Endpoint used by app

- `GET /ws/getArticles.php?catId={id}&page=0&isparent=1`

## Legacy response features already supported

- Root array response
- Empty response map `{ "status": false }`
- K2 fields: `title`, `introtext`, `fulltext`, `created`
- Legacy image key: `featureImg`

## Important security note

Your old archive contains plain DB credentials in `config.php`.
Rotate DB password and remove credentials from public/shared archives.
