@args tv: ZmplValue
@zig {
  const rows = tv.get("rows").?;
  const empty = try tv.chainRefT(bool, "empty");
}
<div id="tree" hx-get="/ui/conversation/{{tv.conv.id}}/tree" hx-trigger="tree-changed from:body" hx-target="this" hx-swap="outerHTML" hx-push-url="false">
@if (empty)
<p class="muted">No messages yet.</p>
@end
<ul class="tree">
@for (rows) |row| {
<li class="msg" style="--depth: {{row.depth}}">
<button type="button" class="bubble" hx-get="/ui/message/{{row.id}}/menu" hx-target="#panel" hx-swap="innerHTML" hx-push-url="false"><span class="role">{{row.role}}</span> {{row.content}}</button>
@zig {
  const trs = row.get("translations").?;
}
@for (trs) |t| {
<div class="tr"><span class="lang">{{t.language}}</span> {{t.content}}
<button type="button" class="link" hx-get="/ui/translation/{{t.id}}/edit" hx-target="#panel" hx-swap="innerHTML" hx-push-url="false">edit</button>
<button type="button" class="link" hx-delete="/ui/translation/{{t.id}}" hx-confirm="Delete this translation?" hx-target="#panel" hx-swap="innerHTML" hx-push-url="false">delete</button></div>
}
</li>
}
</ul>
</div>
