@args f: ZmplValue
<form class="form" hx-post="/ui/conversations" hx-target="this" hx-swap="outerHTML" hx-push-url="false" hx-disabled-elt="find button[type=submit]">
<div class="field">
<label for="conv-title">Title</label>
<input id="conv-title" name="title" type="text" value="{{f.title}}">
<p class="field-error">{{f.err_title}}</p>
</div>
<div class="field">
<label for="conv-description">Description</label>
<input id="conv-description" name="description" type="text" value="{{f.description}}">
<p class="field-error">{{f.err_description}}</p>
</div>
<div class="field">
<label for="conv-language">Language you write in</label>
<input id="conv-language" name="source_language" type="text" value="{{f.language}}">
<p class="field-error">{{f.err_language}}</p>
</div>
<div class="field">
<label for="conv-first">First message (optional)</label>
<textarea id="conv-first" name="initial_message" rows="2">{{f.first_message}}</textarea>
<p class="field-error">{{f.err_first_message}}</p>
</div>
<div class="actions"><button type="submit">Create</button></div>
</form>
