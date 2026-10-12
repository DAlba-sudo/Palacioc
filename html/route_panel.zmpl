<section class="menu">
<h2>Route</h2>
<ol class="route">
@for ($.steps) |s| {
<li><span class="role">{{s.role}}</span> {{s.content}}
@zig {
  const trs = s.get("translations").?;
}
@for (trs) |t| {
<div class="tr"><span class="lang">{{t.language}}</span> {{t.content}}</div>
}
</li>
}
</ol>
<div class="actions">
<button type="button" hx-get="/ui/message/{{$.msg.id}}/menu" hx-target="#panel" hx-swap="innerHTML" hx-push-url="false">Back</button>
</div>
</section>
