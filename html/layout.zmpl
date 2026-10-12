<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="htmx-config" content='{"includeIndicatorStyles":false,"historyCacheSize":0,"responseHandling":[{"code":"204","swap":false},{"code":"[23]..","swap":true},{"code":"[45]..","swap":true,"error":true}]}'>
<title>Palacioc</title>
<link rel="stylesheet" href="/static/app.css">
<script src="/static/htmx-2.0.10.min.js"></script>
</head>
<body>
<header class="top"><a href="/" hx-get="/" hx-target="#main" hx-swap="innerHTML" hx-push-url="true">Palacioc</a></header>
<div id="flash" role="status" aria-live="polite"></div>
<main id="main">
{{zmpl.content}}
</main>
</body>
</html>
