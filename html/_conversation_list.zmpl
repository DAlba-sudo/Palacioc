@args l: ZmplValue
@zig {
  const items = l.get("items").?;
  const more = try l.chainRefT(bool, "more");
  const empty = try l.chainRefT(bool, "empty");
}
@if (empty)
<li class="muted">No conversations yet.</li>
@end
@for (items) |c| {
<li><a href="/ui/conversation/{{c.id}}" hx-get="/ui/conversation/{{c.id}}" hx-target="#main" hx-swap="innerHTML" hx-push-url="true"><strong>{{c.title}}</strong> <span class="lang">{{c.language}}</span></a>
<p class="muted">{{c.description}}</p></li>
}
@if (more)
<li class="more"><button type="button" hx-get="/ui/conversations" hx-include=".search" hx-vals='{"p": {{l.next}}}' hx-target="closest li" hx-swap="outerHTML" hx-push-url="false">More</button></li>
@end
