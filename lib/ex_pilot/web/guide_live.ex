defmodule ExPilot.Web.GuideLive do
  @moduledoc "The guide: what everything in the arena is, with its picture."

  use Phoenix.LiveView

  import ExPilot.Web.Components

  alias ExPilot.Guide

  @impl true
  def mount(_params, _session, socket), do: {:ok, assign(socket, sections: Guide.sections())}

  @impl true
  def render(assigns) do
    ~H"""
    <.shell username={@username} current="guide">
      <div class="page-head">
        <h1>Guide</h1>
        <p class="dim">What you will meet in an arena, and the key that uses it.</p>
      </div>
      <div class="guide">
        <section :for={{heading, entries} <- @sections}>
          <h2>{heading}</h2>
          <div class="entries">
            <div :for={entry <- entries} class="card entry">
              <.sprite art={entry.art} />
              <div><b>{entry.name}</b><p>{entry.text}</p></div>
            </div>
          </div>
        </section>
      </div>
    </.shell>
    """
  end
end
