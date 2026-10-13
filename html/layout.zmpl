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
<div id="flash" role="status" aria-live="polite"></div>
{{zmpl.content}}
<script>
(function () {
  var log = function () { return document.getElementById('chat-log'); };
  var down = function () { var l = log(); if (l) l.scrollTop = l.scrollHeight; };
  // Mobile shows one pane at a time; the tabs, bubbles and edit links carry data-pane.
  var setPane = function (pane) {
    var shell = document.getElementById('shell');
    if (!shell) return;
    shell.dataset.pane = pane;
    shell.querySelectorAll('.tabs button').forEach(function (b) {
      b.setAttribute('aria-pressed', String(b.dataset.pane === pane));
    });
  };
  document.addEventListener('click', function (e) {
    var t = e.target.closest('[data-pane]');
    if (!t) return;
    setPane(t.dataset.pane);
    if (t.dataset.focus) {
      var f = document.getElementById(t.dataset.focus);
      if (f) f.focus();
    }
  });
  // Enter sends, Shift+Enter inserts a newline.
  document.addEventListener('keydown', function (e) {
    var t = e.target;
    if (t.id === 'compose-text' && e.key === 'Enter' && !e.shiftKey && !e.isComposing) {
      e.preventDefault();
      t.form.requestSubmit();
    }
  });
  // Sent: clear the box, keep focus, show the newest message.
  document.body.addEventListener('chat-sent', function () {
    var t = document.getElementById('compose-text');
    if (t) { t.value = ''; t.focus(); }
    down();
  });
  // Translation saved: back into the textarea for the next one.
  document.body.addEventListener('tr-saved', function () {
    var t = document.getElementById('tr-content');
    if (t) t.focus();
  });
  document.addEventListener('htmx:afterSettle', function () {
    var s = document.getElementById('shell');
    if (s) setPane(s.dataset.pane);
  });
  document.addEventListener('DOMContentLoaded', function () {
    down();
    var s = document.getElementById('shell');
    if (s) setPane(s.dataset.pane);
  });
})();
</script>
</body>
</html>
