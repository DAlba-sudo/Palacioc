<section class="home">
<h1>Conversations</h1>
<input class="search" type="search" name="q" value="{{$.list.q}}" placeholder="Search conversations" aria-label="Search conversations" hx-get="/ui/conversations" hx-trigger="input changed delay:300ms, search" hx-target="#conversations" hx-swap="innerHTML" hx-push-url="false">
<ul id="conversations" class="conv-list">
@partial conversation_list($.list)
</ul>
<details class="new-conv">
<summary>New conversation</summary>
@partial conversation_form($.form)
</details>
</section>
