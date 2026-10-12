<section class="menu">
<h2>Message</h2>
<p><span class="role">{{$.msg.role}}</span> {{$.msg.content}}</p>
<div class="actions col">
<button type="button" hx-get="/ui/translation/new?message_id={{$.msg.id}}" hx-target="#panel" hx-swap="innerHTML" hx-push-url="false">Add a translation</button>
<button type="button" hx-get="/ui/message/new?parent_id={{$.msg.id}}" hx-target="#panel" hx-swap="innerHTML" hx-push-url="false">Add a new message (new branch)</button>
<button type="button" hx-get="/ui/message/{{$.msg.id}}/edit" hx-target="#panel" hx-swap="innerHTML" hx-push-url="false">Edit</button>
<button type="button" hx-get="/ui/message/{{$.msg.id}}/route" hx-target="#panel" hx-swap="innerHTML" hx-push-url="false">Show route</button>
<button type="button" class="danger" hx-delete="/ui/message/{{$.msg.id}}" hx-confirm="Delete this message and every reply below it?" hx-target="#panel" hx-swap="innerHTML" hx-push-url="false">Delete</button>
<button type="button" hx-get="/ui/panel/close" hx-target="#panel" hx-swap="innerHTML" hx-push-url="false">Close</button>
</div>
</section>
