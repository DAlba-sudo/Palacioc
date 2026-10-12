<section class="conversation">
<p><a href="/" hx-get="/" hx-target="#main" hx-swap="innerHTML" hx-push-url="true">&larr; All conversations</a></p>
<h1>{{$.page.conv.title}} <span class="lang">{{$.page.conv.language}}</span></h1>
<p class="muted">{{$.page.conv.description}}</p>
<div class="actions">
<button type="button" hx-get="/ui/message/new?conversation_id={{$.page.conv.id}}" hx-target="#panel" hx-swap="innerHTML" hx-push-url="false">Add a root message</button>
<button type="button" class="danger" hx-delete="/ui/conversation/{{$.page.conv.id}}" hx-confirm="Delete this conversation and all its messages?" hx-push-url="false">Delete conversation</button>
</div>
<div class="split">
@partial tree($.page)
<aside id="panel" aria-live="polite"></aside>
</div>
</section>
